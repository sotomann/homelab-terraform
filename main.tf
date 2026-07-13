resource "proxmox_virtual_environment_container" "test" {
  description = "Creado por Terraform - prueba"
  node_name   = "proxmox"
  vm_id       = 199

  unprivileged = true

  initialization {
    hostname = "tf-test01"

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
    template_file_id = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
    type              = "debian"
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = "local-lvm"
    size         = 4
  }

  started = true
}
