// macOS / Linux / Windows desktop notifications for opencode sessions.
// Fires for every session running on this machine, so you no longer have to
// switch between terminals to find out which one finished / needs input:
//
//   - session.idle     → "Finished"          (response completed)
//   - permission.asked → "Needs authorization"
//   - question.asked   → "Has a question"
//   - session.error    → "Error"
//
// The session title is fetched from the SDK so the notification tells you
// WHICH session needs attention.
//
// Delivery per platform (chosen automatically via process.platform):
//   - macOS:   osascript "display notification" (silent; set Script Editor's
//              notification style to "Alerts" in System Settings →
//              Notifications to keep them visible until dismissed)
//   - Linux:   notify-send (needs libnotify installed and a running
//              notification daemon, e.g. GNOME/KDE or dunst/mako)
//   - Windows: PowerShell toast notification (WinRT via Windows PowerShell
//              5.1, which ships with Windows; title/body are passed via
//              env vars to avoid quoting issues)
// Headless machines (no desktop session) are deliberately not covered —
// other/unknown platforms silently do nothing.
//
// Remove this file (or rename it to notify.js.disabled) to turn it off.

// PowerShell toast script: reads the notification text from env vars
// OC_TITLE / OC_BODY so no quoting/escaping is needed in the command line.
const PS_TOAST = `
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$null = $x.GetElementsByTagName('text').Item(0).AppendChild($x.CreateTextNode($env:OC_TITLE))
$null = $x.GetElementsByTagName('text').Item(1).AppendChild($x.CreateTextNode($env:OC_BODY))
[void][Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('opencode').Show([Windows.UI.Notifications.ToastNotification]::new($x))
`

export const NotifyPlugin = async ({ client, $ }) => {
  const platform = process.platform

  // AppleScript string escaping: backslashes, double quotes, newlines (macOS).
  const esc = (s) =>
    String(s ?? "")
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"')
      .replace(/\r?\n/g, " ")

  async function sessionTitle(sessionID) {
    if (!sessionID) return "Session"
    try {
      const res = await client.session.get({ path: { id: sessionID } })
      const data = res?.data ?? res
      return data?.title || "Session"
    } catch {
      return "Session"
    }
  }

  async function notify(subtitle, body) {
    const text = String(body ?? "").replace(/\r?\n/g, " ")
    try {
      if (platform === "darwin") {
        const script = `display notification "${esc(text)}" with title "opencode" subtitle "${esc(subtitle)}"`
        await $`osascript -e ${script}`
      } else if (platform === "linux") {
        // notify-send: bold first line (summary) + body text below.
        await $`notify-send -a opencode -u normal ${`opencode: ${subtitle}`} ${text}`
      } else if (platform === "win32") {
        await $`powershell -NoProfile -NonInteractive -Command ${PS_TOAST}`.env({
          OC_TITLE: `opencode: ${subtitle}`,
          OC_BODY: text,
        })
      }
      // Other platforms (headless boxes etc.): silently do nothing.
    } catch {
      // Never let a failing notification break the session loop.
    }
  }

  return {
    event: async ({ event }) => {
      try {
        const type = event?.type
        const p = event?.properties || {}
        switch (type) {
          case "session.idle":
            await notify("Finished", await sessionTitle(p.sessionID))
            break
          case "permission.asked": {
            const what = typeof p.title === "string" && p.title ? `: ${p.title}` : ""
            await notify("Needs authorization", (await sessionTitle(p.sessionID)) + what)
            break
          }
          case "question.asked":
            await notify("Has a question", await sessionTitle(p.sessionID))
            break
          case "session.error": {
            const msg = typeof p.error === "string" ? p.error : p.error?.message
            await notify("Error", msg ? `${await sessionTitle(p.sessionID)}: ${msg}` : await sessionTitle(p.sessionID))
            break
          }
        }
      } catch {
        // Never break the session on notification errors.
      }
    },
  }
}
