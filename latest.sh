#!/bin/bash

get_latest_version() {
    repo_url="$1"
    latest_version=$(curl -s "https://api.github.com/repos/${repo_url}/releases/latest" | jq -r '.tag_name')
    echo "$latest_version"
}

get_files_list() {
    repo_url="$1"
    version="$2"
    files_list=$(curl -s "https://api.github.com/repos/${repo_url}/releases/tags/${version}" | jq -r '.assets[].name')
    echo "$files_list"
}

download_package() {
    url="$1"
    directory="$2"
    file_name="$3"
    
    if [ -f "$directory/$file_name" ]; then
        echo "El archivo $directory/$file_name ya existe. Saltando descarga."
    else
        wget "$url" -O "$directory/$file_name"
        echo "Descargado: $directory/$file_name"
    fi
}

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
    "Meeep1/EeveeSpotifyRevivedPublic"
    "raulsaeed/BHTikTokPlusPlus"
    "arichornlover/YouTube-Reborn-v5"
    "SoCuul/SCInsta"
    "faroukbmiled/RyukGram"
)

mkdir -p pool/iphoneos-arm pool/iphoneos-arm64

downloads_made=false

for repo_info in "${repositories[@]}"; do
    IFS='/' read -r -a parts <<< "$repo_info"
    repo_url="${parts[0]}/${parts[1]}"
    
    echo "Procesando $repo_url..."
    
    latest_version=$(get_latest_version "$repo_url")
    
    if [ -z "$latest_version" ] || [ "$latest_version" == "null" ]; then
        echo "  No se encontró versión o error en API para $repo_url"
        continue
    fi

    files_list=$(get_files_list "$repo_url" "$latest_version")
    
    for file in $files_list; do
        download_url="https://github.com/${repo_url}/releases/download/${latest_version}/${file}"
        if [[ $file == *iphoneos-arm.deb ]]; then
            download_package "$download_url" "pool/iphoneos-arm" "$file"
            downloads_made=true
        elif [[ $file == *iphoneos-arm64.deb ]]; then
            download_package "$download_url" "pool/iphoneos-arm64" "$file"
            downloads_made=true
        elif [[ $file == *"rootless"*.deb ]] || [[ $file =~ rootfu(ll|l).*\.deb ]]; then
            echo "  Detectado paquete variante (Rootless/Rootfull): $file"
            download_package "$download_url" "pool/iphoneos-arm64" "$file"
            downloads_made=true
        fi
    done
done

if [ "$downloads_made" = true ]; then
    if [ -f "build.sh" ]; then
        chmod +x build.sh
        ./build.sh
        echo "Build ejecutado correctamente."
    else
        echo "Advertencia: Se realizaron descargas pero no se encontró 'build.sh'."
    fi
    echo "Descarga completa."
else
    echo "No se realizaron nuevas descargas. Saliendo sin ejecutar comandos adicionales."
fi