#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# 🔄 n8n Self-Hosted - Actualización
# ══════════════════════════════════════════════════════════════════════
# Actualiza la instancia de n8n a la última versión disponible en Docker.
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
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}"
    echo "══════════════════════════════════════════════════════════════════════"
    echo "  🔄 n8n Self-Hosted - Actualización"
    echo "══════════════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

update_n8n() {
    log_info "Cambiando al directorio del proyecto: ${PROJECT_DIR}"
    cd "${PROJECT_DIR}" || exit 1

    log_info "Realizando un backup de la base de datos y datos de n8n antes de actualizar..."
    if [[ -x "${SCRIPT_DIR}/backup.sh" ]]; then
        "${SCRIPT_DIR}/backup.sh"
        log_info "✅ Backup completado (o intentado)."
    else
        log_warn "⚠️  Script de backup no encontrado o no ejecutable. Omitiendo backup..."
    fi

    log_info "Descargando las últimas imágenes de Docker..."
    docker compose pull

    log_info "Recreando contenedores con las nuevas imágenes..."
    docker compose up -d

    log_info "Limpiando imágenes antiguas de Docker para liberar espacio..."
    docker image prune -f

    log_info "✅ Actualización completada exitosamente."
}

# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────
main() {
    print_header
    update_n8n
}

# Ejecutar
main "$@"
