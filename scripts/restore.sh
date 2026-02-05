#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# 🔄 n8n Restore Script
# ══════════════════════════════════════════════════════════════════════
# Restaura la base de datos y datos de n8n desde backups locales o Drive.
# ══════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# Configuración
# ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_DIR}/backups"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"

# Rclone
RCLONE_REMOTE="drive"
RCLONE_FOLDER="N8N"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    echo "  🔄 n8n Self-Hosted - Restauración"
    echo "══════════════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

list_local_backups() {
    echo ""
    echo "📁 Backups locales disponibles:"
    echo "─────────────────────────────────────────"
    
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -lh "$BACKUP_DIR"/*.gz 2>/dev/null || echo "  (ninguno)"
    else
        echo "  (directorio de backups no existe)"
    fi
    echo ""
}

list_remote_backups() {
    echo ""
    echo "☁️  Backups en Google Drive:"
    echo "─────────────────────────────────────────"
    
    rclone lsl "${RCLONE_REMOTE}:${RCLONE_FOLDER}/" 2>/dev/null | head -20 || echo "  (ninguno o error de conexión)"
    echo ""
}

download_from_drive() {
    local filename="$1"
    local dest="${BACKUP_DIR}/${filename}"
    
    log_info "Descargando desde Drive: $filename"
    
    if rclone copy "${RCLONE_REMOTE}:${RCLONE_FOLDER}/${filename}" "$BACKUP_DIR/" --progress; then
        log_info "✅ Descarga completada"
        echo "$dest"
    else
        log_error "Error al descargar"
        return 1
    fi
}

restore_database() {
    local backup_file="$1"
    
    log_info "Restaurando base de datos desde: $(basename "$backup_file")"
    
    # Verificar que el servicio está corriendo
    if ! docker compose -f "$COMPOSE_FILE" ps db | grep -q "running"; then
        log_error "El servicio de base de datos no está corriendo"
        echo "Inicia los servicios con: docker compose up -d"
        return 1
    fi
    
    # Restaurar
    if gunzip -c "$backup_file" | docker compose -f "$COMPOSE_FILE" exec -T db psql -U n8n n8n; then
        log_info "✅ Base de datos restaurada"
    else
        log_error "Error al restaurar base de datos"
        return 1
    fi
}

restore_n8n_data() {
    local backup_file="$1"
    local n8n_data_dir="${PROJECT_DIR}/n8n_data"
    
    log_info "Restaurando datos de n8n desde: $(basename "$backup_file")"
    
    # Detener n8n
    log_info "Deteniendo n8n..."
    docker compose -f "$COMPOSE_FILE" stop n8n
    
    # Backup del directorio actual (por si acaso)
    if [[ -d "$n8n_data_dir" ]]; then
        log_info "Creando backup del directorio actual..."
        mv "$n8n_data_dir" "${n8n_data_dir}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    
    # Restaurar
    if tar -xzf "$backup_file" -C "$PROJECT_DIR"; then
        log_info "✅ Datos de n8n restaurados"
    else
        log_error "Error al restaurar datos de n8n"
        return 1
    fi
    
    # Reiniciar n8n
    log_info "Reiniciando n8n..."
    docker compose -f "$COMPOSE_FILE" start n8n
    
    log_info "✅ Restauración completada"
}

interactive_restore() {
    print_header
    
    echo "Selecciona el tipo de restauración:"
    echo ""
    echo "  1) Restaurar base de datos (desde backup local)"
    echo "  2) Restaurar base de datos (desde Google Drive)"
    echo "  3) Restaurar datos de n8n (desde backup local)"
    echo "  4) Restaurar datos de n8n (desde Google Drive)"
    echo "  5) Listar backups disponibles"
    echo "  6) Salir"
    echo ""
    
    read -rp "Opción: " choice
    
    case $choice in
        1)
            list_local_backups
            read -rp "Nombre del archivo de backup de BD (db_*.sql.gz): " filename
            restore_database "${BACKUP_DIR}/${filename}"
            ;;
        2)
            list_remote_backups
            read -rp "Nombre del archivo de backup de BD (db_*.sql.gz): " filename
            local_file=$(download_from_drive "$filename")
            restore_database "$local_file"
            ;;
        3)
            list_local_backups
            read -rp "Nombre del archivo de backup de datos (n8n_data_*.tar.gz): " filename
            restore_n8n_data "${BACKUP_DIR}/${filename}"
            ;;
        4)
            list_remote_backups
            read -rp "Nombre del archivo de backup de datos (n8n_data_*.tar.gz): " filename
            local_file=$(download_from_drive "$filename")
            restore_n8n_data "$local_file"
            ;;
        5)
            list_local_backups
            list_remote_backups
            ;;
        6)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            log_error "Opción inválida"
            exit 1
            ;;
    esac
}

show_usage() {
    echo "Uso: $0 [opción]"
    echo ""
    echo "Opciones:"
    echo "  --db <archivo>      Restaurar base de datos desde archivo"
    echo "  --data <archivo>    Restaurar datos de n8n desde archivo"
    echo "  --list              Listar backups disponibles"
    echo "  --help              Mostrar esta ayuda"
    echo ""
    echo "Sin argumentos: modo interactivo"
}

# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────
main() {
    case "${1:-}" in
        --db)
            [[ -z "${2:-}" ]] && { log_error "Falta archivo de backup"; exit 1; }
            restore_database "$2"
            ;;
        --data)
            [[ -z "${2:-}" ]] && { log_error "Falta archivo de backup"; exit 1; }
            restore_n8n_data "$2"
            ;;
        --list)
            list_local_backups
            list_remote_backups
            ;;
        --help)
            show_usage
            ;;
        "")
            interactive_restore
            ;;
        *)
            log_error "Opción desconocida: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Ejecutar
main "$@"
