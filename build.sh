#!/bin/bash
OUTPUT_DIR="."

script_full_path=$(dirname "$0")
cd "$script_full_path" || exit 1
rm -rf $OUTPUT_DIR
mkdir -p $OUTPUT_DIR/{rootful,rootless}

dirs=(./pool ./pool/iphoneos-arm ./pool/iphoneos-arm64)

set_arch_vars() {
    case $(basename "$1") in
        pool)
            output_dir=$OUTPUT_DIR
            extra=(extra_packages*)
            ;;
        iphoneos-arm)
            output_dir=$OUTPUT_DIR/rootful
            extra=(extra_packages_rootful)
            ;;
        iphoneos-arm64)
            output_dir=$OUTPUT_DIR/rootless
            extra=(extra_packages_rootless)
            ;;
    esac
}

# Buscar claves GPG disponibles
available_keys=$(gpg --list-secret-keys --keyid-format LONG)
GPG_KEY=""

# Seleccionar la primera clave GPG encontrada (puedes ajustar esta lógica según tus necesidades)
if [ -n "$available_keys" ]; then
    GPG_KEY=$(echo "$available_keys" | grep -oP '^sec\s+\K\S+(?=\s+)' | head -n 1)
fi

if [ -z "$GPG_KEY" ]; then
    echo "No se encontraron claves GPG disponibles."
    exit 1
fi

echo "Se utilizará una clave GPG para firmar los archivos."

echo "[*] Generando paquetes..."
for d in "${dirs[@]}"; do
    set_arch_vars "$d"
    apt-ftparchive packages "$d" > $output_dir/Packages
    echo >> $output_dir/Packages
    cat "${extra[@]}" >> $output_dir/Packages 2>/dev/null
    zstd -q -c19 $output_dir/Packages > $output_dir/Packages.zst
    xz -c9 $output_dir/Packages > $output_dir/Packages.xz
    bzip2 -c9 $output_dir/Packages > $output_dir/Packages.bz2
    gzip -nc9 $output_dir/Packages > $output_dir/Packages.gz
    lzma -c9 $output_dir/Packages > $output_dir/Packages.lzma
    lz4 -c9 $output_dir/Packages > $output_dir/Packages.lz4
done

echo "[*] Generando release..."
for d in "${dirs[@]}"; do
    set_arch_vars "$d"
    apt-ftparchive \
        -o APT::FTPArchive::Release::Origin="DeciBelioS - REPO" \
        -o APT::FTPArchive::Release::Label="DeciBelioS - REPO" \
        -o APT::FTPArchive::Release::Suite="stable" \
        -o APT::FTPArchive::Release::Version="1.0" \
        -o APT::FTPArchive::Release::Codename="decibelios-repo" \
        -o APT::FTPArchive::Release::Architectures="iphoneos-arm iphoneos-arm64" \
        -o APT::FTPArchive::Release::Components="main" \
        -o APT::FTPArchive::Release::Description="DeciBelioS - REPO" \
        release $output_dir > $output_dir/Release
done

echo "[*] Firma de release mediante clave GPG..."
for d in "${dirs[@]}"; do
    set_arch_vars "$d"
    gpg -abs -u $GPG_KEY -o $output_dir/Release.gpg $output_dir/Release
    gpg -abs -u $GPG_KEY --clearsign -o $output_dir/InRelease $output_dir/Release
done

echo "[*] ¡Hecho!"
