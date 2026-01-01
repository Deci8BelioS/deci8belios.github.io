#!/bin/bash
GPG_KEY="$GPG_FINGERPRINT"
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