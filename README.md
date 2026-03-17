# re1000 — ThingsBoard Edge IoT

Scripts d'installation et de configuration de la stack IoT **ThingsBoard Edge PE + TB Gateway** sur le module **Seeedstudio reTerminal DM (re1000)** équipé d'un Raspberry Pi CM4.

---

## Matériel cible

| Composant | Détail |
|-----------|--------|
| Plateforme | Seeedstudio reTerminal DM (re1000) |
| SoC | Raspberry Pi Compute Module 4 |
| Architecture | ARM64 (aarch64) |
| OS | Raspberry Pi OS 64-bit — Debian Bookworm |
| RAM recommandée | 4 GB (2 GB minimum) |
| Stockage | microSD ou eMMC ≥ 16 GB |

---

## Contenu du dépôt

| Fichier | Description |
|---------|-------------|
| `tb_edge_install.sh` | Installation de ThingsBoard Edge PE en Docker |
| `tb_gateway_install.sh` | Installation de TB IoT Gateway en Docker (connecteurs inclus) |

---

## 1. ThingsBoard Edge PE — `tb_edge_install.sh`

### Ce que fait le script

1. **Valide les paramètres** — vérifie que tous les credentials obligatoires sont fournis
2. **Vérifie l'environnement** — root requis, architecture aarch64, RAM disponible
3. **Met à jour le système** — `apt-get update && upgrade`
4. **Installe Docker** — Docker CE + Compose plugin (si absent)
5. **Optimise le CM4** — création d'un swap 2 GB, réglage `vm.overcommit_memory`
6. **Génère le `docker-compose.yml`** dans le répertoire d'installation avec :
   - Service `mytbedge` — image `thingsboard/tb-edge-pe`
   - Service `postgres` — PostgreSQL 16 avec healthcheck
7. **Crée un service systemd `tb-edge`** — démarrage automatique au boot
8. **Démarre la stack** — `docker compose pull` puis `up -d`
9. **Vérifie le démarrage** — sonde l'API REST sur le port 8080

### Prérequis

- Raspberry Pi OS 64-bit (Bookworm) fraîchement installé
- Accès Internet (pull des images Docker)
- Compte ThingsBoard Server PE avec une instance Edge provisionée
- Clé de licence ThingsBoard Edge PE

### Paramètres du script

Tous les credentials et paramètres de déploiement sont passés en **arguments CLI** ou via des **variables d'environnement**. Aucune valeur sensible n'est codée en dur dans le script.

#### Options obligatoires

| Option CLI | Variable d'env | Description |
|-----------|----------------|-------------|
| `--routing-key KEY` | `CLOUD_ROUTING_KEY` | Clé de routage Edge — générée lors du provisioning de l'Edge sur le serveur TB |
| `--routing-secret SECRET` | `CLOUD_ROUTING_SECRET` | Secret de routage Edge associé |
| `--cloud-host HOST` | `CLOUD_RPC_HOST` | FQDN ou IP du serveur ThingsBoard parent (ex: `mon-serveur.exemple.com`) |
| `--edge-license LICENSE` | `EDGE_LICENSE` | Clé de licence ThingsBoard Edge PE |

#### Options facultatives

| Option CLI | Variable d'env | Défaut | Description |
|-----------|----------------|--------|-------------|
| `--version VERSION` | `TB_EDGE_VERSION` | `4.3.0.1EDGEPE` | Tag de l'image Docker TB Edge PE |
| `--install-dir PATH` | `INSTALL_DIR` | `/opt/tb-edge` | Répertoire d'installation |
| `--cloud-port PORT` | `CLOUD_RPC_PORT` | `7070` | Port gRPC du serveur parent |
| `--cloud-ssl BOOL` | `CLOUD_RPC_SSL_ENABLED` | `false` | Activer TLS sur la connexion gRPC (`true`/`false`) |
| `--pg-password PASS` | `POSTGRES_PASSWORD` | *généré aléatoirement* | Mot de passe PostgreSQL |

> ℹ️ Si `--pg-password` n'est pas fourni, le script génère automatiquement un mot de passe aléatoire de 20 caractères, affiché en fin d'installation.

### Utilisation

```bash
# Cloner ce dépôt sur le reTerminal DM
git clone <URL_DU_REPO>
cd re1000-tbEdge-IoT

# Exécuter avec passage des paramètres en arguments CLI
sudo bash tb_edge_install.sh \
  --routing-key    "votre-routing-key" \
  --routing-secret "votre-routing-secret" \
  --cloud-host     "votre-serveur.exemple.com" \
  --edge-license   "votre-licence-edge"
```

**Alternative — via variables d'environnement :**

```bash
export CLOUD_ROUTING_KEY="votre-routing-key"
export CLOUD_ROUTING_SECRET="votre-routing-secret"
export CLOUD_RPC_HOST="votre-serveur.exemple.com"
export EDGE_LICENSE="votre-licence-edge"
export POSTGRES_PASSWORD="MotDePasseForte123!"   # Optionnel

sudo -E bash tb_edge_install.sh
```

> ⚠️ **Sécurité** : Ne jamais inclure les credentials dans l'historique bash. Préférer les variables d'environnement ou un fichier de configuration chiffré (ex: Ansible Vault).

### Ports exposés

| Port | Protocole | Usage |
|------|-----------|-------|
| `8080` | TCP | Interface web ThingsBoard Edge |
| `1883` | TCP | Broker MQTT |
| `5683–5688` | UDP | CoAP |

### Connexion après installation

- **Interface web** : `http://<IP_DU_MODULE>:8080`
- **Identifiants par défaut** :
  - Login : `sysadmin@thingsboard.org`
  - Mot de passe : `sysadmin`

> ⚠️ **Changer le mot de passe immédiatement** après la première connexion.

### Commandes utiles

```bash
# Voir les logs de TB Edge
docker compose -C /opt/tb-edge logs -f mytbedge

# Voir les logs PostgreSQL
docker compose -C /opt/tb-edge logs -f postgres

# Redémarrer la stack via systemd
systemctl restart tb-edge

# Arrêter la stack
systemctl stop tb-edge

# Vérifier l'état du service
systemctl status tb-edge
```

### Volumes Docker persistants

| Volume | Contenu |
|--------|---------|
| `tb-edge-data` | Données applicatives TB Edge (licence, config) |
| `tb-edge-logs` | Logs applicatifs |
| `tb-edge-postgres-data` | Base de données PostgreSQL |

---

## 2. TB IoT Gateway — `tb_gateway_install.sh`

TB IoT Gateway s'installe en complément de TB Edge sur le même reTerminal DM. Il est déployé en Docker avec `network_mode: host` et `privileged: true` pour accéder aux interfaces hardware (BLE, CAN, ports série).

### Ce que fait le script

1. **Valide les paramètres** — vérifie que l'Access Token est fourni
2. **Vérifie que TB Edge répond** — sonde l'API REST avant de continuer
3. **Crée la structure de répertoires** dans le répertoire d'installation : `config/`, `extensions/`, `logs/`
4. **Génère `tb_gateway.yaml`** — configuration principale avec tous les connecteurs activés
5. **Génère les fichiers JSON** de configuration pour chaque connecteur (exemples commentés)
6. **Génère un exemple de connecteur Python** dans `extensions/custom/`
7. **Crée le `docker-compose.yml`** et pull l'image officielle
8. **Crée un service systemd `tb-gateway`** — démarrage après `tb-edge.service`

### Prérequis

- **TB Edge PE opérationnel** (installé via `tb_edge_install.sh`)
- Un **device de type Gateway** créé dans TB Edge, avec son **Access Token**

> Dans TB Edge : *Entities → Devices → + Add device → cocher "Is gateway"* puis récupérer le token dans *Manage credentials*.

### Paramètres du script

#### Option obligatoire

| Option CLI | Variable d'env | Description |
|-----------|----------------|-------------|
| `--access-token TOKEN` | `TB_GW_ACCESS_TOKEN` | Access Token du device Gateway créé dans TB Edge |

#### Options facultatives

| Option CLI | Variable d'env | Défaut | Description |
|-----------|----------------|--------|-------------|
| `--tb-host HOST` | `TB_HOST` | `localhost` | Hôte de l'instance TB Edge (MQTT) |
| `--tb-port PORT` | `TB_PORT` | `1883` | Port MQTT de TB Edge |
| `--version VERSION` | `TB_GW_VERSION` | `3.9.1` | Tag de l'image Docker TB Gateway |
| `--install-dir PATH` | `INSTALL_DIR` | `/opt/tb-gateway` | Répertoire d'installation |
| `--gw-name NAME` | `GW_NAME` | `TB-Gateway-re1000` | Nom affiché dans TB Edge |

### Utilisation

```bash
# Cas minimal — TB Edge local sur le même appareil
sudo bash tb_gateway_install.sh \
  --access-token "votre-access-token-gateway"

# Avec TB Edge sur un hôte différent
sudo bash tb_gateway_install.sh \
  --access-token "votre-access-token-gateway" \
  --tb-host "192.168.1.100"

# Via variables d'environnement
export TB_GW_ACCESS_TOKEN="votre-access-token-gateway"
sudo -E bash tb_gateway_install.sh
```

### Connecteurs configurés

Tous les connecteurs officiels sont activés et livrés avec un fichier JSON d'exemple à adapter :

| Connecteur | Fichier de config | Usage typique |
|-----------|-------------------|---------------|
| MQTT | `config/mqtt.json` | Broker MQTT local ou externe |
| Modbus TCP | `config/modbus.json` | PLC, compteurs, capteurs industriels |
| OPC-UA | `config/opcua.json` | Automates industriels, SCADA |
| BACnet | `config/bacnet.json` | Systèmes de gestion de bâtiment (GTB) |
| BLE | `config/ble.json` | Capteurs Bluetooth Low Energy |
| Serial RS232/RS485 | `config/serial.json` | Équipements série legacy |
| REST API | `config/rest.json` | Intégration HTTP/HTTPS |
| SNMP | `config/snmp.json` | Équipements réseau, UPS |
| FTP | `config/ftp.json` | Transfert de fichiers de données |
| Socket TCP/UDP | `config/socket.json` | Protocoles propriétaires |
| CAN Bus | `config/can.json` | Systèmes embarqués, véhicules |
| Custom Python | `extensions/custom/` | Connecteurs sur mesure |

Pour activer uniquement certains connecteurs, commenter les entrées correspondantes dans `tb_gateway.yaml`.

### Structure du répertoire d'installation

```
/opt/tb-gateway/
├── docker-compose.yml
├── config/
│   ├── tb_gateway.yaml     ← Configuration principale
│   ├── mqtt.json
│   ├── modbus.json
│   ├── opcua.json
│   ├── bacnet.json
│   ├── ble.json
│   ├── serial.json
│   ├── rest.json
│   ├── snmp.json
│   ├── ftp.json
│   ├── socket.json
│   ├── can.json
│   └── custom.json
├── extensions/
│   └── custom/
│       └── custom_connector.py   ← Exemple de connecteur Python
└── logs/
```

### Commandes utiles

```bash
# Voir les logs du gateway
docker compose -C /opt/tb-gateway logs -f tb-gateway

# Redémarrer après modification d'un fichier de config
systemctl restart tb-gateway

# Arrêter le gateway
systemctl stop tb-gateway

# État du service
systemctl status tb-gateway
```

---

## Architecture de la solution

```
                Internet
                    │
        ┌───────────▼───────────┐
        │  ThingsBoard Server PE │
        │  (votre-serveur.com)   │
        └───────────┬───────────┘
                    │ gRPC :7070
                    │
        ┌───────────▼───────────────────────────┐
        │        reTerminal DM (re1000)          │
        │                                        │
        │  ┌─────────────────────────────────┐  │
        │  │  ThingsBoard Edge PE :8080       │  │
        │  │  + PostgreSQL 16                 │  │
        │  └──────────────┬──────────────────┘  │
        │                 │ MQTT :1883           │
        │  ┌──────────────▼──────────────────┐  │
        │  │  TB IoT Gateway                  │  │
        │  │  (Modbus, OPC-UA, MQTT, BLE...)  │  │
        │  └──────────────┬──────────────────┘  │
        └─────────────────┼──────────────────────┘
                          │
              ┌───────────┴───────────┐
              │    Terrain / Capteurs  │
              │  (PLC, capteurs IoT,   │
              │   compteurs, etc.)     │
              └───────────────────────┘
```

---

## Sécurité

- Les scripts ne stockent **aucun credential en dur** — tous les paramètres sensibles sont passés via les options CLI ou les variables d'environnement
- Le mot de passe PostgreSQL est **généré aléatoirement** si non fourni
- Les credentials sont uniquement écrits dans le `docker-compose.yml` local (hors versionnage)
- Ne jamais committer de fichiers contenant de vraies clés ou mots de passe

---

## Auteur

**EnerGroup** — [energroup.ch](https://energroup.ch)

---

## Licence

Usage interne EnerGroup. Tous droits réservés.
