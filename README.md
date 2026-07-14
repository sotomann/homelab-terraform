# Homelab — Aprovisionamiento con Terraform

Aprovisionamiento de LXC (y en el futuro VMs) en Proxmox VE mediante Terraform, usando el provider [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest). Complementa a [`homelab-ansible`](https://github.com/sotomann/homelab-ansible): Terraform crea la máquina, Ansible la configura.

## Contexto

Homelab sobre un HP EliteDesk 800 G4 Mini (i5-8400T, 6 núcleos, 16 GB RAM) con Proxmox VE 9.2. Hasta ahora las máquinas se creaban a mano desde el panel; el objetivo de este proyecto es declarar la infraestructura en código, versionada y reproducible.

## Decisiones de diseño

- **Provider `bpg/proxmox` en vez de `Telmate/proxmox`**: Telmate tiene un bug abierto de permisos (`VM.Monitor`) en Proxmox VE 9.x. bpg está activamente mantenido y soporta PVE 9.2 de forma oficial.
- **Usuario y token dedicados** (`terraform@pve`), con un rol acotado en vez de usar `root@pam`. Principio de mínimo privilegio: si el token se filtra, el daño se limita a gestión de VMs/LXC.
- **`insecure = true`** en el provider: el certificado Let's Encrypt del nodo está emitido para `homelab.hjs.es` (vía Cloudflare Tunnel), no para la IP interna `192.168.1.10` que usa Terraform, así que la verificación TLS por hostname fallaría aunque el cert sea válido. Tráfico solo dentro de la LAN.
- **`ct_vm_id` y `ct_hostname` sin valor por defecto**: fuerzan a decidir explícitamente cada despliegue, para no repetir ID o nombre por descuido.

## Requisitos

- Terraform >= 1.9
- Proxmox VE 9.x
- Usuario `terraform@pve` con token de API (ver más abajo)

## Estructura

├── providers.tf              # Provider bpg/proxmox
├── variables.tf              # Declaración de variables
├── main.tf                   # Recurso(s) de infraestructura
├── terraform.tfvars.example  # Plantilla de valores (sin datos reales)
├── terraform.tfvars          # Valores reales — NO se sube a git
└── .gitignore

## Preparar el token en Proxmox

Desde el Shell del nodo:

```bash
pveum role add Terraform -privs "Realm.AllocateUser,VM.PowerMgmt,VM.GuestAgent.Unrestricted,Sys.Console,Sys.Audit,Sys.AccessNetwork,VM.Config.Cloudinit,VM.Replicate,Pool.Allocate,SDN.Audit,Realm.Allocate,SDN.Use,Mapping.Modify,VM.Config.Memory,VM.GuestAgent.FileSystemMgmt,VM.Allocate,SDN.Allocate,VM.Console,VM.Clone,VM.Backup,Datastore.AllocateTemplate,VM.Snapshot,VM.Config.Network,Sys.Incoming,Sys.Modify,VM.Snapshot.Rollback,VM.Config.Disk,Datastore.Allocate,VM.Config.CPU,VM.Config.CDROM,Group.Allocate,Datastore.Audit,VM.Migrate,VM.GuestAgent.FileWrite,Mapping.Use,Datastore.AllocateSpace,Sys.Syslog,VM.Config.Options,Pool.Audit,User.Modify,VM.Config.HWType,VM.Audit,Sys.PowerMgmt,VM.GuestAgent.Audit,Mapping.Audit,VM.GuestAgent.FileRead,Permissions.Modify"

pveum user add terraform@pve --comment "Cuenta de servicio para Terraform"
pveum aclmod / -user terraform@pve -role Terraform
pveum user token add terraform@pve terraform-token --privsep=0
```

Guarda el `full-tokenid` y el `value` — el secret solo se muestra una vez.

## Notas para reconstruir la plantilla Windows

Antes del sysprep, aplicar siempre:

```powershell
# WinRM para gestión con Ansible
winrm quickconfig -q
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
Set-NetConnectionProfile -NetworkCategory Private
New-NetFirewallRule -Name "WinRM-HTTP-In" -DisplayName "WinRM HTTP" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any

# Quitar el aviso de Ctrl+Alt+Supr en consola virtualizada
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableCAD /t REG_DWORD /d 1 /f

## Uso

```bash
git clone git@github.com:sotomann/homelab-terraform.git
cd homelab-terraform

cp terraform.tfvars.example terraform.tfvars
# edita terraform.tfvars con el token real y los valores del recurso

terraform init
terraform plan
terraform apply
```

## Estado actual

En desarrollo activo. Por ahora despliega LXC; VMs con plantillas cloud-init quedan como siguiente iteración.

## Proyectos relacionados

- [homelab-ansible](https://github.com/sotomann/homelab-ansible) — configuración post-despliegue
- Ficha del proyecto: [hjs.es/proyectos/terraform](https://hjs.es/proyectos/terraform)
