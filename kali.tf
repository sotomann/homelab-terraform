resource "proxmox_virtual_environment_vm" "kali" {
  name        = "kali"
  description = "Kali Linux — pentest/forense"
  node_name   = "proxmox"
  vm_id       = 300
  started     = var.kali_started
  cpu {
    cores = 2
    type  = "host"
  }
  memory {
    dedicated = 4096
  }
  disk {
    datastore_id = "local-lvm"
    import_from  = "local:import/kali-linux-2026.2-qemu-amd64.qcow2"
    interface    = "scsi0"
    size         = 92
  }
  scsi_hardware = "virtio-scsi-single"
  network_device {
    bridge = "vmbr0"
  }
  agent {
    enabled = true
  }
  boot_order = ["scsi0"]
}
