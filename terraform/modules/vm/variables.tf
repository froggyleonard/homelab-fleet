variable "name" {
  type = string
}

variable "vmid" {
  type = number
}

variable "node_name" {
  type    = string
  default = "pve"
}

variable "template_id" {
  type = number
}

variable "tags" {
  type    = list(string)
  default = ["fleet"]
}

variable "cores" {
  type = number
}

variable "memory_mib" {
  type = number
}

variable "balloon_min_mib" {
  type    = number
  default = 0
}

variable "vlan_tag" {
  type = number
}

variable "os_datastore" {
  type    = string
  default = "local-zfs"
}

variable "os_disk_gb" {
  type = number
}

variable "extra_disks" {
  type = list(object({
    datastore = string
    interface = string
    size_gb   = number
  }))
  default = []
}

variable "ip" {
  description = "IPv4 address without CIDR suffix"
  type        = string
}

variable "gateway" {
  type = string
}

variable "ci_user" {
  type    = string
  default = "ops"
}

variable "ssh_public_keys" {
  type = list(string)
}
