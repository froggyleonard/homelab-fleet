# terraform

- `modules/vm` — one Proxmox VM from the cloud-init template (bpg provider)
- `envs/pve` — the fleet: template 9000 (Ubuntu 24.04) + 6 VMs (201–203 infra, 211–213 apps)

Auth is environment-only (`PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`) — no
credentials in this repo, ever. State is local and gitignored (single operator);
remote state is a deliberate non-goal for now.

Real network addressing is also environment-only: copy
`envs/pve/terraform.tfvars.example` to `terraform.tfvars` (gitignored) and set
`net_prefix` to the lab's first two octets.

```sh
cd envs/pve
cp terraform.tfvars.example terraform.tfvars  # then edit net_prefix
terraform init
terraform plan
```
