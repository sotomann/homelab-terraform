# Homelab — Aprovisionamiento con Terraform

Aprovisionamiento de LXC y VMs Windows en Proxmox VE mediante Terraform, usando el provider [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest). Complementa a [`homelab-ansible`](https://github.com/sotomann/homelab-ansible): Terraform crea la máquina, Ansible la configura.

## Contexto

Homelab sobre un HP EliteDesk 800 G4 Mini (i5-8400T, 6 núcleos, 16 GB RAM) con Proxmox VE 9.2. Antes de este proyecto, las máquinas se creaban a mano desde el panel; el objetivo es declarar la infraestructura en código, versionada y reproducible.

## Decisiones de diseño

- **Provider `bpg/proxmox` en vez de `Telmate/proxmox`**: Telmate tiene un bug abierto de permisos (`VM.Monitor`) en Proxmox VE 9.x. bpg está activamente mantenido y soporta PVE 9.2 de forma oficial.
- **Usuario y token dedicados** (`terraform@pve`), con un rol acotado en vez de `root@pam`. Mínimo privilegio: si el token se filtra, el daño se limita a gestión de VMs/LXC.
- **`insecure = true`** en el provider: el certificado Let's Encrypt del nodo está emitido para `homelab.hjs.es` (vía Cloudflare Tunnel), no para la IP interna `192.168.1.10` que usa Terraform, así que la verificación TLS por hostname fallaría aunque el cert sea válido. Tráfico solo dentro de la LAN.
- **IP fija — dos mecanismos distintos según el tipo de recurso**: en los LXC, Proxmox inyecta la IP directamente (declarada en `contenedores`, CIDR real gestionado por Terraform). En las VMs Windows no se usa cloud-init/Cloudbase-Init (añade fragilidad conocida a la integración con Proxmox) — en su lugar, Windows sigue usando DHCP y la IP fija se consigue con una reserva DHCP en el router, atada a la MAC de la VM.
- **Perfiles de tamaño (`flavors`)** para los LXC: en vez de repetir cores/memoria/disco en cada máquina, se declaran una vez (`basico`/`pro`/`supreme`/`extreme`) y cada contenedor solo referencia el nombre del perfil.

## Requisitos

- Terraform >= 1.9
- Proxmox VE 9.x
- Usuario `terraform@pve` con token de API (ver más abajo)
- Para VMs Windows: una plantilla ya preparada en Proxmox (ver sección correspondiente)

## Estructura

```
├── providers.tf              # Provider bpg/proxmox
├── variables.tf              # Declaración de variables (flavors, contenedores, vms_windows)
├── lxc.tf                    # Recurso: LXC (for_each sobre var.contenedores)
├── vms.tf                    # Recurso: VMs Windows (for_each sobre var.vms_windows)
├── terraform.tfvars.example  # Plantilla de valores (sin datos reales)
├── terraform.tfvars          # Valores reales — NO se sube a git
└── .gitignore
```

## Cómo usar este repo según lo que quieras desplegar

| Quiero...                     | Edita esta variable en `.tfvars` | Recurso definido en |
|--------------------------------|-----------------------------------|----------------------|
| LXC Linux (uno o varios)       | `contenedores`                    | `lxc.tf`             |
| VM Windows (una o varias)      | `vms_windows`                     | `vms.tf`             |
| Ambos a la vez                 | Las dos variables                 | Los dos archivos     |
| Solo una máquina, sin más      | Mapa con una única entrada — no hay modo especial para "individual" |

Terraform no distingue por nombre de archivo — lee todos los `.tf` del directorio y los trata como uno solo. Si `vms_windows` no tiene entradas (o el archivo no existe), simplemente no crea ninguna VM; no hace falta "desactivar" `vms.tf` para desplegar solo LXC.

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

En `terraform.tfvars`:
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

No se despliega Windows desde cero — se clona una plantilla ya instalada y generalizada. Para construirla:

**ISOs necesarias** (subir a Proxmox: Datacenter → almacenamiento `local` → Content → Upload):
- Windows Server 2022, evaluación gratuita 180 días: `microsoft.com/en-us/evalcenter/evaluate-windows-server-2022`
- Drivers VirtIO: `https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso`

**Creación de la VM**: disco SCSI con controlador VirtIO SCSI, red VirtIO, "Agregar disco adicional para drivers VirtIO" marcado en la pestaña SO, casilla **Qemu Agent** activada en la pestaña Sistema (sin esto, Proxmox no ve la IP de la VM aunque el agente esté instalado dentro).

**Dentro de Windows, antes del sysprep** — instalar `virtio-win-guest-tools.exe` (drivers + qemu-guest-agent en un solo paso), aplicar todas las actualizaciones pendientes, y dejar preparado el acceso remoto:

```powershell
# WinRM, para que Ansible pueda gestionar la VM tras el despliegue
winrm quickconfig -q
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
Set-NetConnectionProfile -NetworkCategory Private
New-NetFirewallRule -Name "WinRM-HTTP-In" -DisplayName "WinRM HTTP" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any

# RDP, opcional — solo si quieres poder conectarte por escritorio remoto además de WinRM
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Quita el aviso de Ctrl+Alt+Supr al entrar por consola virtualizada (cosmético, opcional)
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableCAD /t REG_DWORD /d 1 /f
```

Luego generalizar y convertir en plantilla:
```powershell
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
```
VM apagada → botón derecho → **Convertir en plantilla**. Anota su `vm_id`.

### Desplegar desde la plantilla

En `terraform.tfvars`:
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

Verificación de que el guest-agent quedó vivo (indica que la plantilla está bien hecha):
```bash
qm agent <vm_id> network-get-interfaces
```

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

## Estado actual

LXC y VMs Windows funcionando de extremo a extremo (crear/verificar/destruir probado en ambos). Pendiente: generación automática del inventario de Ansible a partir de las máquinas desplegadas.

## Proyectos relacionados

- [homelab-ansible](https://github.com/sotomann/homelab-ansible) — configuración post-despliegue
- Ficha del proyecto: [hjs.es/proyectos/terraform](https://hjs.es/proyectos/terraform)
