# Proxmox: provisioning a dotfiles-ready VM

Not managed by chezmoi (see `.chezmoiignore`) - this provisions a VM
*before* chezmoi exists on it. `proxmox-user-data.yaml` is the cloud-init
config; everything below is standard Proxmox `qm` usage, adapt VMID/storage/
bridge names to your setup. Unlike the rest of this repo, this hasn't been
tested against a real Proxmox instance - it's the documented procedure, not
something verified end-to-end.

## One-time: get the cloud image and stage the snippet

```sh
# On the Proxmox host:
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img \
  -O /var/lib/vz/template/iso/noble-server-cloudimg-amd64.img

mkdir -p /var/lib/vz/snippets
scp cloud-init/proxmox-user-data.yaml root@<proxmox-host>:/var/lib/vz/snippets/
```

(`local:snippets` needs to be enabled for the storage - Datacenter → Storage
→ local → Edit → Content → check "Snippets", if it isn't already.)

## Create the VM

```sh
VMID=<pick one, e.g. 200>

qm create $VMID --name dotfiles-server --memory 2048 --cores 2 \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --ostype l26

qm importdisk $VMID /var/lib/vz/template/iso/noble-server-cloudimg-amd64.img local-lvm
qm set $VMID --scsi0 local-lvm:vm-$VMID-disk-0
qm set $VMID --boot c --bootdisk scsi0
qm set $VMID --ide2 local-lvm:cloudinit
qm set $VMID --serial0 socket --vga serial0   # cloud images want a serial console
qm set $VMID --cicustom "user=local:snippets/proxmox-user-data.yaml"
qm set $VMID --ipconfig0 ip=dhcp              # or a static IP, see `qm set --help`

qm resize $VMID scsi0 +18G   # cloud images ship tiny (~2GB) disks

qm start $VMID
```

## After boot

Find its IP (Proxmox UI → VM → Summary, or your DHCP server/router), then:

```sh
ssh angel@<vm-ip>
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply angelnu/dotfiles
```

Only the age private key prompt remains — `role` and `prune` are already
answered by the cloud-init user-data. Paste the key directly at the prompt,
never into a chat/LLM session.
