variable "net_prefix" {
  description = "First two octets of the lab network (e.g. \"10.0\"). No default on purpose — set it in terraform.tfvars (gitignored, see terraform.tfvars.example) so real addressing never lands in git."
  type        = string

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}$", var.net_prefix))
    error_message = "net_prefix must be the first two octets, e.g. \"10.0\"."
  }
}

variable "ssh_public_keys" {
  description = "SSH public keys injected into every fleet VM via cloud-init"
  type        = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKuCBorebkpFt5+CXsOy8/YTx8mre16ZD/ImqPiiRv+T lehnerfreddy@gmail.com",
  ]
}

variable "apps_enabled" {
  description = "Create the cluster-apps VMs (211-213). Flipped true at P5 (2026-07-18) after Gate 2 teardown freed the rpool space."
  type        = bool
  default     = true
}
