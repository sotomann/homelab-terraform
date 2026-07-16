resource "proxmox_virtual_environment_vm" "windows" {
  for_each = var.vms_windows

  name        = each.value.name
  description = "Creado por Terraform (clonado de plantilla)"
  node_name   = "proxmox"
  vm_id       = each.value.vm_id

  clone {
    vm_id = each.value.template_vm_id
    full  = true
  }

  lifecycle {
    ignore_changes = [clone]
  }

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk
  }

  network_device {
    bridge = each.value.bridge
  }

  scsi_hardware = "virtio-scsi-single"

  machine = "pc-i440fx-11.0"

  operating_system {
    type = "win11"
  }

  started = each.value.started
}
