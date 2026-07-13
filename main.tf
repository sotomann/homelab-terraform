resource "proxmox_virtual_environment_container" "test" {
  description = "Creado por Terraform"
  node_name   = "proxmox"
  vm_id       = var.ct_vm_id

  unprivileged = true

  initialization {
    hostname = var.ct_hostname

    ip_config {
      ipv4 {
        address = "dhcp"
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
    template_file_id = var.ct_template
    type              = "debian"
  }

  cpu {
    cores = var.ct_cores
  }

  memory {
    dedicated = var.ct_memory
  }

  disk {
    datastore_id = "local-lvm"
    size         = var.ct_disk_size
  }

  started = true
}
