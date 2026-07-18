# terraform

- `modules/vm` — one Proxmox VM from the cloud-init template (bpg provider)
- `envs/pve` — the fleet: template 9000 (Ubuntu 24.04) + 6 VMs (201–203 infra, 211–213 apps)

Auth is environment-only (`PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`) — no
credentials in this repo, ever. State is local and gitignored (single operator);
remote state is a deliberate non-goal for now.

```sh
cd envs/pve
terraform init
terraform plan -var 'ssh_public_keys=["ssh-ed25519 AAAA..."]'
```
