resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory_generado.ini"
  content = templatefile("${path.module}/templates/inventory.tpl", {
    linux_hosts   = local.linux_hosts
    windows_hosts = local.windows_hosts
  })
}
