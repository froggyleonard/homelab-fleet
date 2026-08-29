terraform {
  required_version = ">= 1.9.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

# Auth via environment:
#   PROXMOX_VE_ENDPOINT  = https://<pve-host>:8006
#   PROXMOX_VE_API_TOKEN = user@realm!tokenid=uuid
provider "proxmox" {
  insecure = true # self-signed cert on the single homelab node
}

locals {
  node     = "pve"
  gw_infra = "${var.net_prefix}.100.1"
  gw_apps  = "${var.net_prefix}.110.1"
  gw_user  = "${var.net_prefix}.20.1"
  ssh_keys = var.ssh_public_keys
  template = 9000

  # Dev workstation (task 013) — USER VLAN so the desktop reaches it without
  # cross-VLAN rules. Static IP below the DHCP pool (.100-.200). Tagged "dev",
  # not "fleet": cluster automation must never pick it up.
  dev = {
    dev-ws1 = { vmid = 220, cores = 8, mem = 16384, vlan = 20, ip = "${var.net_prefix}.20.21", gw = local.gw_user, os_gb = 60, extra = [] }
  }

  fleet = {
    infra-cp1 = { vmid = 201, cores = 2, mem = 6144, vlan = 100, ip = "${var.net_prefix}.100.11", gw = local.gw_infra, os_gb = 25, extra = [] }
    infra-cp2 = { vmid = 202, cores = 2, mem = 6144, vlan = 100, ip = "${var.net_prefix}.100.12", gw = local.gw_infra, os_gb = 25, extra = [] }
    infra-cp3 = { vmid = 203, cores = 2, mem = 6144, vlan = 100, ip = "${var.net_prefix}.100.13", gw = local.gw_infra, os_gb = 25, extra = [] }
    apps-cp1  = { vmid = 211, cores = 2, mem = 4096, vlan = 110, ip = "${var.net_prefix}.110.11", gw = local.gw_apps, os_gb = 25, extra = [] }
    apps-w1 = { vmid = 212, cores = 6, mem = 12288, vlan = 110, ip = "${var.net_prefix}.110.12", gw = local.gw_apps, os_gb = 30, extra = [
      { datastore = "local-zfs", interface = "scsi1", size_gb = 20 }, # PostgreSQL (SSD)
      # Longhorn replica data. Excluded from vzdump: a VM-level snapshot of a
      # live replica is crash-consistent at best, the data is already replicated
      # across both workers, and including it costs 200G of archive per night for
      # something nobody should restore that way.
      { datastore = "Media", interface = "scsi2", size_gb = 200, backup = false },
    ] }
    apps-w2 = { vmid = 213, cores = 6, mem = 16384, vlan = 110, ip = "${var.net_prefix}.110.13", gw = local.gw_apps, os_gb = 30, extra = [
      # Longhorn replica data — excluded from vzdump, see apps-w1 above.
      { datastore = "Media", interface = "scsi1", size_gb = 200, backup = false },
    ] }
  }
}

# Ubuntu 24.04 (Noble) cloud image → template 9000.
# content_type "import" (not "iso") so the VM disk can import_from it;
# the .qcow2 name is required for PVE to accept it as an importable image.
# overwrite=false: the /current/ URL is a moving daily target — without this,
# every upstream rebuild forces a re-download that replaces the datastore file
# and re-imports the template disk (and the size HEAD runs on the pve node,
# stalling every plan). The stored image stays authoritative once downloaded.
resource "proxmox_download_file" "noble" {
  node_name    = local.node
  datastore_id = "local"
  content_type = "import"
  file_name    = "noble-server-cloudimg-amd64.qcow2"
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  overwrite    = false
}

resource "proxmox_virtual_environment_vm" "template" {
  name      = "ubuntu-2404-cloudinit"
  vm_id     = local.template
  node_name = local.node
  template  = true
  tags      = ["fleet", "template"]

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  network_device {
    bridge   = "vmbr0"
    firewall = false
  }

  disk {
    datastore_id = "local-zfs"
    interface    = "scsi0"
    import_from  = proxmox_download_file.noble.id
    size         = 10
    discard      = "on"
    ssd          = true
  }

  initialization {
    datastore_id = "local-zfs"
  }

  operating_system {
    type = "l26"
  }

  # A template never boots, so the guest agent never reports these; without
  # this the provider re-plans them as "known after apply" on every run and
  # `plan -detailed-exitcode` can never return 0
  # (bpg/terraform-provider-proxmox#1494).
  # Terraform warns each entry is redundant ("has no effect" on computed
  # attributes) — empirically false with this provider: same state, plan
  # exits 2 without the block and 0 with it (verified 2026-08-19). The three
  # warnings are expected; removing the block brings the phantom diff back.
  lifecycle {
    ignore_changes = [ipv4_addresses, ipv6_addresses, network_interface_names]
  }
}

module "fleet" {
  source   = "../../modules/vm"
  for_each = { for name, vm in local.fleet : name => vm if var.apps_enabled || !startswith(name, "apps-") }

  name            = each.key
  vmid            = each.value.vmid
  node_name       = local.node
  template_id     = proxmox_virtual_environment_vm.template.vm_id
  cores           = each.value.cores
  memory_mib      = each.value.mem
  vlan_tag        = each.value.vlan
  ip              = each.value.ip
  gateway         = each.value.gw
  os_disk_gb      = each.value.os_gb
  extra_disks     = each.value.extra
  ssh_public_keys = local.ssh_keys
}

module "dev" {
  source   = "../../modules/vm"
  for_each = local.dev

  name            = each.key
  vmid            = each.value.vmid
  node_name       = local.node
  template_id     = proxmox_virtual_environment_vm.template.vm_id
  tags            = ["dev"]
  cores           = each.value.cores
  memory_mib      = each.value.mem
  vlan_tag        = each.value.vlan
  ip              = each.value.ip
  gateway         = each.value.gw
  os_disk_gb      = each.value.os_gb
  extra_disks     = each.value.extra
  ssh_public_keys = local.ssh_keys
}
