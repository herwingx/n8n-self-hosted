#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# 🔐 n8n Self-Hosted - Configurar Permisos
# ══════════════════════════════════════════════════════════════════════
# Configura los permisos correctos para los volúmenes de Docker.
# Ejecutar DESPUÉS del primer 'docker compose up -d'.
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
NC='\033[0m'

# Detectar si ya somos root (LXC, Docker, etc.)
if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

# ─────────────────────────────────────────────────────────────────────
# Funciones
# ─────────────────────────────────────────────────────────────────────
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "🔐 Configurando permisos de volúmenes..."
echo ""

# Verificar que las carpetas existen
if [[ ! -d "${PROJECT_DIR}/n8n_data" ]] && [[ ! -d "${PROJECT_DIR}/postgres_data" ]]; then
    log_error "Las carpetas de datos no existen."
    echo ""
    echo "Primero ejecuta:"
    echo -e "  ${YELLOW}docker compose up -d${NC}"
    echo ""
    echo "Luego vuelve a ejecutar este script."
    exit 1
fi

# n8n corre como usuario 'node' (UID 1000)
if [[ -d "${PROJECT_DIR}/n8n_data" ]]; then
    log_info "Configurando n8n_data → UID 1000 (node)"
    $SUDO_CMD chown -R 1000:1000 "${PROJECT_DIR}/n8n_data"
else
    log_warn "Carpeta n8n_data no encontrada, omitiendo..."
fi

# PostgreSQL Alpine corre como usuario 'postgres' (UID 70)
if [[ -d "${PROJECT_DIR}/postgres_data" ]]; then
    log_info "Configurando postgres_data → UID 70 (postgres)"
    $SUDO_CMD chown -R 70:70 "${PROJECT_DIR}/postgres_data"
else
    log_warn "Carpeta postgres_data no encontrada, omitiendo..."
fi

echo ""
log_info "✅ Permisos configurados correctamente"
echo ""

# Preguntar si reiniciar
read -rp "¿Reiniciar los contenedores ahora? [s/N]: " restart
if [[ "$restart" =~ ^[sS]$ ]]; then
    log_info "Reiniciando contenedores..."
    docker compose -f "${PROJECT_DIR}/docker-compose.yml" restart
    log_info "✅ Contenedores reiniciados"
fi
