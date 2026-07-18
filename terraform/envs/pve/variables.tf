variable "ssh_public_keys" {
  description = "SSH public keys injected into every fleet VM via cloud-init"
  type        = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKuCBorebkpFt5+CXsOy8/YTx8mre16ZD/ImqPiiRv+T lehnerfreddy@gmail.com",
  ]
}

variable "apps_enabled" {
  description = "Create the cluster-apps VMs (211-213). Stays false until P5 — the apps cluster builds only after the Gate 2 teardown frees rpool space."
  type        = bool
  default     = false
}
