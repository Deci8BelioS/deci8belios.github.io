#!/bin/bash

# Uso: GPG_FINGERPRINT=xxx GPG_PASSPHRASE=yyy ./build.sh

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

GPG_KEY="${GPG_FINGERPRINT:-}"
GPG_PASS="${GPG_PASSPHRASE:-}"
OUTPUT_DIR="."
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="build_$(date +%Y%m%d_%H%M%S).log"

# Metadatos del repositorio
REPO_ORIGIN="DeciBelioS - REPO"
REPO_LABEL="DeciBelioS - REPO"
REPO_SUITE="stable"
REPO_VERSION="1.0"
REPO_CODENAME="decibelios-repo"
REPO_ARCHITECTURES="iphoneos-arm iphoneos-arm64"
REPO_COMPONENTS="main"
REPO_DESCRIPTION="DeciBelioS - REPO"

# Directorios de paquetes
dirs=(./pool ./pool/iphoneos-arm ./pool/iphoneos-arm64)

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
    local required_cmds=(apt-ftparchive gpg)
    local compression_cmds=(zstd xz bzip2 gzip lzma lz4)

    # Verificar herramientas esenciales
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "❌ ERROR: Faltan dependencias críticas: ${missing_deps[*]}" >&2
        exit 1
    fi

    # Verificar herramientas de compresión (advertencias)
    local missing_compression=()
    for cmd in "${compression_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_compression+=("$cmd")
        fi
    done

    if [ ${#missing_compression[@]} -ne 0 ]; then
        echo "⚠️  ADVERTENCIA: Compresores no disponibles: ${missing_compression[*]}"
        echo "   El repositorio funcionará pero sin algunos formatos de compresión"
    fi
}

# Validar variables críticas
validate_config() {
    if [ -z "$GPG_KEY" ]; then
        echo "❌ ERROR: GPG_FINGERPRINT no está definido" >&2
        echo "   Uso: GPG_FINGERPRINT=tu_fingerprint ./$(basename "$0")" >&2
        exit 1
    fi

    if [ -z "$GPG_PASS" ]; then
        echo "⚠️  ADVERTENCIA: GPG_PASSPHRASE no está definido"
        echo "   Se solicitará interactivamente (puede causar problemas en CI/CD)"
    fi

    # Verificar que la clave GPG existe
    if ! gpg --list-secret-keys "$GPG_KEY" &> /dev/null; then
        echo "❌ ERROR: No se encontró la clave GPG: $GPG_KEY" >&2
        echo "   Claves disponibles:" >&2
        gpg --list-secret-keys --keyid-format LONG >&2
        exit 1
    fi
}

# Configurar variables según arquitectura
set_arch_vars() {
    case $(basename "$1") in
        pool)
            output_dir="$OUTPUT_DIR"
            extra=(extra_packages*)
            arch_name="multi-arch"
            ;;
        iphoneos-arm)
            output_dir="$OUTPUT_DIR/rootful"
            extra=(extra_packages_rootful)
            arch_name="rootful (arm)"
            ;;
        iphoneos-arm64)
            output_dir="$OUTPUT_DIR/rootless"
            extra=(extra_packages_rootless)
            arch_name="rootless (arm64)"
            ;;
        *)
            echo "❌ ERROR: Arquitectura desconocida: $1" >&2
            return 1
            ;;
    esac
}

# Limpiar y preparar directorios de forma segura
prepare_directories() {
    echo "📁 Preparando estructura de directorios..."

    # Validar que OUTPUT_DIR no esté vacío o sea peligroso
    if [ -z "$OUTPUT_DIR" ] || [ "$OUTPUT_DIR" = "/" ] || [ "$OUTPUT_DIR" = "/root" ]; then
        echo "❌ ERROR: OUTPUT_DIR tiene un valor peligroso: $OUTPUT_DIR" >&2
        exit 1
    fi

    # Eliminar solo los subdirectorios específicos
    rm -rf "${OUTPUT_DIR:?}/rootful" "${OUTPUT_DIR:?}/rootless"

    # Crear estructura
    mkdir -p "$OUTPUT_DIR"/{rootful,rootless}

    echo "✓ Directorios preparados"
}

# Verificar que existan paquetes
check_packages_exist() {
    local found_packages=false

    for d in "${dirs[@]}"; do
        if [ -d "$d" ] && compgen -G "$d/*.deb" > /dev/null; then
            found_packages=true
            break
        fi
    done

    if [ "$found_packages" = false ]; then
        echo "⚠️  ADVERTENCIA: No se encontraron archivos .deb en ningún directorio"
        echo "   Directorios esperados: ${dirs[*]}"
        return 1
    fi

    return 0
}

# ============================================================================
# FUNCIONES DE GENERACIÓN
# ============================================================================

# Comprimir archivo en paralelo si es posible
compress_file() {
    local input_file="$1"
    local format="$2"
    local output_file="${input_file}.${format}"

    case "$format" in
        zst)
            if command -v zstd &> /dev/null; then
                zstd -q -c19 -T0 "$input_file" > "$output_file"
            fi
            ;;
        xz)
            if command -v xz &> /dev/null; then
                # Usar pxz si está disponible para compresión paralela
                if command -v pxz &> /dev/null; then
                    pxz -c9 "$input_file" > "$output_file"
                else
                    xz -c9 -T0 "$input_file" > "$output_file"
                fi
            fi
            ;;
        bz2)
            if command -v bzip2 &> /dev/null; then
                # Usar pbzip2 si está disponible para compresión paralela
                if command -v pbzip2 &> /dev/null; then
                    pbzip2 -c9 "$input_file" > "$output_file"
                else
                    bzip2 -c9 "$input_file" > "$output_file"
                fi
            fi
            ;;
        gz)
            if command -v gzip &> /dev/null; then
                # Usar pigz si está disponible para compresión paralela
                if command -v pigz &> /dev/null; then
                    pigz -c9 "$input_file" > "$output_file"
                else
                    gzip -nc9 "$input_file" > "$output_file"
                fi
            fi
            ;;
        lzma)
            if command -v lzma &> /dev/null; then
                lzma -c9 "$input_file" > "$output_file"
            fi
            ;;
        lz4)
            if command -v lz4 &> /dev/null; then
                lz4 -c9 "$input_file" > "$output_file"
            fi
            ;;
    esac
}

# Generar archivos Packages
generate_packages() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Generando archivos Packages..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for d in "${dirs[@]}"; do
        if ! set_arch_vars "$d"; then
            continue
        fi

        echo "  → Procesando: $arch_name ($d)"

        # Verificar que el directorio existe
        if [ ! -d "$d" ]; then
            echo "    ⚠️  Directorio no existe, saltando"
            continue
        fi

        # Generar Packages con caché de base de datos para mejor rendimiento
        if ! apt-ftparchive \
            --db "$output_dir/apt-ftparchive.db" \
            -o APT::FTPArchive::AlwaysStat=false \
            packages "$d" > "$output_dir/Packages" 2>/dev/null; then
            echo "    ⚠️  Error generando Packages, archivo puede estar vacío"
        fi

        # Agregar línea en blanco y paquetes extras
        echo >> "$output_dir/Packages"
        for extra_file in "${extra[@]}"; do
            if [ -f "$extra_file" ]; then
                cat "$extra_file" >> "$output_dir/Packages"
                echo "    ✓ Agregado: $extra_file"
            fi
        done 2>/dev/null

        # Comprimir en paralelo
        echo "    🗜️  Comprimiendo..."
        for format in zst xz bz2 gz lzma lz4; do
            compress_file "$output_dir/Packages" "$format" &
        done
        wait

        echo "    ✓ Completado: $arch_name"
    done
}

# Generar archivos Release
generate_release() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Generando archivos Release..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for d in "${dirs[@]}"; do
        if ! set_arch_vars "$d"; then
            continue
        fi

        echo "  → Procesando: $arch_name"

        if [ ! -d "$output_dir" ]; then
            echo "    ⚠️  Directorio de salida no existe, saltando"
            continue
        fi

        apt-ftparchive \
            -o APT::FTPArchive::Release::Origin="$REPO_ORIGIN" \
            -o APT::FTPArchive::Release::Label="$REPO_LABEL" \
            -o APT::FTPArchive::Release::Suite="$REPO_SUITE" \
            -o APT::FTPArchive::Release::Version="$REPO_VERSION" \
            -o APT::FTPArchive::Release::Codename="$REPO_CODENAME" \
            -o APT::FTPArchive::Release::Architectures="$REPO_ARCHITECTURES" \
            -o APT::FTPArchive::Release::Components="$REPO_COMPONENTS" \
            -o APT::FTPArchive::Release::Description="$REPO_DESCRIPTION" \
            release "$output_dir" > "$output_dir/Release"

        echo "    ✓ Completado: $arch_name"
    done
}

# Firmar archivos Release
sign_release() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔐 Firmando archivos Release con GPG..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Clave: $GPG_KEY"

    for d in "${dirs[@]}"; do
        if ! set_arch_vars "$d"; then
            continue
        fi

        echo "  → Firmando: $arch_name"

        if [ ! -f "$output_dir/Release" ]; then
            echo "    ⚠️  Release no existe, saltando"
            continue
        fi

        # Preparar opciones de GPG
        local gpg_opts=(
            --batch
            --yes
            -u "$GPG_KEY"
        )

        # Agregar passphrase si está definida
        if [ -n "$GPG_PASS" ]; then
            gpg_opts+=(
                --pinentry-mode loopback
                --passphrase "$GPG_PASS"
            )
        fi

        # Firma separada (Release.gpg)
        if gpg "${gpg_opts[@]}" -abs \
            -o "$output_dir/Release.gpg" \
            "$output_dir/Release" 2>/dev/null; then
            echo "    ✓ Release.gpg creado"
        else
            echo "    ❌ Error firmando Release.gpg" >&2
            return 1
        fi

        # Firma inline (InRelease)
        if gpg "${gpg_opts[@]}" --clearsign \
            -o "$output_dir/InRelease" \
            "$output_dir/Release" 2>/dev/null; then
            echo "    ✓ InRelease creado"
        else
            echo "    ❌ Error firmando InRelease" >&2
            return 1
        fi
    done
}

# Mostrar resumen
show_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 RESUMEN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for d in "${dirs[@]}"; do
        if ! set_arch_vars "$d"; then
            continue
        fi

        if [ ! -d "$output_dir" ]; then
            continue
        fi

        local pkg_count=0
        if [ -f "$output_dir/Packages" ]; then
            pkg_count=$(grep -c "^Package:" "$output_dir/Packages" 2>/dev/null || echo "0")
        fi

        echo ""
        echo "  📁 $arch_name ($output_dir)"
        echo "     Paquetes: $pkg_count"

        if [ -f "$output_dir/Release" ]; then
            echo "     ✓ Release"
        fi
        if [ -f "$output_dir/Release.gpg" ]; then
            echo "     ✓ Release.gpg (firmado)"
        fi
        if [ -f "$output_dir/InRelease" ]; then
            echo "     ✓ InRelease (firmado)"
        fi

        # Listar formatos de compresión disponibles
        local formats=()
        for ext in zst xz bz2 gz lzma lz4; do
            if [ -f "$output_dir/Packages.$ext" ]; then
                formats+=("$ext")
            fi
        done
        if [ ${#formats[@]} -gt 0 ]; then
            echo "     Formatos: ${formats[*]}"
        fi
    done
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   Generador de Repositorio APT para iOS/iPadOS      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""

    cd "$SCRIPT_DIR" || {
        echo "❌ ERROR: No se puede acceder al directorio del script" >&2
        exit 1
    }

    setup_logging
    check_dependencies
    validate_config

    if ! check_packages_exist; then
        echo ""
        echo "⚠️  No hay paquetes para procesar, terminando"
        exit 0
    fi

    prepare_directories
    generate_packages
    generate_release
    sign_release
    show_summary

    echo ""
    echo "✅ ¡Repositorio generado exitosamente!"
    echo "📝 Log guardado en: $LOG_FILE"
    echo "=== Fin: $(date) ==="
}

# Ejecutar main
main "$@"
