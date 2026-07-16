locals {
  # LXC: la IP ya está declarada, solo le quitamos el /24
  linux_hosts = {
    for k, v in var.contenedores : k => {
      name = v.hostname
      ip   = split("/", v.ip)[0]
    }
  }
  # VMs Windows: la IP se lee del propio recurso ya creado (guest-agent),
  # filtrando localhost (127.x) y autoasignación sin DHCP (169.254.x)
  windows_hosts = {
    for k, v in var.vms_windows : k => {
      name = v.name
      ip = try([
        for addr in flatten(proxmox_virtual_environment_vm.windows[k].ipv4_addresses) :
        addr if !startswith(addr, "127.") && !startswith(addr, "169.254.")
      ][0], null)
    }
  }
}
