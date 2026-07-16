# Homelab — Aprovisionamiento con Terraform

Aprovisionamiento de LXC, VMs Windows y una VM Kali Linux en Proxmox VE mediante Terraform, usando el provider [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest). Complementa a [`homelab-ansible`](https://github.com/sotomann/homelab-ansible): Terraform crea la máquina, Ansible la configura.

## Contexto

Homelab sobre un HP EliteDesk 800 G4 Mini (i5-8400T, 6 núcleos, 16 GB RAM) con Proxmox VE 9.2. Antes de este proyecto, las máquinas se creaban a mano desde el panel; el objetivo es declarar la infraestructura en código, versionada y reproducible.

## Decisiones de diseño

- **Provider `bpg/proxmox` en vez de `Telmate/proxmox`**: Telmate tiene un bug abierto de permisos (`VM.Monitor`) en Proxmox VE 9.x. bpg está activamente mantenido y soporta PVE 9.2 de forma oficial.
- **Usuario y token dedicados** (`terraform@pve`), con un rol acotado en vez de `root@pam`. Mínimo privilegio: si el token se filtra, el daño se limita a gestión de VMs/LXC.
- **`insecure = true`** en el provider: el certificado Let's Encrypt del nodo está emitido para `homelab.hjs.es` (vía Cloudflare Tunnel), no para la IP interna `192.168.1.10` que usa Terraform, así que la verificación TLS por hostname fallaría aunque el cert sea válido. Tráfico solo dentro de la LAN.
- **IP fija — dos mecanismos distintos según el tipo de recurso**: en los LXC, Proxmox inyecta la IP directamente (declarada en `contenedores`). En las VMs Windows no se usa cloud-init/Cloudbase-Init — Windows sigue usando DHCP o IP estática manual dentro del guest, y la reserva se gestiona con la MAC de la VM cuando el rango del router lo permite.
- **Perfiles de tamaño (`flavors`)**: `minimo` (1 core/512MB/2GB), `basico` (1/1024MB/10GB), `pro` (2/2048MB/20GB), `supreme` (3/3072MB/30GB), `extreme` (4/4096MB/40GB). `minimo` se añadió específicamente para LXC de un solo binario (ttyd) — `basico` sobraba de largo en disco para eso, y en un SSD de 240GB compartido entre todo el homelab, 8GB de diferencia por máquina importa.
- **Kali como VM, no LXC**: necesita sockets raw, modo monitor Wi-Fi y acceso a dispositivos USB — un LXC comparte kernel con el host y limita o bloquea todo eso. Si algún día corre ahí algo no confiable, la VM aísla a nivel de kernel y el LXC no.
- **`scsi_hardware` y `operating_system` declarados explícitos en `vms.tf`**: tras un `terraform import` de una VM ya existente, el provider rellena estos campos con sus propios valores si no se fijan — un `apply` sin declararlos explícitamente hubiera cambiado el controlador SCSI de una VM Windows en caliente, con riesgo real de dejarla sin arrancar.
- **`started` como campo declarado, no como valor fijo**: `contenedores`, `vms_windows` y la propia Kali (`kali_started`) exponen `started` como atributo — con default `true` para no romper nada existente, pero editable. Antes estaba fijo a `true` en el propio recurso; el problema real: apagar una máquina a mano en Proxmox no cambia lo que Terraform *cree* que debería ser, así que el siguiente `apply` la volvía a encender sin avisar. Con `started` declarado en `terraform.tfvars`, lo real y lo declarado por fin pueden coincidir sin pelear entre sí.
- **`locals.tf` filtra hosts sin IP, no solo evita el crash**: la primera versión usaba `try(..., null)` para que una VM apagada (sin IP de guest-agent) no reventara el `plan` — pero un `null` sigue sin poder interpolarse dentro de `templatefile()`, así que el error solo se aplazaba hasta que una VM Windows *de verdad* estuviera apagada en un `plan`. La solución final separa "calcular la IP" de "decidir si el host entra en el inventario": un segundo `for` filtra por `if v.ip != null` antes de pasarlo a la plantilla. Una máquina apagada simplemente no aparece en el inventario — correcto, porque no tiene sentido que Ansible intente conectar a una IP que no existe ahora mismo.

## Requisitos

- Terraform >= 1.9
- Proxmox VE 9.x
- Usuario `terraform@pve` con token de API (ver más abajo)
- Para VMs Windows: una plantilla ya preparada en Proxmox
- Para Kali: la imagen QEMU pre-construida en el storage `local`, content type `import`

## Estructura

```
├── providers.tf              # Provider bpg/proxmox
├── variables.tf              # flavors, contenedores, vms_windows, kali_started
├── lxc.tf                    # Recurso: LXC (for_each sobre var.contenedores)
├── vms.tf                    # Recurso: VMs Windows (for_each sobre var.vms_windows)
├── kali.tf                   # Recurso: VM Kali Linux (máquina única, imagen QEMU importada)
├── locals.tf                 # linux_hosts / windows_hosts, filtrando hosts sin IP
├── inventario.tf             # local_file.ansible_inventory (templatefile)
├── templates/
│   └── inventory.tpl         # Plantilla del inventario Ansible
├── terraform.tfvars.example  # Plantilla de valores (sin datos reales)
├── terraform.tfvars          # Valores reales — NO se sube a git
├── inventory_generado.ini    # Generado por local_file — NO se sube a git
└── .gitignore
```

## Cómo usar este repo según lo que quieras desplegar

| Quiero...                       | Edita esta variable en `.tfvars`                     | Recurso definido en |
| -------------------------------- | ----------------------------------------------------- | -------------------- |
| LXC Linux (uno o varios)         | `contenedores`                                         | `lxc.tf`             |
| VM Windows (una o varias)        | `vms_windows`                                          | `vms.tf`             |
| Kali Linux                       | no aplica — máquina única, sin flavor ni mapa           | `kali.tf`            |
| Apagar una máquina sin que el próximo `apply` la reencienda | `started = false` en su entrada (o `kali_started = false`) | `variables.tf` (tipo) + el recurso correspondiente |
| Crear/tocar solo una máquina, sin arrastrar el resto | nada — usa `terraform apply -target=...` (ver más abajo) | — |

Terraform no distingue por nombre de archivo — lee todos los `.tf` del directorio y los trata como uno solo.

## Preparar el token en Proxmox

```
pveum role add Terraform -privs "Realm.AllocateUser,VM.PowerMgmt,VM.GuestAgent.Unrestricted,Sys.Console,Sys.Audit,Sys.AccessNetwork,VM.Config.Cloudinit,VM.Replicate,Pool.Allocate,SDN.Audit,Realm.Allocate,SDN.Use,Mapping.Modify,VM.Config.Memory,VM.GuestAgent.FileSystemMgmt,VM.Allocate,SDN.Allocate,VM.Console,VM.Clone,VM.Backup,Datastore.AllocateTemplate,VM.Snapshot,VM.Config.Network,Sys.Incoming,Sys.Modify,VM.Snapshot.Rollback,VM.Config.Disk,Datastore.Allocate,VM.Config.CPU,VM.Config.CDROM,Group.Allocate,Datastore.Audit,VM.Migrate,VM.GuestAgent.FileWrite,Mapping.Use,Datastore.AllocateSpace,Sys.Syslog,VM.Config.Options,Pool.Audit,User.Modify,VM.Config.HWType,VM.Audit,Sys.PowerMgmt,VM.GuestAgent.Audit,Mapping.Audit,VM.GuestAgent.FileRead,Permissions.Modify"

pveum user add terraform@pve --comment "Cuenta de servicio para Terraform"
pveum aclmod / -user terraform@pve -role Terraform
pveum user token add terraform@pve terraform-token --privsep=0
```

## Desplegar LXC

Perfiles disponibles (`flavors` en `variables.tf`): `minimo` (1 core/512MB/2GB — pensado para un único binario, tipo ttyd), `basico` (1/1024MB/10GB), `pro` (2/2048MB/20GB), `supreme` (3/3072MB/30GB), `extreme` (4/4096MB/40GB).

```hcl
contenedores = {
  web01 = {
    vm_id    = 200
    hostname = "web01"
    flavor   = "supreme"
    ip       = "192.168.1.20/24"
    gateway  = "192.168.1.1"
  }
  ttyd = {
    vm_id    = 103
    hostname = "ttyd"
    flavor   = "minimo"
    ip       = "192.168.1.14/24"
    gateway  = "192.168.1.1"
    # started = false   # opcional — omitido = encendido (default true)
  }
}
```

```
terraform init
terraform plan
terraform apply
```

## Desplegar VMs Windows

### Requisito previo: plantilla preparada

**ISOs necesarias**: Windows Server 2022 evaluación 180 días (`microsoft.com/en-us/evalcenter/evaluate-windows-server-2022`), drivers VirtIO (`https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso`).

VM con controlador VirtIO SCSI, red VirtIO, disco adicional de drivers VirtIO marcado, Qemu Agent activo. Dentro de Windows, antes del sysprep:

```
winrm quickconfig -q
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
New-NetFirewallRule -Name "WinRM-HTTP-In" -DisplayName "WinRM HTTP" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
```

VM apagada → **Convertir en plantilla**. Anota su `vm_id`.

### Desplegar desde la plantilla

```hcl
vms_windows = {
  win_test01 = {
    vm_id          = 490
    name           = "win-test01"
    template_vm_id = 251
    started        = false   # opcional — false si quieres que se quede apagada tras el apply
  }
}
```

```
terraform plan
terraform apply
```

**Renumerar o mover el `vm_id` de una VM ya gestionada nunca se hace a mano desde Proxmox.** Si se hace, el arreglo:

```
terraform state rm 'proxmox_virtual_environment_vm.windows["<clave>"]'
# actualizar vm_id en terraform.tfvars al valor real
terraform import 'proxmox_virtual_environment_vm.windows["<clave>"]' <nodo>/<vm_id_real>
terraform plan
```

Si el recurso usa `clone`, añade `lifecycle { ignore_changes = [clone] }` antes de importar — ese bloque no se puede reconstruir desde un import.

## Desplegar Kali (imagen QEMU pre-construida)

M�quina única en `kali.tf`, sin cloud-init — IP fijada a mano en el guest tras el primer arranque.

```
apt install -y p7zip-full
mkdir -p /root/kali-img && cd /root/kali-img
wget https://cdimage.kali.org/kali-2026.2/kali-linux-2026.2-qemu-amd64.7z
7z x kali-linux-2026.2-qemu-amd64.7z
qemu-img info kali-linux-2026.2-qemu-amd64.qcow2   # confirma el "virtual size" — no se puede reducir después
mv kali-linux-2026.2-qemu-amd64.qcow2 /var/lib/vz/import/
```

`disk.import_from` apunta a `local:import/<archivo>.qcow2`. `kali_started = false` en `terraform.tfvars` si no quieres que arranque en cada `apply`.

```
terraform plan
terraform apply
```

Tras el primer arranque, IP fija dentro del guest:
```
nmcli con show
nmcli con mod "<nombre>" ipv4.addresses 192.168.1.60/24 ipv4.gateway 192.168.1.1 ipv4.dns 8.8.8.8 ipv4.method manual
nmcli con up "<nombre>"
```

## Encendido/apagado declarativo, y por qué `-target` no es gratis

Apagar una máquina a mano en Proxmox (`pct stop`/`qm stop`) no cambia lo que Terraform cree que debería pasar — si el recurso sigue declarando (o asumiendo por default) `started = true`, el siguiente `apply` la vuelve a encender, sin avisar de que lo está haciendo por eso. La solución es declarar el estado que quieres en `terraform.tfvars`, no imponerlo por fuera:

```hcl
contenedores = {
  web01 = { ... , started = false }
}
vms_windows = {
  win_test01 = { ... , started = false }
}
kali_started = false
```

**Sobre `terraform apply -target=...`**, para crear/tocar una sola máquina sin arrastrar el resto del plan: funciona, pero con una trampa real — si targeteas también `local_file.ansible_inventory` (para que el inventario incluya la máquina nueva ya mismo), Terraform arrastra automáticamente **todas** las VMs de las que ese inventario depende para poder leer sus IPs, aunque nunca las nombraste. En la práctica: targetear "solo ttyd + el inventario" encendió también `win-test01`, porque el inventario lee su IP vía guest-agent. Terraform avisa de esto literalmente en el propio mensaje ("*-target is not for routine use*") — es la herramienta correcta para una situación puntual, no una forma de trabajar el día a día. Si vas a apagar/encender máquinas con frecuencia, el campo `started` de arriba es la solución de fondo; `-target` es el parche para hoy.

## Uso general

```
git clone git@github.com:sotomann/homelab-terraform.git
cd homelab-terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Estado actual

LXC, VMs Windows, VM Kali y ahora también **ttyd** (terminal web, flavor `minimo`, 192.168.1.14) funcionando de extremo a extremo. El inventario de Ansible se genera solo en cada `apply` (`locals.tf` + `inventario.tf`), filtrando automáticamente cualquier host apagado o sin IP resuelta todavía. Encendido/apagado por máquina es ahora un campo declarado (`started`), no un valor fijo — apagar algo a mano en Proxmox y declarar `started = false` en el `.tfvars` son ahora la misma cosa, en vez de estar en guerra permanente con el próximo `apply`.

## Proyectos relacionados

- [homelab-ansible](https://github.com/sotomann/homelab-ansible) — configuración post-despliegue
- Ficha del proyecto: [hjs.es/proyectos/terraform](https://hjs.es/proyectos/terraform)
