#!/bin/bash
# 🧪 Test: restore_n8n_data

set -euo pipefail

# Configuración del entorno de pruebas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$(mktemp -d)"

# Exportar variables para sobreescribir las del script
export PROJECT_DIR="$TEST_DIR"
export BACKUP_DIR="${TEST_DIR}/backups"
export COMPOSE_FILE="${TEST_DIR}/docker-compose.yml"

# Configuración de mocks
export MOCK_BIN="${TEST_DIR}/bin"
export MOCK_LOG="${TEST_DIR}/mock.log"

# Importar el script
source "${PROJECT_ROOT}/scripts/restore.sh"

setup() {
    mkdir -p "$MOCK_BIN" "$BACKUP_DIR"
    export PATH="$MOCK_BIN:$PATH"
    > "$MOCK_LOG"

    # Crear directorios y archivos de prueba
    touch "${BACKUP_DIR}/test_backup.tar.gz"
    touch "$COMPOSE_FILE"

    # Mocks
    cat << 'EOF' > "${MOCK_BIN}/docker"
#!/bin/bash
echo "docker $@" >> "$MOCK_LOG"
EOF

    cat << 'EOF' > "${MOCK_BIN}/tar"
#!/bin/bash
echo "tar $@" >> "$MOCK_LOG"
if [[ "${TAR_FAIL:-0}" == "1" ]]; then
    exit 1
fi
EOF

    cat << 'EOF' > "${MOCK_BIN}/date"
#!/bin/bash
echo "20230101120000"
EOF

    chmod +x "${MOCK_BIN}/docker" "${MOCK_BIN}/tar" "${MOCK_BIN}/date"
    export TAR_FAIL=0
}

teardown() {
    rm -rf "$TEST_DIR"
}

test_restore_n8n_data_happy_path() {
    echo "▶️  Test: restore_n8n_data (Happy Path sin datos existentes)"
    setup

    # Asegurarnos que n8n_data NO existe
    rm -rf "${PROJECT_DIR}/n8n_data"

    restore_n8n_data "${BACKUP_DIR}/test_backup.tar.gz"

    # Verificaciones
    if ! grep -q "docker compose -f ${TEST_DIR}/docker-compose.yml stop n8n" "$MOCK_LOG"; then
        echo "❌ Error: No se detuvo el contenedor n8n"
        exit 1
    fi
    if ! grep -q "tar -xzf ${TEST_DIR}/backups/test_backup.tar.gz -C ${TEST_DIR}" "$MOCK_LOG"; then
        echo "❌ Error: No se ejecutó tar correctamente"
        exit 1
    fi
    if ! grep -q "docker compose -f ${TEST_DIR}/docker-compose.yml start n8n" "$MOCK_LOG"; then
        echo "❌ Error: No se reinició el contenedor n8n"
        exit 1
    fi

    echo "✅ Test pasado"
}

test_restore_n8n_data_existing_data() {
    echo "▶️  Test: restore_n8n_data (Con datos existentes)"
    setup

    # Crear directorio n8n_data
    mkdir -p "${PROJECT_DIR}/n8n_data"
    touch "${PROJECT_DIR}/n8n_data/dummy.txt"

    restore_n8n_data "${BACKUP_DIR}/test_backup.tar.gz"

    # Verificaciones
    if [[ -d "${PROJECT_DIR}/n8n_data" ]]; then
        echo "❌ Error: El directorio original n8n_data no debería existir (debió moverse a .bak)"
        exit 1
    fi
    if [[ ! -d "${PROJECT_DIR}/n8n_data.bak.20230101120000" ]]; then
        echo "❌ Error: No se creó el backup del directorio n8n_data (.bak.20230101120000)"
        exit 1
    fi

    echo "✅ Test pasado"
}

test_restore_n8n_data_tar_fail() {
    echo "▶️  Test: restore_n8n_data (Error en tar)"
    setup

    export TAR_FAIL=1

    # Ejecutar y capturar el código de salida
    set +e
    restore_n8n_data "${BACKUP_DIR}/test_backup.tar.gz"
    local exit_code=$?
    set -e

    # Verificaciones
    if [[ $exit_code -eq 0 ]]; then
        echo "❌ Error: La función debería retornar error si tar falla"
        exit 1
    fi
    if grep -q "docker compose -f ${TEST_DIR}/docker-compose.yml start n8n" "$MOCK_LOG"; then
        echo "❌ Error: No se debería iniciar el contenedor si tar falla"
        exit 1
    fi

    echo "✅ Test pasado"
}

main() {
    trap teardown EXIT
    echo "🧪 Ejecutando tests para restore.sh..."
    test_restore_n8n_data_happy_path
    test_restore_n8n_data_existing_data
    test_restore_n8n_data_tar_fail
    echo "🎉 Todos los tests pasaron correctamente."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
