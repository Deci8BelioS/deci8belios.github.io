#!/bin/bash

# Uso: GITHUB_TOKEN=tu_token ./script.sh

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
MAX_PARALLEL_DOWNLOADS=3
LOG_FILE="download_$(date +%Y%m%d_%H%M%S).log"

# Repositorios
repositories=(
    "opa334/TrollStore"
    "dayanch96/uYouLocalization"
    "BandarHL/BHTwitter"
    "BandarHL/BHInstagram"
    "Lessica/TrollSpeed"
    "dayanch96/YTLite"
    "dayanch96/YTMusicUltimate"
    "dayanch96/InfusePlus"
    "dayanch96/BHTikTok-Plus"
    "khanhduytran0/TrollPad"
    "khanhduytran0/CAPerfHUD"
    "whoeevee/EeveeSpotifyReborn"
    "raulsaeed/BHTikTokPlusPlus"
    "arichornlover/YouTube-Reborn-v5"
    "SoCuul/SCInsta"
)

# ============================================================================
# FUNCIONES DE UTILIDAD
# ============================================================================

# Configurar logging
setup_logging() {
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
    echo "=== Inicio: $(date) ==="
}

# Verificar dependencias
check_dependencies() {
    local missing_deps=()

    for cmd in curl jq wget; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "ERROR: Faltan las siguientes dependencias: ${missing_deps[*]}" >&2
        echo "Instálalas con: sudo apt install ${missing_deps[*]} (Debian/Ubuntu)" >&2
        echo "               o: brew install ${missing_deps[*]} (macOS)" >&2
        exit 1
    fi
}

# Mostrar advertencias iniciales
show_warnings() {
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "⚠️  ADVERTENCIA: No se detectó GITHUB_TOKEN"
        echo "   Sin autenticación estás limitado a 60 requests/hora"
        echo "   Genera un token en: https://github.com/settings/tokens"
        echo "   Úsalo así: GITHUB_TOKEN=tu_token ./$(basename "$0")"
        echo ""
    fi
}

# ============================================================================
# FUNCIONES DE GITHUB API
# ============================================================================

# Obtener la última versión de un repositorio
get_latest_version() {
    local repo_url="$1"
    local auth_header=""

    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="-H "Authorization: Bearer $GITHUB_TOKEN""
    fi

    local response
    response=$(eval curl -s $auth_header "https://api.github.com/repos/${repo_url}/releases/latest")

    # Verificar errores de API
    if echo "$response" | jq -e '.message' &> /dev/null; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.message')
        echo "ERROR: API GitHub - $error_msg (repo: $repo_url)" >&2
        return 1
    fi

    local latest_version
    latest_version=$(echo "$response" | jq -r '.tag_name')

    if [ "$latest_version" = "null" ] || [ -z "$latest_version" ]; then
        echo "ERROR: No se encontró release para $repo_url" >&2
        return 1
    fi

    echo "$latest_version"
}

# Obtener lista de archivos de una versión específica
get_files_list() {
    local repo_url="$1"
    local version="$2"
    local auth_header=""

    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="-H "Authorization: Bearer $GITHUB_TOKEN""
    fi

    local response
    response=$(eval curl -s $auth_header "https://api.github.com/repos/${repo_url}/releases/tags/${version}")

    local files_list
    files_list=$(echo "$response" | jq -r '.assets[].name')

    echo "$files_list"
}

# ============================================================================
# FUNCIONES DE DESCARGA
# ============================================================================

# Descargar un paquete
download_package() {
    local url="$1"
    local directory="$2"
    local file_name="$3"
    local full_path="$directory/$file_name"

    # Verificar si ya existe
    if [ -f "$full_path" ]; then
        echo "✓ Ya existe: $file_name"
        return 0
    fi

    # Intentar descarga
    echo "⬇ Descargando: $file_name"

    if wget -q --show-progress --timeout=30 --tries=3 "$url" -O "$full_path.tmp"; then
        mv "$full_path.tmp" "$full_path"
        echo "✓ Completado: $file_name"
        return 0
    else
        echo "✗ Error descargando: $file_name" >&2
        rm -f "$full_path.tmp"
        return 1
    fi
}

# Procesar un repositorio
process_repository() {
    local repo_url="$1"
    local downloads_made=0

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Procesando: $repo_url"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local latest_version
    if ! latest_version=$(get_latest_version "$repo_url"); then
        echo "⚠️  Saltando repositorio debido a error"
        return 0
    fi

    echo "📌 Última versión: $latest_version"

    local files_list
    files_list=$(get_files_list "$repo_url" "$latest_version")

    if [ -z "$files_list" ]; then
        echo "⚠️  No se encontraron archivos en esta release"
        return 0
    fi

    # Descargar archivos
    while IFS= read -r file; do
        [ -z "$file" ] && continue

        # Limitar descargas paralelas
        while [ "$(jobs -r | wc -l)" -ge "$MAX_PARALLEL_DOWNLOADS" ]; do
            sleep 0.5
        done

        if [[ $file == *iphoneos-arm.deb ]]; then
            download_package                 "https://github.com/${repo_url}/releases/download/${latest_version}/${file}"                 "pool/iphoneos-arm"                 "$file" &
            downloads_made=1
        elif [[ $file == *iphoneos-arm64.deb ]]; then
            download_package                 "https://github.com/${repo_url}/releases/download/${latest_version}/${file}"                 "pool/iphoneos-arm64"                 "$file" &
            downloads_made=1
        fi
    done <<< "$files_list"

    # Esperar a que terminen las descargas de este repo
    wait

    return $downloads_made
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   Descargador de Tweaks de iOS desde GitHub         ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""

    setup_logging
    check_dependencies
    show_warnings

    # Crear estructura de directorios
    mkdir -p pool/iphoneos-arm pool/iphoneos-arm64
    echo "✓ Directorios creados"

    # Variable para rastrear descargas
    local total_downloads=0

    # Procesar cada repositorio
    for repo_info in "${repositories[@]}"; do
        if process_repository "$repo_info"; then
            ((total_downloads++)) || true
        fi
    done

    # Esperar a todas las descargas pendientes
    wait

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 RESUMEN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Ejecutar build.sh si hubo descargas
    if [ $total_downloads -gt 0 ]; then
        echo "✓ Se realizaron descargas de $total_downloads repositorios"

        if [ -f "build.sh" ]; then
            echo "🔨 Ejecutando build.sh..."
            chmod +x build.sh
            ./build.sh
        else
            echo "⚠️  build.sh no encontrado, saltando"
        fi

        echo "✅ Proceso completado exitosamente"
    else
        echo "ℹ️  No se realizaron nuevas descargas"
        echo "   Todos los archivos ya estaban descargados"
    fi

    echo ""
    echo "📝 Log guardado en: $LOG_FILE"
    echo "=== Fin: $(date) ==="
}

# Ejecutar main
main "$@"
