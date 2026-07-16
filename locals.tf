locals {
  linux_hosts = {
    for k, v in var.contenedores : k => {
      name = v.hostname
      ip   = split("/", v.ip)[0]
    }
  }

  windows_hosts_raw = {
    for k, v in var.vms_windows : k => {
      name = v.name
      ip = try([
        for addr in flatten(proxmox_virtual_environment_vm.windows[k].ipv4_addresses) :
        addr if !startswith(addr, "127.") && !startswith(addr, "169.254.")
      ][0], null)
    }
  }

  windows_hosts = {
    for k, v in local.windows_hosts_raw : k => v if v.ip != null
  }
}
