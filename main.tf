resource "proxmox_virtual_environment_container" "lxc" {
  for_each = var.contenedores

  description = "Creado por Terraform"
  node_name   = "proxmox"
  vm_id       = each.value.vm_id

  unprivileged = true

  initialization {
    hostname = each.value.hostname

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.ip == "dhcp" ? null : each.value.gateway
      }
    }

    user_account {
      keys = [trimspace(file("~/.ssh/id_ed25519.pub"))]
    }
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = each.value.template
    type              = "debian"
  }

  cpu {
    cores = var.flavors[each.value.flavor].cores
  }

  memory {
    dedicated = var.flavors[each.value.flavor].memory
  }

  disk {
    datastore_id = "local-lvm"
    size         = var.flavors[each.value.flavor].disk
  }

  features {
    nesting = each.value.nesting
  }

  started = true
}

