#!/bin/bash

GPG_KEY="$GPG_FINGERPRINT"
OUTPUT_DIR="./dist"

script_full_path=$(dirname "$0")
cd "$script_full_path" || exit 1

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/rootful" "$OUTPUT_DIR/rootless"

dirs=(./pool ./pool/iphoneos-arm ./pool/iphoneos-arm64)

set_arch_vars() {
    case $(basename "$1") in
        pool)
            output_path="$OUTPUT_DIR"
            extra=(extra_packages*)
            origin_label="DeciBelioS - Main"
            ;;
        iphoneos-arm)
            output_path="$OUTPUT_DIR/rootful"
            extra=(extra_packages_rootful)
            origin_label="DeciBelioS - Rootful"
            ;;
        iphoneos-arm64)
            output_path="$OUTPUT_DIR/rootless"
            extra=(extra_packages_rootless)
            origin_label="DeciBelioS - Rootless"
            ;;
    esac
}

echo "[*] Comprobando dependencias..."
if ! command -v apt-ftparchive &> /dev/null; then
    echo "Error: apt-ftparchive no está instalado (instala apt-utils)."
    exit 1
fi

echo "[*] Generando paquetes..."
for d in "${dirs[@]}"; do
    if [ ! -d "$d" ]; then continue; fi
    set_arch_vars "$d"
    echo " -> Procesando $d hacia $output_path"
    apt-ftparchive packages "$d" > "$output_path/Packages"
    if ls ${extra[@]} 1> /dev/null 2>&1; then
        cat "${extra[@]}" >> "$output_path/Packages" 2>/dev/null
    fi
    if command -v zstd >/dev/null; then zstd -q -c19 "$output_path/Packages" > "$output_path/Packages.zst"; fi
    if command -v xz >/dev/null; then xz -c9 "$output_path/Packages" > "$output_path/Packages.xz"; fi
    if command -v bzip2 >/dev/null; then bzip2 -c9 "$output_path/Packages" > "$output_path/Packages.bz2"; fi
    if command -v gzip >/dev/null; then gzip -nc9 "$output_path/Packages" > "$output_path/Packages.gz"; fi
    if command -v lzma >/dev/null; then lzma -c9 "$output_path/Packages" > "$output_path/Packages.lzma"; fi
    if command -v lz4 >/dev/null; then lz4 -c9 "$output_path/Packages" > "$output_path/Packages.lz4"; fi
done

echo "[*] Generando archivos Release..."
for d in "${dirs[@]}"; do
    if [ ! -d "$d" ]; then continue; fi
    set_arch_vars "$d"
    apt-ftparchive \
        -o APT::FTPArchive::Release::Origin="DeciBelioS" \
        -o APT::FTPArchive::Release::Label="$origin_label" \
        -o APT::FTPArchive::Release::Suite="stable" \
        -o APT::FTPArchive::Release::Version="1.0" \
        -o APT::FTPArchive::Release::Codename="ios" \
        -o APT::FTPArchive::Release::Architectures="iphoneos-arm iphoneos-arm64" \
        -o APT::FTPArchive::Release::Components="main" \
        -o APT::FTPArchive::Release::Description="Repositorio de DeciBelioS para iOS" \
        release "$output_path" > "$output_path/Release"
done

echo "[*] Firmando Release con GPG..."
if [ -z "$GPG_KEY" ]; then
    echo "Advertencia: GPG_FINGERPRINT no está definida. Saltando firma."
else
    for d in "${dirs[@]}"; do
        if [ ! -d "$d" ]; then continue; fi
        set_arch_vars "$d"
        # Firma GPG (Release.gpg)
        gpg --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" --batch --yes -abs -u "$GPG_KEY" -o "$output_path/Release.gpg" "$output_path/Release"
        # Firma InRelease (firmado dentro del archivo, preferido por gestores modernos)
        gpg --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" --batch --yes --clearsign -u "$GPG_KEY" -o "$output_path/InRelease" "$output_path/Release"
    done
fi

echo "[*] ¡Proceso completado! Los archivos están en la carpeta: dist/"