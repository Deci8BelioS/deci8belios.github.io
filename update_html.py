from collections import defaultdict
from packaging.version import parse as parse_version

DEFAULT_ICON_URL = 'Icon.png'

def parse_packages_file(filepath):
    """Analiza el archivo 'Packages' principal y extrae los detalles de cada paquete."""
    packages = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error CRÍTICO: El archivo principal de paquetes '{filepath}' no fue encontrado.")
        return []
    package_blocks = content.strip().split('\n\n')
    for block in package_blocks:
        if not block.strip(): continue
        package_info = {}
        for line in block.strip().split('\n'):
            if ':' in line:
                key, value = line.split(':', 1)
                package_info[key.strip()] = value.strip()
        if 'Package' in package_info and 'Version' in package_info:
            packages.append(package_info)
    return packages

def filter_and_prioritize_tweaks(packages):
    """
    Agrupa por un ID normalizado (minúsculas), prioriza por arquitectura
    y luego selecciona la versión más reciente del grupo prioritario.
    """
    grouped_packages = defaultdict(list)
    for pkg in packages:
        normalized_id = pkg['Package'].lower()
        grouped_packages[normalized_id].append(pkg)
    final_packages = []
    for package_id, versions in grouped_packages.items():
        if not versions:
            continue
        rootless_tweaks = [p for p in versions if p.get('Architecture') == 'iphoneos-arm64']
        rootful_tweaks = [p for p in versions if p.get('Architecture') == 'iphoneos-arm']
        chosen_tweak = None
        if rootless_tweaks:
            chosen_tweak = max(rootless_tweaks, key=lambda p: parse_version(p.get('Version', '0')))
        elif rootful_tweaks:
            chosen_tweak = max(rootful_tweaks, key=lambda p: parse_version(p.get('Version', '0')))
        else:
            chosen_tweak = max(versions, key=lambda p: parse_version(p.get('Version', '0')))
        if chosen_tweak:
            final_packages.append(chosen_tweak)
    return final_packages

def generate_html_list(packages):
    """Genera una lista de elementos <li> en HTML a partir de la lista de paquetes."""
    if not packages:
        return "<li class='no-tweaks'>No se encontraron paquetes.</li>"
    html = ""
    sorted_packages = sorted(packages, key=lambda p: p.get('Name', p.get('Package', '')).lower())
    for pkg in sorted_packages:
        name = pkg.get('Name', pkg.get('Package'))
        version = pkg.get('Version', 'N/A')
        description = pkg.get('Description', 'Sin descripción.')
        icon_url = pkg.get('Icon', DEFAULT_ICON_URL)
        html += f"""
        <li>
            <img src="{icon_url}" alt="{name} icon" class="tweak-icon" onerror="this.src='{DEFAULT_ICON_URL}';">
            <div class="tweak-info">
                <div class="tweak-header">
                    <strong>{name}</strong>
                    <span>v{version}</span>
                </div>
                <p>{description}</p>
            </div>
        </li>
        """
    return html

def update_index_html(html_list):
    """Lee el archivo de plantilla, reemplaza el marcador y guarda el resultado en index.html."""
    template_path = 'index.template.html'
    output_path = 'index.html'
    try:
        with open(template_path, 'r', encoding='utf-8') as f: content = f.read()
    except FileNotFoundError:
        print(f"Error CRÍTICO: El archivo de plantilla '{template_path}' no fue encontrado.")
        return
    placeholder = '<!-- TWEAKS_LIST_PLACEHOLDER -->'
    if placeholder not in content:
        print(f"Error CRÍTICO: Marcador '{placeholder}' no encontrado en '{template_path}'.")
        return
    new_content = content.replace(placeholder, html_list)
    with open(output_path, 'w', encoding='utf-8') as f: f.write(new_content)
    print(f"'{output_path}' generado con la lista de tweaks definitiva.")

if __name__ == '__main__':
    packages_file = './Packages'
    all_packages = parse_packages_file(packages_file)
    final_tweak_list = filter_and_prioritize_tweaks(all_packages)
    tweaks_html_list = generate_html_list(final_tweak_list)
    update_index_html(tweaks_html_list)