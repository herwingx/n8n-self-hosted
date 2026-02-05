#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# 🔧 n8n Self-Hosted - Script de Instalación
# ══════════════════════════════════════════════════════════════════════
# Configura el entorno, instala dependencias y programa backups automáticos.
# ══════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# Configuración
# ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────
# Funciones
# ─────────────────────────────────────────────────────────────────────
print_header() {
    echo -e "${BLUE}"
    echo "══════════════════════════════════════════════════════════════════════"
    echo "  🔧 n8n Self-Hosted - Instalación"
    echo "══════════════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

detect_sudo() {
    # Detectar si ya somos root (LXC, Docker, etc.)
    if [[ $EUID -eq 0 ]]; then
        SUDO_CMD=""
        log_info "Ejecutando como root (LXC/Docker detectado)"
    else
        SUDO_CMD="sudo"
    fi
}

check_dependencies() {
    log_info "Verificando dependencias..."
    
    local deps=("docker" "rclone")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Dependencias faltantes: ${missing[*]}"
        echo ""
        echo "Instalar con:"
        echo "  Docker: curl -fsSL https://get.docker.com | sh"
        echo "  rclone: curl https://rclone.org/install.sh | sudo bash"
        exit 1
    fi
    
    log_info "✅ Todas las dependencias instaladas"
}

check_rclone_config() {
    log_info "Verificando configuración de rclone..."
    
    if ! rclone listremotes | grep -q "^drive:"; then
        log_error "Remote 'drive' no encontrado en rclone"
        echo ""
        echo "Configura rclone con:"
        echo "  rclone config"
        echo ""
        echo "Crea un remote llamado 'drive' para Google Drive"
        exit 1
    fi
    
    # Verificar que la carpeta N8N existe o crearla
    if ! rclone lsd drive:N8N &> /dev/null; then
        log_warn "Carpeta N8N no existe en Drive, creándola..."
        rclone mkdir drive:N8N
    fi
    
    log_info "✅ rclone configurado correctamente"
}

setup_env() {
    log_info "Configurando variables de entorno..."
    
    if [[ -f "${PROJECT_DIR}/.env" ]]; then
        log_warn "Archivo .env ya existe, omitiendo..."
        return
    fi
    
    if [[ ! -f "${PROJECT_DIR}/.env.example" ]]; then
        log_error "Archivo .env.example no encontrado"
        exit 1
    fi
    
    cp "${PROJECT_DIR}/.env.example" "${PROJECT_DIR}/.env"
    
    # Generar clave de encriptación
    local encryption_key
    encryption_key=$(openssl rand -hex 32)
    sed -i "s/genera_una_clave_de_64_caracteres_hex/${encryption_key}/" "${PROJECT_DIR}/.env"
    
    log_info "✅ Archivo .env creado con clave de encriptación generada"
    log_warn "⚠️  Edita .env con tus valores antes de iniciar"
}

setup_directories() {
    log_info "Creando directorios necesarios..."
    
    mkdir -p "${PROJECT_DIR}/backups"
    mkdir -p "${PROJECT_DIR}/n8n_data"
    mkdir -p "${PROJECT_DIR}/postgres_data"
    
    log_info "✅ Directorios creados"
}

make_scripts_executable() {
    log_info "Haciendo scripts ejecutables..."
    
    chmod +x "${SCRIPT_DIR}/backup.sh"
    chmod +x "${SCRIPT_DIR}/restore.sh" 2>/dev/null || true
    
    log_info "✅ Scripts configurados"
}

setup_cron() {
    log_info "Configurando backup automático..."
    
    local cron_job="0 3 * * * ${SCRIPT_DIR}/backup.sh >> ${PROJECT_DIR}/backups/cron.log 2>&1"
    local cron_comment="# n8n-backup: Backup diario a las 3:00 AM"
    
    # Verificar si ya existe
    if crontab -l 2>/dev/null | grep -q "n8n-backup"; then
        log_warn "Cron job ya existe, omitiendo..."
        return
    fi
    
    # Agregar cron job
    (crontab -l 2>/dev/null || echo ""; echo "$cron_comment"; echo "$cron_job") | crontab -
    
    log_info "✅ Backup programado diariamente a las 3:00 AM"
}

show_next_steps() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ Instalación completada${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Próximos pasos:"
    echo ""
    echo "  1. Edita el archivo .env con tus valores:"
    echo -e "     ${YELLOW}nano ${PROJECT_DIR}/.env${NC}"
    echo ""
    echo "  2. Configura el Cloudflare Tunnel con tu token"
    echo ""
    echo "  3. Inicia los servicios:"
    echo -e "     ${YELLOW}cd ${PROJECT_DIR} && docker compose up -d${NC}"
    echo ""
    echo "  4. Accede a n8n en: https://n8n.tudominio.com"
    echo ""
    echo "Comandos útiles:"
    echo ""
    echo "  - Ejecutar backup manual:"
    echo -e "    ${YELLOW}${SCRIPT_DIR}/backup.sh${NC}"
    echo ""
    echo "  - Ver logs de backup:"
    echo -e "    ${YELLOW}tail -f ${PROJECT_DIR}/backups/backup.log${NC}"
    echo ""
    echo "  - Ver cron jobs:"
    echo -e "    ${YELLOW}crontab -l${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────
main() {
    print_header
    detect_sudo
    check_dependencies
    check_rclone_config
    setup_env
    setup_directories
    make_scripts_executable
    setup_cron
    show_next_steps
}

# Ejecutar
main "$@"
