#!/bin/bash

# Función para obtener la última versión de un repositorio en GitHub
get_latest_version() {
    repo_url="$1"
    latest_version=$(curl -s "https://api.github.com/repos/${repo_url}/releases/latest" | jq -r '.tag_name')
    echo "$latest_version"
}

# Función para obtener la lista de archivos disponibles en una versión específica
get_files_list() {
    repo_url="$1"
    version="$2"
    files_list=$(curl -s "https://api.github.com/repos/${repo_url}/releases/tags/${version}" | jq -r '.assets[].name')
    echo "$files_list"
}

# Función para descargar un paquete y colocarlo en la carpeta correspondiente
download_package() {
    url="$1"
    directory="$2"
    file_name="$3"
    
    # Verificar si el archivo ya existe
    if [ -f "$directory/$file_name" ]; then
        echo "El archivo $directory/$file_name ya existe. Saltando descarga."
    else
        wget "$url" -O "$directory/$file_name"
        echo "Descargado: $directory/$file_name"
    fi
}

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

# Crear la estructura de directorios
mkdir -p pool/iphoneos-arm pool/iphoneos-arm64

# Variable para rastrear si se realizaron descargas
downloads_made=false

# Descargar los paquetes
for repo_info in "${repositories[@]}"; do
    IFS='/' read -r -a parts <<< "$repo_info"
    repo_url="${parts[0]}/${parts[1]}"
    package_name="${parts[2]}"
    
    echo "Procesando $repo_url..."
    
    latest_version=$(get_latest_version "$repo_url")
    
    # Verificación simple para evitar errores si la API falla o no hay releases
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
        elif [[ $file == *"rootless"*.deb ]] || [[ $file == *"rootfull"*.deb ]]; then
            echo "  Detectado paquete variante (Rootless/Rootfull): $file"
            download_package "$download_url" "pool/iphoneos-arm64" "$file"
            downloads_made=true
        fi
    done
done

# Ejecutar comandos adicionales solo si se realizaron descargas
if [ "$downloads_made" = true ]; then
    # Ejecutar build.sh desde el repositorio clonado
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