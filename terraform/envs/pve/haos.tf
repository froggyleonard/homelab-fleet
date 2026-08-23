# Home Assistant OS (task 020, phase M3).
#
# Deliberately a standalone resource rather than an entry in the local.fleet
# clone map: HAOS is an appliance image with its own partition layout and no
# cloud-init, so it shares nothing with the Ubuntu template path.
#
# The provisioning artifact is prepared by hand on the pve node and lives at
# local:import/haos_ova-18.2.qcow2. proxmox_download_file cannot fetch it
# declaratively — HAOS publishes the qcow2 only as .xz, and this provider's
# decompression_algorithm accepts gz | lzo | zst | bz2 (re-verified against the
# installed 0.111.1 schema on 2026-08-23, not carried over from the plan).
#
# The 18.2 pin governs the PROVISIONING ARTIFACT only. HAOS self-manages OS and
# core updates in-app after onboarding, so the running version legitimately
# drifts from this number and that is not pin rot.
resource "proxmox_virtual_environment_vm" "haos" {
  name      = "haos"
  vm_id     = 230
  node_name = local.node
  tags      = ["home"]

  # Restart with the host — this is the house's automation brain, not a
  # workload something else will reconcile.
  on_boot = true

  # HAOS ships the qemu guest agent, so this reports for real (unlike the
  # template) and no ignore_changes blanket is needed.
  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  # q35 + OVMF per the HA installation docs. Secure boot MUST be off:
  # pre_enrolled_keys = false is what keeps the Microsoft keys out and lets the
  # unsigned HAOS bootloader run. Enrolling keys here is the classic way to end
  # up at a UEFI shell instead of an installed system.
  machine = "q35"
  bios    = "ovmf"

  efi_disk {
    datastore_id      = "local-zfs"
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  # VLAN 80 (General). Addressing is a DHCP reservation on OPNsense keyed to
  # the MAC exported below — nothing about the address belongs in this repo.
  network_device {
    bridge   = "vmbr0"
    vlan_id  = 80
    firewall = false
  }

  # SCSI on a virtio-scsi controller, per the HA docs' own virt-install recipe
  # (bus=scsi, model=virtio-scsi).
  scsi_hardware = "virtio-scsi-pci"

  disk {
    datastore_id = "local-zfs"
    interface    = "scsi0"
    import_from  = "local:import/haos_ova-18.2.qcow2"
    size         = 32
    discard      = "on"
    ssd          = true
  }

  operating_system {
    type = "l26"
  }

  # No initialization{} block on purpose: HAOS is not cloud-init driven, and
  # attaching a cloud-init drive to it does nothing useful.
}

# The OPNsense DHCP reservation is keyed to this. Note it changes if the VM is
# ever destroyed and recreated — re-point the reservation if that happens.
output "haos_mac_address" {
  description = "MAC of the HAOS VM, for the OPNsense DHCP reservation."
  value       = proxmox_virtual_environment_vm.haos.network_device[0].mac_address
}
