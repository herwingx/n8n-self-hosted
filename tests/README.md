# Tests — n8n Self-Hosted

En este documento se describe **qué hace cada test**, **qué script y funciones prueba** y **cómo ejecutarlos**. Los tests usan **mocks** de Docker, rclone, tar, gzip y crontab, así que no requieren servicios reales ni credenciales.

---

## Cómo ejecutar

Desde la raíz del proyecto:

```bash
# Ejecutar todos los tests
./tests/run_all_tests.sh
```

O un test concreto:

```bash
./tests/test_install.sh
./tests/test_backup_database.sh
# ... etc.
```

---

## Qué hace cada test (resumen)

| Archivo | Script probado | Función(es) probada(s) |
|--------|----------------|------------------------|
| `test_install.sh` | `scripts/install.sh` | `check_dependencies`, `check_rclone_config` |
| `test_backup_database.sh` | `scripts/backup.sh` | `backup_database` |
| `test_backup_n8n_data.sh` | `scripts/backup.sh` | `backup_n8n_data` |
| `test_upload_to_drive.sh` | `scripts/backup.sh` | `upload_to_drive` |
| `test_backup_cleanup_remote.sh` | `scripts/backup.sh` | `cleanup_remote` |
| `test_restore_database.sh` | `scripts/restore.sh` | `restore_database` |
| `test_restore.sh` | `scripts/restore.sh` | `download_from_drive` |
| `test_syntax.sh` | `scripts/install.sh` | Carga del script (sintaxis) |
| `test_setup_cron_verify.sh` | `scripts/install.sh` | `setup_cron` |

---

## Detalle: qué valida cada test

### `test_install.sh`
- **check_dependencies**: (1) Todo OK cuando docker y rclone están; (2) Falla si falta docker; (3) Falla si falta rclone; (4) Falla si faltan ambos.
- **check_rclone_config**: (1) Falla y mensaje claro si no existe remote `gdrive`; (2) Crea carpeta `N8N` en Drive si no existe; (3) No hace nada si ya existe `gdrive` y carpeta `N8N`.

### `test_backup_database.sh`
- **backup_database**: (1) Éxito cuando docker y gzip responden bien y se crea el `.sql.gz`; (2) Falla y no deja archivo si `docker compose exec` falla; (3) Falla y no deja archivo si `gzip` falla.

### `test_backup_n8n_data.sh`
- **backup_n8n_data**: (1) Si no existe `n8n_data/`, no falla y registra WARN; (2) Si existe, crea el `.tar.gz` y devuelve la ruta; (3) Si `tar` falla, devuelve error, registra ERROR y elimina el archivo parcial.

### `test_upload_to_drive.sh`
- **upload_to_drive**: (1) Éxito cuando rclone copia bien; (2) Falla cuando rclone devuelve error.

### `test_backup_cleanup_remote.sh`
- **cleanup_remote**: (1) Éxito y log INFO cuando rclone delete va bien; (2) Log WARN (pero no falla el script) cuando rclone delete falla (p. ej. sin archivos antiguos).

### `test_restore_database.sh`
- **restore_database**: (1) Falla con mensaje claro si el servicio `db` no está corriendo; (2) Éxito cuando db está arriba y gunzip + psql van bien; (3) Falla si `gunzip` falla; (4) Falla si `docker compose exec` (psql) falla.

### `test_restore.sh`
- **download_from_drive**: (1) Descarga correcta: rclone con argumentos esperados, log de éxito y devuelve la ruta local; (2) Fallo: rclone falla, log de error y no devuelve ruta.

### `test_syntax.sh`
- Comprueba que `scripts/install.sh` se puede cargar con `source` sin errores de sintaxis.

### `test_setup_cron_verify.sh`
- **setup_cron**: (1) Crontab vacío → añade la línea de backup n8n; (2) Si ya existe la entrada n8n-backup → no duplica; (3) Si hay otros jobs → los mantiene y añade el de n8n. Usa un crontab mock en `/tmp` para no tocar el crontab real.

## Benchmark (opcional)

- **`benchmark_setup_cron.sh`**: mide tiempos de la versión “original” vs la optimizada de `setup_cron`. No es un test de corrección; ejecutar solo si quieres comparar rendimiento.

## Convenciones

- Cada test es un script bash que hace `exit 0` si todo pasa y `exit 1` si algo falla.
- Los tests en `tests/` asumen que se ejecutan desde la raíz del repo (p. ej. `./tests/test_install.sh`) o que el directorio de trabajo es el repo; usan `SCRIPT_DIR`/`PROJECT_DIR` para localizar `scripts/`.

## Nota sobre `test_install.sh`

Los casos de `check_rclone_config` mockean `rclone` en un subshell. En algunos entornos puede ejecutarse el `rclone` real si está en el PATH, y entonces el test puede fallar (p. ej. si no tienes el remote `gdrive`). Los tests de `check_dependencies` no dependen de eso y suelen pasar siempre.
