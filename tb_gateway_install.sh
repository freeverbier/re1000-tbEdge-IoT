#!/bin/bash
# =============================================================================
# Installation TB IoT Gateway sur Seeedstudio reTerminal DM (re1000)
# Plateforme : Raspberry Pi CM4 — Raspberry Pi OS 64-bit (Debian Bookworm)
# Auteur     : EnerGroup
# Usage      : sudo bash tb_gateway_install.sh [OPTIONS]
#
# Ce script déploie TB IoT Gateway en Docker, connecté à une instance locale
# de ThingsBoard Edge PE (installée via tb_edge_install.sh).
# Tous les connecteurs officiels sont activés dans la configuration.
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
  --access-token    TOKEN    Token d'accès du device Gateway dans TB Edge

Options facultatives :
  --tb-host         HOST     Hôte MQTT de TB Edge                 [défaut : localhost]
  --tb-port         PORT     Port MQTT de TB Edge                 [défaut : 1883]
  --tb-edge-http    HOST     Hôte HTTP de TB Edge (health check)  [défaut : localhost]
  --tb-edge-port    PORT     Port HTTP de TB Edge (health check)  [défaut : 8080]
  --skip-edge-check          Ne pas vérifier si TB Edge répond
  --version         VERSION  Version de l'image TB Gateway        [défaut : 3.8.1]
  --install-dir     PATH     Répertoire d'installation            [défaut : /opt/tb-gateway]
  --gw-name         NAME     Nom du gateway dans TB Edge          [défaut : TB-Gateway-re1000]
  -h, --help                 Affiche cette aide

Variables d'environnement (alternatives aux options CLI) :
  TB_GW_ACCESS_TOKEN, TB_HOST, TB_PORT, TB_EDGE_HTTP_HOST, TB_EDGE_HTTP_PORT,
  TB_GW_VERSION, INSTALL_DIR, GW_NAME

Exemples :
  # Passage par arguments CLI
  sudo bash tb_gateway_install.sh \\
    --access-token "votre-token-gateway"

  # Avec un serveur TB Edge distant
  sudo bash tb_gateway_install.sh \\
    --access-token "votre-token-gateway" \\
    --tb-host "192.168.1.100" \\
    --tb-port 1883

  # Via variables d'environnement
  export TB_GW_ACCESS_TOKEN="votre-token-gateway"
  sudo -E bash tb_gateway_install.sh

Prérequis :
  • ThingsBoard Edge PE installé et opérationnel (tb_edge_install.sh)
  • Un device de type "Gateway" créé dans TB Edge, avec son Access Token

EOF
    exit 0
}

# =============================================================================
# VALEURS PAR DÉFAUT
# =============================================================================
TB_GW_VERSION="${TB_GW_VERSION:-3.8.1}"
INSTALL_DIR="${INSTALL_DIR:-/opt/tb-gateway}"
TB_GW_ACCESS_TOKEN="${TB_GW_ACCESS_TOKEN:-}"
TB_HOST="${TB_HOST:-localhost}"
TB_PORT="${TB_PORT:-1883}"
# Hôte/port HTTP pour le health check TB Edge (séparé du host MQTT)
TB_EDGE_HTTP_HOST="${TB_EDGE_HTTP_HOST:-localhost}"
TB_EDGE_HTTP_PORT="${TB_EDGE_HTTP_PORT:-8080}"
SKIP_EDGE_CHECK="${SKIP_EDGE_CHECK:-false}"
GW_NAME="${GW_NAME:-TB-Gateway-re1000}"

# =============================================================================
# PARSING DES ARGUMENTS CLI
# =============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --access-token)   TB_GW_ACCESS_TOKEN="$2";  shift 2 ;;
        --tb-host)        TB_HOST="$2";             shift 2 ;;
        --tb-port)        TB_PORT="$2";             shift 2 ;;
        --tb-edge-http)   TB_EDGE_HTTP_HOST="$2";   shift 2 ;;
        --tb-edge-port)   TB_EDGE_HTTP_PORT="$2";   shift 2 ;;
        --skip-edge-check) SKIP_EDGE_CHECK="true";  shift   ;;
        --version)        TB_GW_VERSION="$2";       shift 2 ;;
        --install-dir)    INSTALL_DIR="$2";         shift 2 ;;
        --gw-name)        GW_NAME="$2";             shift 2 ;;
        -h|--help)       usage ;;
        *)               error "Option inconnue : $1. Utilisez --help pour la liste des options." ;;
    esac
done

# =============================================================================
# VALIDATION DES PARAMÈTRES OBLIGATOIRES
# =============================================================================
section "Validation des paramètres"

[[ -z "$TB_GW_ACCESS_TOKEN" ]] && \
    error "Paramètre obligatoire manquant : --access-token (ou TB_GW_ACCESS_TOKEN)\n\nCréez un device Gateway dans TB Edge puis récupérez son Access Token.\nUtilisez --help pour plus d'informations."

info "Paramètres validés ✓"
info "  Version Gateway  : $TB_GW_VERSION"
info "  TB Edge host     : $TB_HOST:$TB_PORT"
info "  Répertoire       : $INSTALL_DIR"
info "  Nom du Gateway   : $GW_NAME"

# =============================================================================
# 1. VÉRIFICATIONS PRÉLIMINAIRES
# =============================================================================
section "Vérification de l'environnement"

[[ $EUID -ne 0 ]] && error "Ce script doit être exécuté en root (sudo)."

# Vérifier que Docker est disponible
command -v docker &>/dev/null || error "Docker n'est pas installé. Exécutez d'abord tb_edge_install.sh."

# Vérifier que TB Edge est accessible
# On teste le port HTTP (TCP) et on accepte tout code HTTP (200, 302, 401 = TB Edge répond)
if [[ "$SKIP_EDGE_CHECK" == "true" ]]; then
    warn "Vérification TB Edge ignorée (--skip-edge-check)."
else
    TB_EDGE_URL="http://${TB_EDGE_HTTP_HOST}:${TB_EDGE_HTTP_PORT}/login"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$TB_EDGE_URL" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "000" ]]; then
        warn "TB Edge ne répond pas sur http://${TB_EDGE_HTTP_HOST}:${TB_EDGE_HTTP_PORT} (port fermé ou service non démarré)."
        warn "Si TB Edge est bien démarré, relancez avec --skip-edge-check pour ignorer cette vérification."
        read -rp "Continuer quand même ? [o/N] " r
        [[ "$r" != "o" ]] && exit 1
    else
        info "TB Edge accessible sur http://${TB_EDGE_HTTP_HOST}:${TB_EDGE_HTTP_PORT} (HTTP $HTTP_CODE) ✓"
    fi
fi

ARCH=$(uname -m)
[[ "$ARCH" != "aarch64" ]] && warn "Architecture détectée : $ARCH (attendu : aarch64)"
info "Architecture : $ARCH"

# =============================================================================
# 2. CRÉATION DE LA STRUCTURE DE RÉPERTOIRES
# =============================================================================
section "Création de la structure $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"/{config,extensions,logs}
cd "$INSTALL_DIR"

info "Structure créée ✓"
info "  $INSTALL_DIR/config/       — fichiers de configuration"
info "  $INSTALL_DIR/extensions/   — connecteurs Python personnalisés"
info "  $INSTALL_DIR/logs/         — logs du gateway"

# =============================================================================
# 3. CONFIGURATION PRINCIPALE tb_gateway.yaml
# =============================================================================
section "Génération de la configuration tb_gateway.yaml"

cat > "$INSTALL_DIR/config/tb_gateway.yaml" <<EOF
# =============================================================================
# ThingsBoard IoT Gateway — Configuration principale
# Généré par tb_gateway_install.sh — EnerGroup
# =============================================================================

thingsboard:
  host: ${TB_HOST}
  port: ${TB_PORT}
  # Sécurité TLS (désactivé par défaut, adapter si TB Edge est en TLS)
  security:
    accessToken: ${TB_GW_ACCESS_TOKEN}
    # Pour TLS : décommenter les lignes suivantes
    # type: tls
    # caCert: /etc/thingsboard-gateway/ca.pem
    # privateKey: /etc/thingsboard-gateway/private.pem
    # cert: /etc/thingsboard-gateway/certificate.pem

# Stockage local des données en cas de coupure réseau
storage:
  type: memory
  read_records_count: 100
  max_records_count: 100000

# Logs du gateway
logs:
  # Voir le volume tb-gateway-logs ou /opt/tb-gateway/logs/
  logLevel: INFO

# Statistiques remontées vers TB Edge
statistics:
  enable: true
  statsSendPeriodInSeconds: 3600

# Connecteurs activés — chaque fichier JSON est chargé au démarrage
connectors:
  - name: MQTT Connector
    type: mqtt
    configuration: mqtt.json

  - name: Modbus Connector
    type: modbus
    configuration: modbus.json

  - name: OPC-UA Connector
    type: opcua
    configuration: opcua.json

  - name: BACnet Connector
    type: bacnet
    configuration: bacnet.json

  - name: BLE Connector
    type: ble
    configuration: ble.json

  - name: Serial Connector
    type: serial
    configuration: serial.json

  - name: REST API Connector
    type: rest
    configuration: rest.json

  - name: SNMP Connector
    type: snmp
    configuration: snmp.json

  - name: FTP Connector
    type: ftp
    configuration: ftp.json

  - name: Socket Connector
    type: socket
    configuration: socket.json

  - name: CAN Connector
    type: can
    configuration: can.json

  - name: Custom Connector
    type: custom
    configuration: custom.json
    class: CustomConnector
    module: /thingsboard_gateway/extensions/custom/custom_connector.py
EOF

info "tb_gateway.yaml généré ✓"

# =============================================================================
# 4. CONFIGURATIONS DES CONNECTEURS
# =============================================================================
section "Génération des configurations de connecteurs"

# --------------------------------------------------------------------------
# MQTT Connector
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/mqtt.json" <<'EOF'
{
  "broker": {
    "name": "MQTT Broker local / externe",
    "host": "localhost",
    "port": 1883,
    "clientId": "tb-gw-mqtt-connector",
    "version": 5,
    "maxMessageNumberPerWorker": 10,
    "maxNumberOfWorkers": 100,
    "sendDataOnlyOnChange": false,
    "security": {
      "type": "anonymous"
    }
  },
  "mapping": [
    {
      "topicFilter": "sensors/+/data",
      "converter": {
        "type": "json",
        "deviceNameJsonExpression": "${deviceId}",
        "deviceTypeExpression": "default",
        "timeout": 60000,
        "attributes": [
          {"type": "string", "key": "model", "value": "${model}"}
        ],
        "timeseries": [
          {"type": "double", "key": "temperature", "value": "${temperature}"},
          {"type": "double", "key": "humidity",    "value": "${humidity}"}
        ]
      }
    }
  ],
  "connectRequests": [
    {
      "topicFilter": "sensors/+/connect",
      "deviceNameJsonExpression": "${serialNumber}"
    }
  ],
  "disconnectRequests": [
    {
      "topicFilter": "sensors/+/disconnect",
      "deviceNameJsonExpression": "${serialNumber}"
    }
  ],
  "attributeRequests": [],
  "attributeUpdates": [],
  "serverSideRpc": []
}
EOF

# --------------------------------------------------------------------------
# Modbus Connector
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/modbus.json" <<'EOF'
{
  "master": {
    "slaves": [
      {
        "host": "192.168.1.200",
        "port": 502,
        "type": "tcp",
        "method": "socket",
        "timeout": 35,
        "byteOrder": "BIG",
        "wordOrder": "LITTLE",
        "retries": true,
        "retryOnEmpty": true,
        "retryOnInvalid": true,
        "pollPeriod": 5000,
        "unitId": 1,
        "deviceName": "ModbusDevice",
        "deviceType": "default",
        "sendDataToThingsBoard": false,
        "attributes": [],
        "timeseries": [
          {
            "tag": "frequency",
            "type": "16int",
            "functionCode": 4,
            "objectsCount": 1,
            "address": 0
          },
          {
            "tag": "voltage",
            "type": "16int",
            "functionCode": 4,
            "objectsCount": 1,
            "address": 1
          }
        ],
        "attributeUpdates": [],
        "rpc": []
      }
    ]
  }
}
EOF

# --------------------------------------------------------------------------
# OPC-UA Connector
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/opcua.json" <<'EOF'
{
  "server": {
    "name": "OPC-UA Server",
    "url": "opc.tcp://localhost:4840/freeopcua/server/",
    "timeoutInMillis": 5000,
    "scanPeriodInMillis": 5000,
    "disableSubscriptions": false,
    "subCheckPeriodInMillis": 100,
    "showMap": false,
    "security": "None",
    "identity": {
      "type": "anonymous"
    },
    "mapping": [
      {
        "deviceNodePattern": "Root\\.Objects\\.Device1",
        "deviceNameSource": "I=2258",
        "deviceNameExpression": "${DeviceName}",
        "deviceTypeExpression": "default",
        "attributes": [
          {
            "key": "frequency",
            "path": "${Frequency}"
          }
        ],
        "timeseries": [
          {
            "key": "temperature",
            "path": "${Temperature}"
          }
        ],
        "rpc_methods": [],
        "attributes_updates": []
      }
    ]
  }
}
EOF

# --------------------------------------------------------------------------
# BACnet Connector
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/bacnet.json" <<'EOF'
{
  "general": {
    "objectName": "TB Gateway BACnet",
    "address": "0.0.0.0",
    "objectIdentifier": 599,
    "maxApduLengthAccepted": 1024,
    "segmentationSupported": "segmentedBoth",
    "vendorIdentifier": 15
  },
  "devices": [
    {
      "deviceName": "BACnet Controller",
      "deviceType": "default",
      "address": "192.168.1.100",
      "port": 47808,
      "pollPeriod": 10000,
      "timeseries": [
        {
          "key": "air_temperature",
          "objectType": "analogInput",
          "objectId": 1,
          "propertyId": "presentValue"
        },
        {
          "key": "room_setpoint",
          "objectType": "analogValue",
          "objectId": 10,
          "propertyId": "presentValue"
        }
      ],
      "attributes": [
        {
          "key": "device_name",
          "objectType": "device",
          "objectId": 0,
          "propertyId": "objectName"
        }
      ],
      "rpc": []
    }
  ]
}
EOF

# --------------------------------------------------------------------------
# BLE Connector
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/ble.json" <<'EOF'
{
  "devices": [
    {
      "name": "BLE Sensor",
      "MACAddress": "AA:BB:CC:DD:EE:FF",
      "pollPeriod": 5000,
      "showMap": false,
      "timeout": 10000,
      "attributes": [
        {
          "key": "firmware_version",
          "handle": "0x2a26",
          "method": "read"
        }
      ],
      "timeseries": [
        {
          "key": "temperature",
          "handle": "0xff01",
          "method": "notify",
          "converter": "decodeTemperature"
        }
      ]
    }
  ]
}
EOF

# --------------------------------------------------------------------------
# Serial Connector (RS232 / RS485)
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/serial.json" <<'EOF'
{
  "devices": [
    {
      "name": "Serial Device",
      "type": "default",
      "port": "/dev/ttyUSB0",
      "baudrate": 9600,
      "bytesize": 8,
      "parity": "N",
      "stopbits": 1,
      "timeout": 1,
      "charsize": 32,
      "converter": "SerialUplinkConverter",
      "delimiter": "\n",
      "timeseries": [
        {
          "key": "value",
          "dataExpression": "${payload}"
        }
      ]
    }
  ]
}
EOF

# --------------------------------------------------------------------------
# REST API Connector
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/rest.json" <<'EOF'
{
  "mapping": [
    {
      "endpoint": "/api/v1/telemetry",
      "HTTPMethods": ["POST"],
      "security": {
        "type": "anonymous"
      },
      "converter": {
        "type": "json",
        "deviceNameJsonExpression": "${deviceName}",
        "deviceTypeExpression": "default",
        "attributes": [],
        "timeseries": [
          {"type": "double", "key": "${key}", "value": "${value}"}
        ]
      }
    }
  ],
  "attributeUpdates": [],
  "serverSideRpc": []
}
EOF

# --------------------------------------------------------------------------
# SNMP Connector
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/snmp.json" <<'EOF'
{
  "devices": [
    {
      "deviceName": "SNMP Device",
      "deviceType": "default",
      "ip": "192.168.1.150",
      "port": 161,
      "version": "2c",
      "community": "public",
      "timeout": 3000,
      "retries": 3,
      "timeseries": [
        {
          "key": "sysUpTime",
          "OID": "1.3.6.1.2.1.1.3.0",
          "type": "str"
        },
        {
          "key": "ifInOctets",
          "OID": "1.3.6.1.2.1.2.2.1.10.1",
          "type": "int"
        }
      ],
      "attributes": [
        {
          "key": "sysDescr",
          "OID": "1.3.6.1.2.1.1.1.0",
          "type": "str"
        }
      ]
    }
  ]
}
EOF

# --------------------------------------------------------------------------
# FTP Connector
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/ftp.json" <<'EOF'
{
  "paths": [
    {
      "deviceName": "FTP Data Source",
      "deviceType": "default",
      "delimiter": ",",
      "path": "/data/*.csv",
      "host": "localhost",
      "port": 21,
      "username": "ftpuser",
      "password": "ftppassword",
      "readMode": "FULL",
      "maxFileSize": 5242880,
      "pollPeriod": 60000,
      "timeseries": [
        {
          "key": "temperature",
          "type": "float",
          "index": 1
        }
      ],
      "attributes": []
    }
  ]
}
EOF

# --------------------------------------------------------------------------
# Socket Connector (TCP/UDP)
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/socket.json" <<'EOF'
{
  "socket": {
    "type": "TCP",
    "address": "0.0.0.0",
    "port": 50000,
    "bufferSize": 1024,
    "charset": "utf-8",
    "timeout": 10
  },
  "devices": [
    {
      "address": ".*",
      "deviceName": "Socket Device ${clientAddress}",
      "deviceType": "default",
      "converter": "SocketUplinkConverter",
      "timeseries": [
        {
          "key": "payload",
          "dataExpression": "${payload}"
        }
      ]
    }
  ]
}
EOF

# --------------------------------------------------------------------------
# CAN Bus Connector
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/can.json" <<'EOF'
{
  "interface": "can0",
  "backend": "socketcan",
  "reconnect": true,
  "reconnectPeriod": 30.0,
  "pollPeriod": 1.0,
  "devices": [
    {
      "name": "CAN Device",
      "type": "default",
      "nodeId": 1,
      "timeseries": [
        {
          "key": "rpm",
          "nodeId": 1,
          "frameId": 256,
          "isExtendedId": false,
          "isFd": false,
          "byteorder": "big",
          "dataLength": 2,
          "dataOffset": 0,
          "multiplier": 1,
          "divider": 1,
          "addend": 0,
          "signed": false,
          "encoding": "utf-8"
        }
      ]
    }
  ]
}
EOF

# --------------------------------------------------------------------------
# Custom Connector (Python)
# --------------------------------------------------------------------------
cat > "$INSTALL_DIR/config/custom.json" <<'EOF'
{
  "name": "Custom Connector",
  "type": "custom",
  "class": "CustomConnector",
  "module": "/thingsboard_gateway/extensions/custom/custom_connector.py",
  "logLevel": "DEBUG",
  "sendDataOnlyOnChange": false,
  "configurationJson": {
    "pollPeriod": 5000,
    "devices": [
      {
        "name": "Custom Device",
        "type": "default"
      }
    ]
  }
}
EOF

# Exemple de connecteur Python personnalisé
mkdir -p "$INSTALL_DIR/extensions/custom"
cat > "$INSTALL_DIR/extensions/custom/custom_connector.py" <<'EOF'
"""
Exemple de connecteur personnalisé TB Gateway — EnerGroup
Adapté à votre protocole propriétaire.
"""
import time
import logging
from thingsboard_gateway.connectors.connector import Connector

log = logging.getLogger(__name__)


class CustomConnector(Connector):
    """Connecteur personnalisé — à adapter selon le protocole."""

    def __init__(self, gateway, config, connector_type):
        super().__init__()
        self.__config = config
        self.__gateway = gateway
        self.__connector_type = connector_type
        self.__stopped = False
        self.name = config.get("name", "Custom Connector")
        self.daemon = True

    def open(self):
        self.__stopped = False
        self.start()
        log.info("[%s] Connecteur démarré", self.name)

    def run(self):
        while not self.__stopped:
            try:
                # === Votre logique de collecte ici ===
                # Exemple : lecture d'un registre et envoi à TB
                data = {
                    "deviceName": "My Custom Device",
                    "deviceType": "default",
                    "attributes": [],
                    "telemetry": [
                        {"ts": int(time.time() * 1000),
                         "values": {"example_value": 42.0}}
                    ]
                }
                self.__gateway.send_to_storage(self.name, data)
                time.sleep(self.__config.get("configurationJson", {}).get("pollPeriod", 5000) / 1000)
            except Exception as e:
                log.exception("[%s] Erreur dans run(): %s", self.name, e)
                time.sleep(5)

    def close(self):
        self.__stopped = True
        log.info("[%s] Connecteur arrêté", self.name)

    def get_name(self):
        return self.name

    def is_connected(self):
        return not self.__stopped

    def on_attributes_update(self, content):
        log.debug("[%s] Mise à jour d'attribut : %s", self.name, content)

    def server_side_rpc_handler(self, content):
        log.debug("[%s] RPC reçu : %s", self.name, content)
EOF

info "Configurations des connecteurs générées ✓"

# =============================================================================
# 5. GÉNÉRATION DU docker-compose.yml
# =============================================================================
section "Génération du docker-compose.yml"

cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
# TB IoT Gateway ${TB_GW_VERSION}
# Généré automatiquement par tb_gateway_install.sh — EnerGroup

services:
  tb-gateway:
    restart: always
    image: "thingsboard/tb-gateway:${TB_GW_VERSION}"
    container_name: tb-gateway
    # Accès aux interfaces hardware (BLE, CAN, Serial)
    privileged: true
    # Réseau host pour accès direct aux équipements locaux
    # (Modbus TCP, OPC-UA, BACnet, etc.)
    network_mode: host
    environment:
      # Connexion à TB Edge
      host: ${TB_HOST}
      port: "${TB_PORT}"
      accessToken: ${TB_GW_ACCESS_TOKEN}
      # Performances sur CM4
      PYTHONUNBUFFERED: "1"
    volumes:
      # Configuration
      - ./config:/thingsboard_gateway/config
      # Connecteurs Python personnalisés
      - ./extensions:/thingsboard_gateway/extensions
      # Logs persistants
      - tb-gateway-logs:/thingsboard_gateway/logs
      # Accès aux ports série (RS232/RS485)
      - /dev:/dev

volumes:
  tb-gateway-logs:
    name: tb-gateway-logs
EOF

info "docker-compose.yml généré ✓"

# =============================================================================
# 6. SERVICE SYSTEMD
# =============================================================================
section "Création du service systemd tb-gateway"

cat > /etc/systemd/system/tb-gateway.service <<EOF
[Unit]
Description=ThingsBoard IoT Gateway
After=network-online.target docker.service tb-edge.service
Wants=network-online.target
Requires=docker.service
# Attendre que TB Edge soit opérationnel avant de démarrer le gateway
After=tb-edge.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tb-gateway.service
info "Service systemd tb-gateway activé ✓"

# =============================================================================
# 7. DÉMARRAGE
# =============================================================================
section "Pull de l'image TB Gateway"
docker compose -f "$INSTALL_DIR/docker-compose.yml" pull

section "Démarrage de TB Gateway"
docker compose -f "$INSTALL_DIR/docker-compose.yml" up -d

# =============================================================================
# 8. VÉRIFICATION
# =============================================================================
section "Vérification du démarrage (30 secondes)"
sleep 5
if docker compose -f "$INSTALL_DIR/docker-compose.yml" ps | grep -q "Up"; then
    info "TB Gateway est démarré ✓"
    docker compose -f "$INSTALL_DIR/docker-compose.yml" ps
else
    warn "TB Gateway ne semble pas démarré. Vérifiez les logs :"
    warn "  docker compose -C ${INSTALL_DIR} logs -f tb-gateway"
fi

# =============================================================================
# 9. RÉSUMÉ
# =============================================================================
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  ThingsBoard IoT Gateway installé avec succès !${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  TB Edge cible  : mqtt://${TB_HOST}:${TB_PORT}"
echo "  Access Token   : ${TB_GW_ACCESS_TOKEN}"
echo "  Config dir     : ${INSTALL_DIR}/config/"
echo "  Extensions dir : ${INSTALL_DIR}/extensions/"
echo ""
echo "  Connecteurs activés :"
echo "    • MQTT          → ${INSTALL_DIR}/config/mqtt.json"
echo "    • Modbus TCP    → ${INSTALL_DIR}/config/modbus.json"
echo "    • OPC-UA        → ${INSTALL_DIR}/config/opcua.json"
echo "    • BACnet        → ${INSTALL_DIR}/config/bacnet.json"
echo "    • BLE           → ${INSTALL_DIR}/config/ble.json"
echo "    • Serial RS232  → ${INSTALL_DIR}/config/serial.json"
echo "    • REST API      → ${INSTALL_DIR}/config/rest.json"
echo "    • SNMP          → ${INSTALL_DIR}/config/snmp.json"
echo "    • FTP           → ${INSTALL_DIR}/config/ftp.json"
echo "    • Socket TCP    → ${INSTALL_DIR}/config/socket.json"
echo "    • CAN Bus       → ${INSTALL_DIR}/config/can.json"
echo "    • Custom Python → ${INSTALL_DIR}/extensions/custom/"
echo ""
echo "  Commandes utiles :"
echo "    Logs          : docker compose -C ${INSTALL_DIR} logs -f tb-gateway"
echo "    Redémarrer    : systemctl restart tb-gateway"
echo "    Arrêter       : systemctl stop tb-gateway"
echo "    État          : systemctl status tb-gateway"
echo ""
echo -e "${YELLOW}  Prochaine étape :${NC}"
echo "  Adaptez les fichiers JSON dans ${INSTALL_DIR}/config/"
echo "  selon vos équipements terrain, puis :"
echo "    systemctl restart tb-gateway"
echo ""
