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
