variable "ssh_public_keys" {
  description = "SSH public keys injected into every fleet VM via cloud-init"
  type        = list(string)
}
