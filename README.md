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

> Voir le script `tb_gateway_install.sh` et sa documentation intégrée pour les détails complets.

TB IoT Gateway s'installe en complément de TB Edge sur le même reTerminal DM. Il est déployé en Docker et se connecte automatiquement à l'instance Edge locale via MQTT.

### Connecteurs inclus dans l'image officielle

| Connecteur | Usage typique |
|-----------|---------------|
| MQTT | Broker MQTT local ou externe |
| OPC-UA | Automates industriels, SCADA |
| Modbus RTU/TCP | PLC, compteurs, capteurs industriels |
| BACnet | Systèmes de gestion de bâtiment (GTB) |
| BLE | Capteurs Bluetooth Low Energy |
| CAN Bus | Systèmes embarqués, véhicules |
| Serial (RS232/RS485) | Équipements série legacy |
| REST API | Intégration HTTP/HTTPS |
| SNMP | Équipements réseau, UPS |
| FTP | Transfert de fichiers de données |
| Socket (TCP/UDP) | Protocoles propriétaires |
| Custom (Python) | Connecteurs sur mesure |

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
