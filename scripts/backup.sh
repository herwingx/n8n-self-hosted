#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# 💾 n8n Backup Script
# ══════════════════════════════════════════════════════════════════════
# Respalda la base de datos PostgreSQL y los datos de n8n a Google Drive
# usando rclone. Diseñado para ejecutarse via cron.
# ══════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# Configuración
# ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_DIR}/backups"
LOG_FILE="${BACKUP_DIR}/backup.log"

# Rclone
RCLONE_REMOTE="drive"
RCLONE_FOLDER="N8N"

# Retención
LOCAL_RETENTION_DAYS=7
REMOTE_RETENTION_DAYS=30

# Docker
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"

# ─────────────────────────────────────────────────────────────────────
# Funciones
# ─────────────────────────────────────────────────────────────────────
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

check_dependencies() {
    local deps=("docker" "rclone" "tar" "gzip")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "ERROR" "Dependencia no encontrada: $dep"
            exit 1
        fi
    done
}

create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
}

get_timestamp() {
    date '+%Y%m%d_%H%M%S'
}

backup_database() {
    local timestamp="$1"
    local backup_file="${BACKUP_DIR}/db_${timestamp}.sql.gz"
    
    log "INFO" "Iniciando backup de base de datos..."
    
    if docker compose -f "$COMPOSE_FILE" exec -T db pg_dump -U n8n n8n 2>/dev/null | gzip > "$backup_file"; then
        log "INFO" "Backup de BD completado: $(basename "$backup_file") ($(du -h "$backup_file" | cut -f1))"
        echo "$backup_file"
    else
        log "ERROR" "Error al crear backup de base de datos"
        rm -f "$backup_file"
        return 1
    fi
}

backup_n8n_data() {
    local timestamp="$1"
    local backup_file="${BACKUP_DIR}/n8n_data_${timestamp}.tar.gz"
    local n8n_data_dir="${PROJECT_DIR}/n8n_data"
    
    log "INFO" "Iniciando backup de datos de n8n..."
    
    if [[ ! -d "$n8n_data_dir" ]]; then
        log "WARN" "Directorio n8n_data no existe, omitiendo..."
        return 0
    fi
    
    if tar -czf "$backup_file" -C "$PROJECT_DIR" n8n_data 2>/dev/null; then
        log "INFO" "Backup de datos completado: $(basename "$backup_file") ($(du -h "$backup_file" | cut -f1))"
        echo "$backup_file"
    else
        log "ERROR" "Error al crear backup de datos de n8n"
        rm -f "$backup_file"
        return 1
    fi
}

upload_to_drive() {
    local file="$1"
    local filename
    filename=$(basename "$file")
    
    log "INFO" "Subiendo a Google Drive: $filename"
    
    if rclone copy "$file" "${RCLONE_REMOTE}:${RCLONE_FOLDER}/" --progress 2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "Subida completada: $filename"
        return 0
    else
        log "ERROR" "Error al subir: $filename"
        return 1
    fi
}

cleanup_local() {
    log "INFO" "Limpiando backups locales mayores a ${LOCAL_RETENTION_DAYS} días..."
    
    local count
    count=$(find "$BACKUP_DIR" -name "*.gz" -mtime +"$LOCAL_RETENTION_DAYS" 2>/dev/null | wc -l)
    
    if [[ "$count" -gt 0 ]]; then
        find "$BACKUP_DIR" -name "*.gz" -mtime +"$LOCAL_RETENTION_DAYS" -delete
        log "INFO" "Eliminados $count backups locales antiguos"
    else
        log "INFO" "No hay backups locales antiguos para eliminar"
    fi
}

cleanup_remote() {
    log "INFO" "Limpiando backups remotos mayores a ${REMOTE_RETENTION_DAYS} días..."
    
    if rclone delete "${RCLONE_REMOTE}:${RCLONE_FOLDER}/" --min-age "${REMOTE_RETENTION_DAYS}d" 2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "Limpieza remota completada"
    else
        log "WARN" "Error en limpieza remota (puede que no haya archivos antiguos)"
    fi
}

send_notification() {
    local status="$1"
    local message="$2"
    
    # Aquí puedes agregar notificaciones (Discord, Telegram, etc.)
    # Ejemplo con curl a un webhook:
    # curl -X POST -H "Content-Type: application/json" \
    #   -d "{\"content\": \"$status: $message\"}" \
    #   "$DISCORD_WEBHOOK_URL"
    
    log "INFO" "Notificación: [$status] $message"
}

# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────
main() {
    local timestamp
    local db_backup=""
    local data_backup=""
    local success=true
    
    log "INFO" "════════════════════════════════════════════════════════"
    log "INFO" "Iniciando proceso de backup de n8n"
    log "INFO" "════════════════════════════════════════════════════════"
    
    # Verificar dependencias
    check_dependencies
    
    # Crear directorio de backups
    create_backup_dir
    
    # Obtener timestamp
    timestamp=$(get_timestamp)
    
    # Backup de base de datos
    if db_backup=$(backup_database "$timestamp"); then
        if [[ -n "$db_backup" ]]; then
            upload_to_drive "$db_backup" || success=false
        fi
    else
        success=false
    fi
    
    # Backup de datos de n8n
    if data_backup=$(backup_n8n_data "$timestamp"); then
        if [[ -n "$data_backup" ]]; then
            upload_to_drive "$data_backup" || success=false
        fi
    else
        success=false
    fi
    
    # Limpieza
    cleanup_local
    cleanup_remote
    
    # Resultado final
    if $success; then
        log "INFO" "════════════════════════════════════════════════════════"
        log "INFO" "✅ Backup completado exitosamente"
        log "INFO" "════════════════════════════════════════════════════════"
        send_notification "SUCCESS" "Backup de n8n completado"
    else
        log "ERROR" "════════════════════════════════════════════════════════"
        log "ERROR" "❌ Backup completado con errores"
        log "ERROR" "════════════════════════════════════════════════════════"
        send_notification "ERROR" "Backup de n8n falló"
        exit 1
    fi
}

# Ejecutar
main "$@"
