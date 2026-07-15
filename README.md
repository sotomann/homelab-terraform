# Homelab — Aprovisionamiento con Terraform

Aprovisionamiento de LXC y VMs Windows en Proxmox VE mediante Terraform, usando el provider [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest). Complementa a [`homelab-ansible`](https://github.com/sotomann/homelab-ansible): Terraform crea la máquina y genera su inventario, Ansible la configura.

## Contexto

Homelab sobre un HP EliteDesk 800 G4 Mini (i5-8400T, 6 núcleos, 16 GB RAM) con Proxmox VE 9.2. Antes de este proyecto, las máquinas se creaban a mano desde el panel; el objetivo es declarar la infraestructura en código, versionada y reproducible — y que la propia infraestructura le diga a Ansible qué acaba de crear.

## Decisiones de diseño

- **Provider `bpg/proxmox` en vez de `Telmate/proxmox`**: Telmate tiene un bug abierto de permisos (`VM.Monitor`) en Proxmox VE 9.x. bpg está activamente mantenido y soporta PVE 9.2 de forma oficial.
- **Usuario y token dedicados** (`terraform@pve`), con un rol acotado en vez de `root@pam`. Mínimo privilegio: si el token se filtra, el daño se limita a gestión de VMs/LXC.
- **`insecure = true`** en el provider: el certificado Let's Encrypt del nodo está emitido para `homelab.hjs.es` (vía Cloudflare Tunnel), no para la IP interna `192.168.1.10` que usa Terraform, así que la verificación TLS por hostname fallaría aunque el cert sea válido. Tráfico solo dentro de la LAN.
- **IP fija — dos mecanismos distintos según el tipo de recurso**: en los LXC, Proxmox inyecta la IP directamente (declarada en `contenedores`, CIDR real gestionado por Terraform). En las VMs Windows no se usa cloud-init/Cloudbase-Init (añade fragilidad conocida a la integración con Proxmox) — en su lugar, Windows sigue usando DHCP y la IP fija se consigue con una reserva DHCP en el router, atada a la MAC de la VM.
- **Perfiles de tamaño (`flavors`)** para los LXC: en vez de repetir cores/memoria/disco en cada máquina, se declaran una vez (`basico`/`pro`/`supreme`/`extreme`) y cada contenedor solo referencia el nombre del perfil.
- **Inventario generado, no mantenido a mano**: para los LXC la IP ya es conocida (declarada); para las VMs Windows se lee tras el `apply` desde el propio recurso (`ipv4_addresses`, vía guest-agent) porque la asigna el DHCP del router, no Terraform.

## Requisitos

- Terraform >= 1.9
- Proxmox VE 9.x
- Usuario `terraform@pve` con token de API (ver más abajo)
- Para VMs Windows: una plantilla ya preparada en Proxmox (ver sección correspondiente)

## Estructura

```
├── providers.tf              # Providers: bpg/proxmox + hashicorp/local
├── variables.tf               # Declaración de variables (flavors, contenedores, vms_windows)
├── locals.tf                  # Listas limpias hostname+IP para el inventario
├── lxc.tf                     # Recurso: LXC (for_each sobre var.contenedores)
├── vms.tf                     # Recurso: VMs Windows (for_each sobre var.vms_windows)
├── inventario.tf              # Genera inventory_generado.ini tras cada apply
├── templates/
│   └── inventory.tpl          # Plantilla del inventario de Ansible
├── terraform.tfvars.example   # Plantilla de valores (sin datos reales)
├── terraform.tfvars           # Valores reales — NO se sube a git
└── .gitignore
```

## Cómo usar este repo según lo que quieras desplegar

| Quiero...                     | Edita esta variable en `.tfvars` | Recurso definido en |
|--------------------------------|-----------------------------------|----------------------|
| LXC Linux (uno o varios)       | `contenedores`                    | `lxc.tf`             |
| VM Windows (una o varias)      | `vms_windows`                     | `vms.tf`             |
| Ambos a la vez                 | Las dos variables                 | Los dos archivos     |
| Solo una máquina, sin más      | Mapa con una única entrada — no hay modo especial para "individual" |

Terraform no distingue por nombre de archivo — lee todos los `.tf` del directorio y los trata como uno solo.

## Preparar el token en Proxmox

Desde el Shell del nodo:

```bash
pveum role add Terraform -privs "Realm.AllocateUser,VM.PowerMgmt,VM.GuestAgent.Unrestricted,Sys.Console,Sys.Audit,Sys.AccessNetwork,VM.Config.Cloudinit,VM.Replicate,Pool.Allocate,SDN.Audit,Realm.Allocate,SDN.Use,Mapping.Modify,VM.Config.Memory,VM.GuestAgent.FileSystemMgmt,VM.Allocate,SDN.Allocate,VM.Console,VM.Clone,VM.Backup,Datastore.AllocateTemplate,VM.Snapshot,VM.Config.Network,Sys.Incoming,Sys.Modify,VM.Snapshot.Rollback,VM.Config.Disk,Datastore.Allocate,VM.Config.CPU,VM.Config.CDROM,Group.Allocate,Datastore.Audit,VM.Migrate,VM.GuestAgent.FileWrite,Mapping.Use,Datastore.AllocateSpace,Sys.Syslog,VM.Config.Options,Pool.Audit,User.Modify,VM.Config.HWType,VM.Audit,Sys.PowerMgmt,VM.GuestAgent.Audit,Mapping.Audit,VM.GuestAgent.FileRead,Permissions.Modify"

pveum user add terraform@pve --comment "Cuenta de servicio para Terraform"
pveum aclmod / -user terraform@pve -role Terraform
pveum user token add terraform@pve terraform-token --privsep=0
```

Guarda el `full-tokenid` y el `value` — el secret solo se muestra una vez.

## Desplegar LXC

Perfiles disponibles por defecto en `variables.tf` (`flavors`): `basico` (1 core/1GB/10GB), `pro` (2/2/20), `supreme` (3/3/30), `extreme` (4/4/40).

```hcl
contenedores = {
  web01 = {
    vm_id    = 200
    hostname = "web01"
    flavor   = "supreme"
    ip       = "192.168.1.50/24"
    gateway  = "192.168.1.1"
  }
}
```
```bash
terraform init
terraform plan
terraform apply
```

## Desplegar VMs Windows

### Requisito previo: plantilla preparada

No se despliega Windows desde cero — se clona una plantilla ya instalada y generalizada.

**ISOs necesarias** (subir a Proxmox: Datacenter → almacenamiento `local` → Content → Upload):
- Windows Server 2022, evaluación gratuita 180 días: `microsoft.com/en-us/evalcenter/evaluate-windows-server-2022`
- Drivers VirtIO: `https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso`

**Creación de la VM**: disco SCSI con controlador VirtIO SCSI, red VirtIO, "Agregar disco adicional para drivers VirtIO" marcado en la pestaña SO, casilla **Qemu Agent** activada en la pestaña Sistema.

**Dentro de Windows, antes del sysprep** — instalar `virtio-win-guest-tools.exe`, aplicar actualizaciones, y dejar preparado el acceso remoto:

```powershell
# WinRM, para que Ansible pueda gestionar la VM tras el despliegue
winrm quickconfig -q
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
Set-NetConnectionProfile -NetworkCategory Private
New-NetFirewallRule -Name "WinRM-HTTP-In" -DisplayName "WinRM HTTP" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any

# RDP, opcional
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Quita el aviso de Ctrl+Alt+Supr al entrar por consola virtualizada (cosmético)
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableCAD /t REG_DWORD /d 1 /f
```

Generalizar y convertir en plantilla:
```powershell
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
```
VM apagada → botón derecho → **Convertir en plantilla**. Anota su `vm_id`.

> **Problema conocido**: si sysprep falla con `0x80073cf2` y el log (`%WINDIR%\System32\Sysprep\Panther\setupact.log`) menciona un paquete de Edge "instalado para un usuario pero no provisionado para todos" — es un bug de Microsoft, Windows Update instala Edge por-usuario en vez de a nivel de máquina. Se arregla quitando el paquete y reintentando:
> ```powershell
> Get-AppxPackage -AllUsers Microsoft.MicrosoftEdge.Stable | Remove-AppxPackage -AllUsers
> ```

### Desplegar desde la plantilla

```hcl
vms_windows = {
  web_win01 = {
    vm_id          = 300
    name           = "web-win01"
    template_vm_id = 251   # <- vm_id real de tu plantilla
  }
}
```
```bash
terraform plan
terraform apply
```

Verificación de que el guest-agent quedó vivo:
```bash
qm agent <vm_id> network-get-interfaces
```

### IP fija

Declara una `mac_address` en la entrada de la VM (mismo prefijo `BC:24:11` que usa Proxmox) y crea una reserva DHCP en el router para esa MAC.

## Inventario de Ansible generado automáticamente

Tras cada `apply`, un `local_file` escribe `inventory_generado.ini` en la raíz del repo, con las máquinas reales agrupadas en `[linux]`/`[windows]` — sin ninguna IP tecleada a mano.

**Cómo funciona**: `locals.tf` construye dos mapas limpios de `{name, ip}`. Para los LXC, la IP viene de la propia variable declarada (se le quita el `/24`). Para las VMs Windows, no hay IP declarada — se lee el atributo `ipv4_addresses` que expone el recurso tras crearse (vía qemu-guest-agent), filtrando `127.x` (localhost) y `169.254.x` (autoasignación sin DHCP a tiempo). Una `templatefile` renderiza `templates/inventory.tpl` con esos dos mapas, y el provider `hashicorp/local` escribe el resultado a disco.

```bash
cat inventory_generado.ini
```
```ini
[linux]
web01 ansible_host=192.168.1.50

[windows]
win-test01 ansible_host=192.168.1.153
```

Usarlo directamente:
```bash
ansible-playbook -i inventory_generado.ini site.yml --limit linux
ansible-playbook -i inventory_generado.ini site.yml --limit windows --ask-vault-pass
```

El archivo está en `.gitignore` — contiene IPs reales de la red, no se sube.

**Si `[windows]` sale vacía o con una IP `169.254.x.x`**: el guest-agent no había resuelto la IP real a tiempo. Comprobar con `qm agent <id> network-get-interfaces` y relanzar `terraform apply` (idempotente, solo regenera el archivo, no toca la VM).

**Disparo automático de Ansible tras el apply** (documentado, no activado por defecto): un `null_resource` con `local-exec` podría lanzar `ansible-playbook` justo después del `apply`. No se activa porque acopla el estado de Terraform a la ejecución de Ansible — si el playbook falla, el `apply` se reporta con error aunque la infraestructura se creara bien.

## Uso general

```bash
git clone git@github.com:sotomann/homelab-terraform.git
cd homelab-terraform
cp terraform.tfvars.example terraform.tfvars
# edita terraform.tfvars con el token real y los recursos que quieras desplegar
terraform init
terraform plan
terraform apply
```

## Comandos útiles

```bash
terraform validate                          # solo revisa sintaxis
terraform state list                         # qué hay en el state
terraform plan -target='recurso["clave"]'    # solo ese recurso — excepción, no rutina
terraform destroy                            # elimina lo que gestiona el state
```

## Estado actual

LXC, VMs Windows e integración con Ansible funcionando de extremo a extremo — Terraform crea, genera su propio inventario, Ansible configura, sin ninguna IP escrita a mano en ningún paso.

## Proyectos relacionados

- [homelab-ansible](https://github.com/sotomann/homelab-ansible) — configuración post-despliegue
- Ficha del proyecto: [hjs.es/proyectos/terraform](https://hjs.es/proyectos/terraform)
