terraform {
  required_version = ">= 1.9.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  vm_id     = var.vmid
  node_name = var.node_name
  tags      = var.tags

  clone {
    vm_id = var.template_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mib
    floating  = var.balloon_min_mib
  }

  network_device {
    bridge   = "vmbr0"
    vlan_id  = var.vlan_tag
    firewall = false
  }

  disk {
    datastore_id = var.os_datastore
    interface    = "scsi0"
    size         = var.os_disk_gb
    discard      = "on"
    ssd          = true
  }

  dynamic "disk" {
    for_each = var.extra_disks
    content {
      datastore_id = disk.value.datastore
      interface    = disk.value.interface
      size         = disk.value.size_gb
      discard      = "on"
    }
  }

  initialization {
    datastore_id = var.os_datastore
    ip_config {
      ipv4 {
        address = "${var.ip}/24"
        gateway = var.gateway
      }
    }
    user_account {
      username = var.ci_user
      keys     = var.ssh_public_keys
    }
  }

  operating_system {
    type = "l26"
  }

  on_boot = true
}
