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
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKuCBorebkpFt5+CXsOy8/YTx8mre16ZD/ImqPiiRv+T personal-laptop",
    # Orchestrator seat (dev-ws1, task 014). Affects cloud-init on rebuild only;
    # existing nodes got this key via ansible/seat-key.yaml. Adding it changes
    # user-data for every VM — expect a plan diff after merge; apply rides the
    # next gated apply cycle.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHnZfeKhSdaX1ceZX/jPdUkhfpTVE1evbj9z00GT99lc ops@dev-ws1 seat 2026-08-17",
  ]
}

variable "apps_enabled" {
  description = "Create the cluster-apps VMs (211-213). Flipped true at P5 (2026-07-18) after Gate 2 teardown freed the rpool space."
  type        = bool
  default     = true
}
