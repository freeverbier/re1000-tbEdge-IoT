#!/bin/bash
# =============================================================================
# Installation ThingsBoard Edge PE sur Seeedstudio reTerminal DM (re1000)
# Plateforme : Raspberry Pi CM4 — Raspberry Pi OS 64-bit (Debian Bookworm)
# Auteur     : EnerGroup
# Usage      : sudo bash tb_edge_install.sh [OPTIONS]
# =============================================================================

set -euo pipefail

# --- Couleurs pour les messages ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}=== $* ===${NC}"; }

# =============================================================================
# AIDE
# =============================================================================
usage() {
    cat <<EOF

Usage: sudo bash $(basename "$0") [OPTIONS]

Options obligatoires :
  --routing-key     KEY      Clé de routage Edge (depuis TB Server)
  --routing-secret  SECRET   Secret de routage Edge (depuis TB Server)
  --cloud-host      HOST     FQDN ou IP du serveur ThingsBoard parent
  --edge-license    LICENSE  Clé de licence ThingsBoard Edge PE

Options facultatives :
  --version         VERSION  Version de l'image TB Edge PE  [défaut : 4.3.0.1EDGEPE]
  --install-dir     PATH     Répertoire d'installation       [défaut : /opt/tb-edge]
  --cloud-port      PORT     Port gRPC du serveur parent     [défaut : 7070]
  --cloud-ssl       BOOL     SSL activé (true/false)         [défaut : false]
  --pg-password     PASS     Mot de passe PostgreSQL         [défaut : généré aléatoirement]
  -h, --help                 Affiche cette aide

Variables d'environnement (alternatives aux options CLI) :
  TB_EDGE_VERSION, INSTALL_DIR, CLOUD_ROUTING_KEY, CLOUD_ROUTING_SECRET,
  CLOUD_RPC_HOST, CLOUD_RPC_PORT, CLOUD_RPC_SSL_ENABLED, EDGE_LICENSE,
  POSTGRES_PASSWORD

Exemples :
  # Passage par arguments CLI
  sudo bash tb_edge_install.sh \\
    --routing-key   "abc123" \\
    --routing-secret "secret456" \\
    --cloud-host    "mon-serveur.exemple.com" \\
    --edge-license  "XXXX-YYYY-ZZZZ"

  # Passage par variables d'environnement
  export CLOUD_ROUTING_KEY="abc123"
  export CLOUD_ROUTING_SECRET="secret456"
  export CLOUD_RPC_HOST="mon-serveur.exemple.com"
  export EDGE_LICENSE="XXXX-YYYY-ZZZZ"
  sudo -E bash tb_edge_install.sh

EOF
    exit 0
}

# =============================================================================
# VALEURS PAR DÉFAUT (écrasables par env ou CLI)
# =============================================================================
TB_EDGE_VERSION="${TB_EDGE_VERSION:-4.3.0.1EDGEPE}"
INSTALL_DIR="${INSTALL_DIR:-/opt/tb-edge}"
CLOUD_ROUTING_KEY="${CLOUD_ROUTING_KEY:-}"
CLOUD_ROUTING_SECRET="${CLOUD_ROUTING_SECRET:-}"
CLOUD_RPC_HOST="${CLOUD_RPC_HOST:-}"
CLOUD_RPC_PORT="${CLOUD_RPC_PORT:-7070}"
CLOUD_RPC_SSL_ENABLED="${CLOUD_RPC_SSL_ENABLED:-false}"
EDGE_LICENSE="${EDGE_LICENSE:-}"
# Mot de passe PostgreSQL — généré automatiquement si non fourni
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 20 2>/dev/null || echo "tb_edge_$(date +%s)")}"

# =============================================================================
# PARSING DES ARGUMENTS CLI
# =============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --routing-key)     CLOUD_ROUTING_KEY="$2";     shift 2 ;;
        --routing-secret)  CLOUD_ROUTING_SECRET="$2";  shift 2 ;;
        --cloud-host)      CLOUD_RPC_HOST="$2";         shift 2 ;;
        --cloud-port)      CLOUD_RPC_PORT="$2";         shift 2 ;;
        --cloud-ssl)       CLOUD_RPC_SSL_ENABLED="$2";  shift 2 ;;
        --edge-license)    EDGE_LICENSE="$2";            shift 2 ;;
        --version)         TB_EDGE_VERSION="$2";         shift 2 ;;
        --install-dir)     INSTALL_DIR="$2";             shift 2 ;;
        --pg-password)     POSTGRES_PASSWORD="$2";       shift 2 ;;
        -h|--help)         usage ;;
        *)                 error "Option inconnue : $1. Utilisez --help pour la liste des options." ;;
    esac
done

# =============================================================================
# VALIDATION DES PARAMÈTRES OBLIGATOIRES
# =============================================================================
section "Validation des paramètres"

MISSING=()
[[ -z "$CLOUD_ROUTING_KEY"    ]] && MISSING+=("--routing-key    (ou CLOUD_ROUTING_KEY)")
[[ -z "$CLOUD_ROUTING_SECRET" ]] && MISSING+=("--routing-secret (ou CLOUD_ROUTING_SECRET)")
[[ -z "$CLOUD_RPC_HOST"       ]] && MISSING+=("--cloud-host     (ou CLOUD_RPC_HOST)")
[[ -z "$EDGE_LICENSE"         ]] && MISSING+=("--edge-license   (ou EDGE_LICENSE)")

if [[ ${#MISSING[@]} -gt 0 ]]; then
    error "Paramètres obligatoires manquants :\n$(printf '  • %s\n' "${MISSING[@]}")\n\nUtilisez --help pour la liste complète des options."
fi

info "Paramètres validés ✓"
info "  Version TB Edge  : $TB_EDGE_VERSION"
info "  Cloud host       : $CLOUD_RPC_HOST:$CLOUD_RPC_PORT (SSL: $CLOUD_RPC_SSL_ENABLED)"
info "  Répertoire       : $INSTALL_DIR"

# =============================================================================
# 1. VÉRIFICATIONS PRÉLIMINAIRES
# =============================================================================
section "Vérification de l'environnement"

[[ $EUID -ne 0 ]] && error "Ce script doit être exécuté en root (sudo)."

ARCH=$(uname -m)
[[ "$ARCH" != "aarch64" ]] && warn "Architecture détectée : $ARCH (attendu : aarch64). Continuer ? [o/N]" && read -r r && [[ "$r" != "o" ]] && exit 1

OS_ID=$(. /etc/os-release && echo "$ID")
OS_VER=$(. /etc/os-release && echo "$VERSION_CODENAME")
info "OS : $OS_ID $OS_VER | Arch : $ARCH"

# Mémoire minimale recommandée : 2 GB
TOTAL_MEM_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)
[[ $TOTAL_MEM_MB -lt 1800 ]] && warn "RAM disponible : ${TOTAL_MEM_MB} MB. Minimum recommandé : 2 GB."
info "RAM disponible : ${TOTAL_MEM_MB} MB ✓"

# =============================================================================
# 2. MISE À JOUR SYSTÈME
# =============================================================================
section "Mise à jour des paquets système"
apt-get update -qq
apt-get upgrade -y -qq

# =============================================================================
# 3. INSTALLATION DE DOCKER
# =============================================================================
section "Installation de Docker"

if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version)
    info "Docker déjà installé : $DOCKER_VER"
else
    apt-get install -y -qq ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} ${OS_VER} stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker
    info "Docker installé et démarré ✓"
fi

# Ajouter l'utilisateur courant au groupe docker (hors root)
SUDO_USER_NAME="${SUDO_USER:-}"
if [[ -n "$SUDO_USER_NAME" ]] && ! groups "$SUDO_USER_NAME" | grep -q docker; then
    usermod -aG docker "$SUDO_USER_NAME"
    info "Utilisateur '$SUDO_USER_NAME' ajouté au groupe docker (reconnexion requise)"
fi

# =============================================================================
# 4. OPTIMISATIONS RASPBERRY PI CM4
# =============================================================================
section "Optimisations CM4"

# Swap — ThingsBoard Edge recommande 2 GB minimum
SWAP_FILE="/swapfile"
if [[ ! -f "$SWAP_FILE" ]]; then
    info "Création d'un fichier swap de 2 GB..."
    fallocate -l 2G "$SWAP_FILE"
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
    swapon "$SWAP_FILE"
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    info "Swap 2 GB activé ✓"
else
    info "Fichier swap existant détecté ✓"
fi

# Désactiver l'overcommit agressif (évite OOM killer sur Postgres)
sysctl -w vm.overcommit_memory=1 > /dev/null
echo "vm.overcommit_memory=1" >> /etc/sysctl.d/99-tb-edge.conf

# =============================================================================
# 5. CRÉATION DU RÉPERTOIRE D'INSTALLATION
# =============================================================================
section "Création du répertoire $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# =============================================================================
# 6. GÉNÉRATION DU docker-compose.yml
# =============================================================================
section "Génération du docker-compose.yml"

cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
# ThingsBoard Edge PE ${TB_EDGE_VERSION}
# Généré automatiquement par tb_edge_install.sh — EnerGroup

services:
  mytbedge:
    restart: always
    image: "thingsboard/tb-edge-pe:${TB_EDGE_VERSION}"
    ports:
      - "8080:8080"
      - "1883:1883"
      - "5683-5688:5683-5688/udp"
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/tb-edge
      SPRING_DATASOURCE_USERNAME: postgres
      SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD}
      EDGE_LICENSE_INSTANCE_DATA_FILE: /data/instance-edge-license.data
      EDGE_LICENSE_SECRET: ${EDGE_LICENSE}
      CLOUD_ROUTING_KEY: ${CLOUD_ROUTING_KEY}
      CLOUD_ROUTING_SECRET: ${CLOUD_ROUTING_SECRET}
      CLOUD_RPC_HOST: ${CLOUD_RPC_HOST}
      CLOUD_RPC_PORT: ${CLOUD_RPC_PORT}
      CLOUD_RPC_SSL_ENABLED: "${CLOUD_RPC_SSL_ENABLED}"
      # Limiter la JVM pour CM4 (ajuster si besoin)
      JAVA_OPTS: "-Xms256m -Xmx512m"
    volumes:
      - tb-edge-data:/data
      - tb-edge-logs:/var/log/tb-edge
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    restart: always
    image: "postgres:16"
    ports:
      - "5432"
    environment:
      POSTGRES_DB: tb-edge
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - tb-edge-postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d tb-edge"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  tb-edge-data:
    name: tb-edge-data
  tb-edge-logs:
    name: tb-edge-logs
  tb-edge-postgres-data:
    name: tb-edge-postgres-data
EOF

info "docker-compose.yml généré ✓"

# =============================================================================
# 7. SERVICE SYSTEMD (démarrage automatique au boot)
# =============================================================================
section "Création du service systemd"

cat > /etc/systemd/system/tb-edge.service <<EOF
[Unit]
Description=ThingsBoard Edge PE
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tb-edge.service
info "Service systemd tb-edge activé ✓"

# =============================================================================
# 8. PULL DES IMAGES ET DÉMARRAGE
# =============================================================================
section "Pull des images Docker (peut prendre plusieurs minutes sur CM4)"
docker compose -f "$INSTALL_DIR/docker-compose.yml" pull

section "Démarrage de ThingsBoard Edge"
docker compose -f "$INSTALL_DIR/docker-compose.yml" up -d

# =============================================================================
# 9. ATTENTE DE DÉMARRAGE ET VÉRIFICATION
# =============================================================================
section "Attente du démarrage (90 secondes max)"
MAX_WAIT=90; ELAPSED=0
until curl -sf http://localhost:8080/api/v1/noauth/featureFlags &>/dev/null; do
    sleep 5; ELAPSED=$((ELAPSED+5))
    echo -n "."
    [[ $ELAPSED -ge $MAX_WAIT ]] && break
done
echo ""

if curl -sf http://localhost:8080/api/v1/noauth/featureFlags &>/dev/null; then
    info "ThingsBoard Edge est UP et répond sur le port 8080 ✓"
else
    warn "ThingsBoard Edge ne répond pas encore. Vérifiez les logs :"
    warn "  docker compose -C ${INSTALL_DIR} logs -f mytbedge"
fi

# =============================================================================
# 10. RÉSUMÉ
# =============================================================================
LOCAL_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  ThingsBoard Edge PE installé avec succès !${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Interface web  : http://${LOCAL_IP}:8080"
echo "  MQTT Broker    : ${LOCAL_IP}:1883"
echo "  Cloud parent   : https://${CLOUD_RPC_HOST}"
echo "  Routing Key    : ${CLOUD_ROUTING_KEY}"
echo ""
echo "  Mot de passe Postgres : ${POSTGRES_PASSWORD}"
echo "  (conservez-le dans un endroit sûr)"
echo ""
echo "  Commandes utiles :"
echo "    Logs Edge    : docker compose -C ${INSTALL_DIR} logs -f mytbedge"
echo "    Logs Postgres: docker compose -C ${INSTALL_DIR} logs -f postgres"
echo "    Redémarrer   : systemctl restart tb-edge"
echo "    Arrêter      : systemctl stop tb-edge"
echo ""
echo -e "${YELLOW}  Compte par défaut TB Edge :${NC}"
echo "    Login    : sysadmin@thingsboard.org"
echo "    Password : sysadmin"
echo -e "${YELLOW}  → Changez ce mot de passe immédiatement après la première connexion !${NC}"
echo ""
