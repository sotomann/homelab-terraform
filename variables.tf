variable "proxmox_endpoint" {
  description = "URL de la API de Proxmox VE"
  type        = string
  default     = "https://192.168.1.10:8006/"
}

variable "proxmox_api_token" {
  description = "Token de terraform@pve (formato user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "ct_vm_id" {
  description = "ID del contenedor en Proxmox"
  type        = number
}

variable "ct_hostname" {
  description = "Hostname del contenedor"
  type        = string
}

variable "ct_cores" {
  description = "Núcleos de CPU"
  type        = number
  default     = 1
}

variable "ct_memory" {
  description = "RAM en MB"
  type        = number
  default     = 512
}

variable "ct_disk_size" {
  description = "Tamaño del disco raíz en GB"
  type        = number
  default     = 4
}

variable "ct_template" {
  description = "Plantilla LXC a usar"
  type        = string
  default     = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
}
