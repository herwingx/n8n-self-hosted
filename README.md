# 🔄 n8n Self-Hosted

> **Automatización sin límites** — Despliega tu propia instancia de n8n con PostgreSQL y Cloudflare Tunnel.

[![n8n](https://img.shields.io/badge/n8n-Latest-orange?style=flat-square&logo=n8n)](https://n8n.io)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=flat-square&logo=docker)](https://docs.docker.com/compose/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?style=flat-square&logo=postgresql)](https://www.postgresql.org/)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Tunnel-F38020?style=flat-square&logo=cloudflare)](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
[![rclone](https://img.shields.io/badge/rclone-Google%20Drive-3B7BBD?style=flat-square&logo=googledrive)](https://rclone.org/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

<p align="center">
  <img src="https://n8n.io/n8n-logo.png" alt="n8n Logo" width="200"/>
</p>

---

## ✨ Características

| 🚀 Producción Lista | 🔒 Seguridad Integrada |
|:---|:---|
| PostgreSQL 16 como base de datos persistente | Cloudflare Tunnel para acceso seguro sin puertos expuestos |
| Healthchecks automáticos | Encriptación de credenciales con clave personalizada |
| Reinicio automático de servicios | Opción para deshabilitar registro público |
| Limpieza automática de ejecuciones (14 días) | Variables sensibles fuera del repositorio |

| 🐳 Docker Native | ⚡ Fácil Mantenimiento |
|:---|:---|
| Orquestación con Docker Compose | Comandos simples para actualizar |
| Volúmenes persistentes para datos | Backup y restauración sencilla |
| Imágenes oficiales siempre actualizadas | Logs centralizados |

---

## 🚀 Inicio Rápido

### Prerrequisitos

- Docker y Docker Compose instalados
- Cuenta en Cloudflare con acceso a Zero Trust
- Dominio configurado en Cloudflare

> 📘 **Compatible con LXC/Proxmox**: Los scripts detectan automáticamente si se ejecutan como root.

---

### 1. Clonar el repositorio

```bash
git clone https://github.com/herwingx/n8n-self-hosted.git
cd n8n-self-hosted
```

### 2. Instalar rclone (para backups)

```bash
# Instalar rclone
curl https://rclone.org/install.sh | sudo bash

# Configurar rclone con Google Drive
rclone config
```

Durante la configuración de rclone:
1. Seleccionar `n` (new remote)
2. Nombre: **`gdrive`** ← Este nombre es obligatorio
3. Storage: `drive` (Google Drive)
4. Seguir las instrucciones para autenticar con tu cuenta de Google
5. Verificar con: `rclone lsd gdrive:`

### 3. Configurar Cloudflare Tunnel

1. Ir a [Cloudflare Zero Trust](https://one.dash.cloudflare.com)
2. Navegar a **Access → Tunnels → Create a tunnel**
3. Copiar el token del túnel
4. Configurar el túnel para apuntar a `http://n8n:5678`

### 4. Configurar variables de entorno

```bash
# Copiar archivo de ejemplo
cp .env.example .env

# Generar clave de encriptación segura
openssl rand -hex 32
# Copiar el resultado en N8N_ENCRYPTION_KEY

# Editar .env con tus valores
nano .env
```

Variables a configurar en `.env`:
- `N8N_HOST`: tu dominio (ej: `n8n.tudominio.com`)
- `WEBHOOK_URL`: URL completa con https
- `N8N_ENCRYPTION_KEY`: la clave generada
- `CF_TUNNEL_TOKEN`: token del túnel de Cloudflare
- `DB_PASSWORD`: contraseña segura para PostgreSQL

### 5. Ejecutar instalación

```bash
# Hacer scripts ejecutables y configurar cron de backups
./scripts/install.sh
```

### 6. Iniciar servicios

```bash
docker compose up -d
```

### 7. Configurar permisos de carpetas

> ⚠️ Ejecutar después del primer inicio, cuando Docker crea las carpetas.

```bash
./scripts/fix-permissions.sh
```

### 8. Acceder a n8n

Abre `https://n8n.tudominio.com` en tu navegador.

---

## 🏗️ Arquitectura

```mermaid
flowchart TB
    subgraph Internet
        USER[("👤 Usuario")]
    end

    subgraph Cloudflare["☁️ Cloudflare Edge"]
        CF_EDGE["🔒 SSL/TLS + DDoS Protection"]
    end

    subgraph Tunnel["🚇 Cloudflare Tunnel"]
        CLOUDFLARED["cloudflared container"]
    end

    subgraph Docker["🐳 Docker Network"]
        N8N["⚡ n8n<br/>Motor de Automatización"]
        DB[("🐘 PostgreSQL 16<br/>Base de Datos")]
        
        subgraph Volumes["📁 Volúmenes Persistentes"]
            N8N_DATA["./n8n_data/"]
            PG_DATA["./postgres_data/"]
        end
    end

    subgraph Backup["💾 Backup"]
        RCLONE["rclone"]
        GDRIVE[("☁️ Google Drive<br/>Carpeta: N8N")]
    end

    USER -->|HTTPS| CF_EDGE
    CF_EDGE --> CLOUDFLARED
    CLOUDFLARED -->|HTTP:5678| N8N
    N8N <-->|Puerto 5432| DB
    N8N -.-> N8N_DATA
    DB -.-> PG_DATA
    N8N_DATA --> RCLONE
    PG_DATA --> RCLONE
    RCLONE -->|Diario 3AM| GDRIVE
```

---

## 📦 Comandos Útiles

### Gestión de Servicios

```bash
# Iniciar todos los servicios
docker compose up -d

# Detener todos los servicios
docker compose down

# Ver logs en tiempo real
docker compose logs -f

# Ver logs de un servicio específico
docker compose logs -f n8n
```

### 🔄 Actualizar n8n (si ya está instalado)

Si ya tienes la instancia en marcha y quieres **pasarla a la última versión**:

1. Ve al directorio del proyecto (donde está `docker-compose.yml`).
2. Ejecuta el script de actualización (hace un backup, descarga la nueva imagen, recrea contenedores y limpia imágenes antiguas):

```bash
./scripts/update.sh
```

Ese script hace: **backup** (base de datos y datos de n8n) → **`docker compose pull`** → **`docker compose up -d`** → **`docker image prune -f`**. El proyecto usa la imagen `n8nio/n8n:latest`, así que obtienes la última versión publicada en Docker Hub.

Si prefieres **fijar una versión concreta** (por ejemplo en producción), edita `docker-compose.yml` y cambia la imagen a algo como `n8nio/n8n:1.52.0` (revisa [tags en Docker Hub](https://hub.docker.com/r/n8nio/n8n/tags)).

### 💾 Backup Automático (Google Drive)

Este proyecto incluye un sistema de backup automático a Google Drive usando rclone.

```bash
# Ejecutar backup manual
./scripts/backup.sh

# Ver logs de backup
tail -f backups/backup.log

# Restaurar (modo interactivo)
./scripts/restore.sh

# Listar backups disponibles (local + Drive)
./scripts/restore.sh --list
```

> 📘 Los backups se ejecutan automáticamente cada día a las 3:00 AM vía cron.

### 🔧 Mantenimiento

```bash
# Ver estado de los contenedores
docker compose ps

# Reiniciar un servicio específico
docker compose restart n8n

# Limpiar imágenes no utilizadas
docker image prune -f

# Ver uso de disco de volúmenes
docker system df
```

---

## 📁 Estructura del Proyecto

```
n8n-self-hosted/
├── docker-compose.yml     # Definición de servicios
├── .env.example           # Variables de entorno (plantilla)
├── .env                   # Variables de entorno (local, ignorado)
├── .gitignore             # Archivos ignorados por Git
├── LICENSE                # Licencia MIT
├── README.md              # Esta documentación
├── scripts/
│   ├── install.sh         # Script de instalación inicial
│   ├── fix-permissions.sh # Configurar permisos de volúmenes
│   ├── backup.sh          # Backup automático a Google Drive
│   ├── restore.sh         # Restauración desde backups
│   └── update.sh          # Actualizar imágenes e instancia
├── tests/                  # Tests de scripts (ver tests/README.md)
├── backups/               # Backups locales (ignorado)
├── postgres_data/         # Datos de PostgreSQL (ignorado)
└── n8n_data/              # Datos de n8n (ignorado)
```

### Ejecutar tests

Los tests validan las funciones de los scripts (backup, restore, install) con mocks, sin tocar Docker ni rclone real. Para ejecutarlos:

```bash
# Todos los tests
./tests/run_all_tests.sh

# O uno por uno, por ejemplo:
./tests/test_backup_database.sh
./tests/test_restore_database.sh
./tests/test_install.sh
```

En **`tests/README.md`** está documentado qué hace cada test, qué valida exactamente (casos de prueba) y cómo ejecutarlos.

---

## 🛠️ Stack Tecnológico

| Capa | Tecnología | Propósito |
|:---|:---|:---|
| **Automatización** | n8n | Motor de workflows y automatización |
| **Base de Datos** | PostgreSQL 16 Alpine | Persistencia de datos y workflows |
| **Networking** | Cloudflare Tunnel | Acceso seguro sin puertos expuestos |
| **Backups** | rclone + Google Drive | Respaldo automático en la nube |
| **Orquestación** | Docker Compose | Gestión de contenedores |

---

## 🔐 Seguridad

- ✅ **Cloudflare Tunnel**: No se exponen puertos al exterior
- ✅ **Encriptación de credenciales**: Clave personalizada para proteger datos sensibles
- ✅ **Registro deshabilitado**: Solo admins pueden crear usuarios nuevos
- ✅ **Variables de entorno**: Secretos fuera del código fuente
- ✅ **Healthchecks**: Monitoreo automático del estado de servicios

---

## 🔧 Configuración Avanzada

### Variables de Entorno Adicionales

Puedes agregar estas variables a tu `.env` para personalizar n8n:

```bash
# Zona horaria
GENERIC_TIMEZONE=America/Mexico_City

# Límites de ejecución
EXECUTIONS_DATA_MAX_AGE=720  # Horas (30 días)
EXECUTIONS_DATA_PRUNE=true

# Métricas (Prometheus)
N8N_METRICS=true
N8N_METRICS_PREFIX=n8n_
```

### Configuración de Túnel en Cloudflare

En el dashboard de Cloudflare Zero Trust, configura el túnel:

| Campo | Valor |
|:---|:---|
| Public hostname | `n8n.tudominio.com` |
| Service | `HTTP` |
| URL | `n8n:5678` |

---

## 📖 Documentación Adicional

- [Documentación oficial de n8n](https://docs.n8n.io/)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [PostgreSQL Docker Hub](https://hub.docker.com/_/postgres)

---

## 🤝 Contribuir

Las contribuciones son bienvenidas. Por favor:

1. Haz fork del repositorio
2. Crea una rama para tu feature (`git checkout -b feat/nueva-feature`)
3. Haz commit de tus cambios (`git commit -m "feat(scope): descripción"`)
4. Haz push a la rama (`git push origin feat/nueva-feature`)
5. Abre un Pull Request

---

## 📜 Licencia

Este proyecto está bajo la Licencia MIT. Ver [LICENSE](LICENSE) para más detalles.

---

<p align="center">
  Hecho con ❤️ para la comunidad de automatización
</p>
