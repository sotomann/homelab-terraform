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

variable "flavors" {
  description = "Perfiles de tamaño reutilizables"
  type = map(object({
    cores  = number
    memory = number # MB
    disk   = number # GB
  }))
  default = {
    basico  = { cores = 1, memory = 1024, disk = 10 }
    pro     = { cores = 2, memory = 2048, disk = 20 }
    supreme = { cores = 3, memory = 3072, disk = 30 }
    extreme = { cores = 4, memory = 4096, disk = 40 }
  }
}

variable "contenedores" {
  description = "LXC a desplegar: clave = nombre lógico, valor = sus datos"
  type = map(object({
    vm_id    = number
    hostname = string
    flavor   = string       # debe existir en var.flavors
    ip       = string       # CIDR, ej. "192.168.1.50/24", o "dhcp"
    gateway  = optional(string)
    template = optional(string, "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst")
    nesting = optional(bool, false)
 }))
}

variable "vms_windows" {
  description = "VMs Windows a desplegar, clonadas desde una plantilla ya preparada"
  type = map(object({
    vm_id          = number
    name           = string
    template_vm_id = number
    cores          = optional(number, 2)
    memory         = optional(number, 4096)
    disk           = optional(number, 60)
    bridge         = optional(string, "vmbr0")
  }))
  default = {}
}
