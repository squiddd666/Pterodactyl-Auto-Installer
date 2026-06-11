#!/usr/bin/env bash
#
# Pterodactyl Panel + Wings — Full Automated Installer
# Tested on: Ubuntu 22.04 / 24.04 / 26.04 (x86_64)
#
# Installs:
#   - Pterodactyl Panel + Wings (via pterodactyl-installer.se)
#   - Node, allocations, Wings config
#   - Community Minecraft eggs (Fabric, NeoForge, Bedrock, etc.)
#   - Optional test Minecraft server
#   - phpMyAdmin (with root login)
#   - Pterodactyl database host (for server databases)
#
# Usage:
#   sudo bash install-pterodactyl.sh
#
# All services share one password (PASSWORD). Override any setting:
#
#   PASSWORD=MySecurePass123 \
#   FQDN=panel.example.com \
#   CONFIGURE_SSL=yes \
#   ADMIN_EMAIL=you@example.com \
#   bash install-pterodactyl.sh
#
# Options:
#   PASSWORD              Unified password for ALL services (auto-generated if unset)
#   FQDN                  Domain or IP (default: public IP)
#   ADMIN_EMAIL           Admin + Let's Encrypt email
#   ADMIN_USER            Panel admin username (default: admin)
#   TIMEZONE              Panel timezone (default: Asia/Singapore)
#   CONFIGURE_SSL         yes|no — Let's Encrypt (requires domain)
#   CONFIGURE_FIREWALL    yes|no — UFW (default: yes)
#   INSTALL_MINECRAFT_EGGS yes|no (default: yes)
#   CREATE_TEST_SERVER    yes|no (default: yes)
#   TEST_SERVER_NAME      Server name (default: Test Minecraft)
#   TEST_SERVER_EGG       Egg name (default: Paper)
#   TEST_SERVER_MEMORY    MB (default: 1024)
#   TEST_SERVER_DISK      MB (default: 5120)
#   TEST_SERVER_START     yes|no — auto-start after install (default: no)
#   INSTALL_PHPMYADMIN    yes|no (default: yes)
#   SETUP_DATABASE_HOST   yes|no (default: yes)
#   INSTALL_SWAP          yes|no — 2 GB swap file (default: yes)
#   NODE_MAX_MEMORY       Node RAM limit MB (default: 2048)
#   NODE_MAX_DISK         Node disk limit MB (default: 40960)
#   ALLOC_PORT_START      First game port (default: 25565)
#   ALLOC_PORT_END        Last game port (default: 25575)
#   DBHOST_USER           Database host user (default: pterodactyluser)
#   CREDENTIALS_FILE      Output path (default: /root/pterodactyl-credentials.txt)

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

FQDN="${FQDN:-$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_USER="${ADMIN_USER:-admin}"
PASSWORD="${PASSWORD:-${ADMIN_PASS:-$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)}}"
ADMIN_PASS="${PASSWORD}"
ADMIN_FIRST="${ADMIN_FIRST:-Admin}"
ADMIN_LAST="${ADMIN_LAST:-User}"
TIMEZONE="${TIMEZONE:-Asia/Singapore}"
CONFIGURE_SSL="${CONFIGURE_SSL:-no}"
CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-yes}"
INSTALL_MINECRAFT_EGGS="${INSTALL_MINECRAFT_EGGS:-yes}"
CREATE_TEST_SERVER="${CREATE_TEST_SERVER:-yes}"
TEST_SERVER_NAME="${TEST_SERVER_NAME:-Test Minecraft}"
TEST_SERVER_EGG="${TEST_SERVER_EGG:-Paper}"
TEST_SERVER_MEMORY="${TEST_SERVER_MEMORY:-1024}"
TEST_SERVER_DISK="${TEST_SERVER_DISK:-5120}"
TEST_SERVER_START="${TEST_SERVER_START:-no}"
INSTALL_PHPMYADMIN="${INSTALL_PHPMYADMIN:-yes}"
SETUP_DATABASE_HOST="${SETUP_DATABASE_HOST:-yes}"
INSTALL_SWAP="${INSTALL_SWAP:-yes}"
SWAP_SIZE="${SWAP_SIZE:-2G}"
DBHOST_USER="${DBHOST_USER:-pterodactyluser}"
NODE_NAME="${NODE_NAME:-Main Node}"
NODE_LOCATION_SHORT="${NODE_LOCATION_SHORT:-node1}"
NODE_LOCATION_LONG="${NODE_LOCATION_LONG:-Primary Node}"
NODE_MAX_MEMORY="${NODE_MAX_MEMORY:-2048}"
NODE_MAX_DISK="${NODE_MAX_DISK:-40960}"
ALLOC_PORT_START="${ALLOC_PORT_START:-25565}"
ALLOC_PORT_END="${ALLOC_PORT_END:-25575}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-/root/pterodactyl-credentials.txt}"
INSTALLER_URL="${INSTALLER_URL:-https://pterodactyl-installer.se}"
LOG_FILE="${LOG_FILE:-/var/log/pterodactyl-auto-install.log}"

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
die()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0"
}

is_ip() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

mariadb_root() {
    # Use socket auth before passwords are set; password auth after.
    if mariadb -u root -e "SELECT 1" &>/dev/null; then
        mariadb -u root "$@"
    else
        mariadb -u root -p"${PASSWORD}" "$@"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight
# ─────────────────────────────────────────────────────────────────────────────

require_root

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

if [[ -d /var/www/pterodactyl ]]; then
    die "Pterodactyl already installed at /var/www/pterodactyl. Aborting."
fi

# Leftover MariaDB data survives apt purge and breaks password sync on reinstall.
if [[ -d /var/lib/mariadb ]] && [[ -n "$(ls -A /var/lib/mariadb 2>/dev/null)" ]]; then
    reset_mariadb=0
    if ! mariadb -u root -e "SELECT 1" &>/dev/null; then
        reset_mariadb=1
    elif mariadb -u root -Nse "SHOW DATABASES LIKE 'panel'" 2>/dev/null | grep -qx panel; then
        reset_mariadb=1
    fi
    if [[ "$reset_mariadb" -eq 1 ]]; then
        warn "Removing stale MariaDB data from a previous install."
        systemctl stop mariadb 2>/dev/null || true
        rm -rf /var/lib/mariadb
        if dpkg -l mariadb-server &>/dev/null; then
            mkdir -p /var/lib/mariadb
            chown mysql:mysql /var/lib/mariadb
            sudo -u mysql mariadb-install-db --datadir=/var/lib/mariadb --auth-root-authentication-method=socket
            systemctl start mariadb
        fi
    fi
fi

if ! command -v curl &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq curl ca-certificates
fi

if is_ip "$FQDN" && [[ "$CONFIGURE_SSL" == "yes" ]]; then
    warn "Let's Encrypt requires a domain. Disabling SSL."
    CONFIGURE_SSL="no"
fi

log "FQDN / IP:        $FQDN"
log "Unified password: $PASSWORD"
log "Admin user:       $ADMIN_USER"
log "Timezone:         $TIMEZONE"
log "Firewall:         $CONFIGURE_FIREWALL | SSL: $CONFIGURE_SSL"
log "Minecraft eggs:   $INSTALL_MINECRAFT_EGGS | Test server: $CREATE_TEST_SERVER"
log "phpMyAdmin:       $INSTALL_PHPMYADMIN | DB host: $SETUP_DATABASE_HOST | Swap: $INSTALL_SWAP"
log "Credentials:      $CREDENTIALS_FILE"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Panel + Wings (community installer)
# ─────────────────────────────────────────────────────────────────────────────

run_installer() {
    log "Running pterodactyl-installer (panel + wings)..."

    local firewall_ans="n" ssl_ans="n"
    [[ "$CONFIGURE_FIREWALL" == "yes" ]] && firewall_ans="y"
    [[ "$CONFIGURE_SSL" == "yes" ]] && ssl_ans="y"

    {
        echo "2"                 # Panel + Wings
        echo ""                  # DB name → panel
        echo ""                  # DB user → pterodactyl
        echo "$PASSWORD"         # DB password (unified)
        echo "$TIMEZONE"
        echo "$ADMIN_EMAIL"
        echo "$ADMIN_EMAIL"
        echo "$ADMIN_USER"
        echo "$ADMIN_FIRST"
        echo "$ADMIN_LAST"
        echo "$PASSWORD"         # Admin password (unified)
        echo "$FQDN"
        echo "$firewall_ans"
        echo ""                  # Telemetry → yes
        echo "y"                 # Confirm panel
        echo "y"                 # Proceed to wings
        echo "$firewall_ans"
        echo "n"                 # Wings DB host user (we configure ourselves)
        echo "$ssl_ans"
        echo "$FQDN"             # FQDN prompt (shown even when SSL is disabled)
        echo "y"                 # Confirm wings
    } | bash <(curl -sSL "$INSTALLER_URL") 2>&1 | tee -a "$LOG_FILE"

    [[ -d /var/www/pterodactyl ]] || die "Panel install failed. See $LOG_FILE"
    ok "Panel and Wings installed."
}

sync_panel_env() {
    log "Syncing panel .env with installer settings..."

    local env="/var/www/pterodactyl/.env"
    [[ -f "$env" ]] || die "Panel .env not found."

    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=\"${PASSWORD}\"|" "$env"
    sed -i "s|^APP_URL=.*|APP_URL=\"http://${FQDN}\"|" "$env"
    [[ "$CONFIGURE_SSL" == "yes" ]] && sed -i "s|^APP_URL=.*|APP_URL=\"https://${FQDN}\"|" "$env"

    cd /var/www/pterodactyl
    grep -q '^APP_KEY=.\+' "$env" || php artisan key:generate --force
    ok "Panel .env synced."
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Node, Wings config, allocations
# ─────────────────────────────────────────────────────────────────────────────

setup_node() {
    log "Creating location, node, and allocations..."

    cd /var/www/pterodactyl

    local scheme="http"
    [[ "$CONFIGURE_SSL" == "yes" ]] && scheme="https"

    php artisan p:location:make \
        --short="$NODE_LOCATION_SHORT" \
        --long="$NODE_LOCATION_LONG" \
        --no-interaction

    php artisan p:node:make \
        --name="$NODE_NAME" \
        --description="Auto-configured node" \
        --locationId=1 \
        --fqdn="$FQDN" \
        --public=1 \
        --scheme="$scheme" \
        --proxy=0 \
        --maintenance=0 \
        --maxMemory="$NODE_MAX_MEMORY" \
        --overallocateMemory=0 \
        --maxDisk="$NODE_MAX_DISK" \
        --overallocateDisk=0 \
        --uploadSize=100 \
        --daemonListeningPort=8080 \
        --daemonSFTPPort=2022 \
        --daemonBase=/var/lib/pterodactyl/volumes \
        --no-interaction

    mkdir -p /etc/pterodactyl /var/lib/pterodactyl/volumes
    php artisan p:node:configuration 1 --format=yaml > /etc/pterodactyl/config.yml
    chmod 600 /etc/pterodactyl/config.yml

    # Bind 0.0.0.0 so Docker listens on all interfaces (required on GCP/AWS
    # where the public IP is NAT'd and not assigned to a local interface).
    php artisan tinker --execute="
        for (\$port = ${ALLOC_PORT_START}; \$port <= ${ALLOC_PORT_END}; \$port++) {
            \Pterodactyl\Models\Allocation::create([
                'node_id' => 1,
                'ip' => '0.0.0.0',
                'ip_alias' => '${FQDN}',
                'port' => \$port,
            ]);
        }
        echo \Pterodactyl\Models\Allocation::where('node_id', 1)->count() . ' allocations';
    "

    systemctl enable wings
    systemctl restart wings
    sleep 2
    systemctl is-active --quiet wings || die "Wings failed to start. Run: journalctl -u wings -e"
    ok "Node ready. Ports ${ALLOC_PORT_START}-${ALLOC_PORT_END}."
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Minecraft eggs
# ─────────────────────────────────────────────────────────────────────────────

import_minecraft_eggs() {
    [[ "$INSTALL_MINECRAFT_EGGS" == "yes" ]] || { log "Skipping Minecraft eggs."; return; }

    log "Importing community Minecraft eggs..."

    local egg_dir="/tmp/minecraft-eggs"
    local base="https://raw.githubusercontent.com/pelican-eggs/eggs/master"
    mkdir -p "$egg_dir"

    declare -A EGGS=(
        [fabric]="game_eggs/minecraft/java/fabric/egg-fabric.json"
        [neoforge]="game_eggs/minecraft/java/neoforge/egg-neo-forge.json"
        [purpur]="game_eggs/minecraft/java/purpur/egg-purpur.json"
        [spigot]="game_eggs/minecraft/java/spigot/egg-spigot.json"
        [folia]="game_eggs/minecraft/java/folia/egg-folia.json"
        [quilt]="game_eggs/minecraft/java/quilt/egg-quilt.json"
        [modrinth]="game_eggs/minecraft/java/modrinth/egg-modrinth-generic.json"
        [curseforge]="game_eggs/minecraft/java/curseforge/egg-curse-forge-generic.json"
        [bedrock]="game_eggs/minecraft/bedrock/bedrock/egg-vanilla-bedrock.json"
        [velocity]="game_eggs/minecraft/proxy/java/velocity/egg-velocity.json"
        [waterfall]="game_eggs/minecraft/proxy/java/waterfall/egg-waterfall.json"
        [pocketmine]="game_eggs/minecraft/bedrock/pocketmine_mp/egg-pocketmine-m-p.json"
        [nukkit]="game_eggs/minecraft/bedrock/nukkit/egg-nukkit.json"
    )

    for name in "${!EGGS[@]}"; do
        curl -fsSL -o "${egg_dir}/${name}.json" "${base}/${EGGS[$name]}"
    done

    cat > /tmp/import-minecraft-eggs.php <<'PHP'
<?php
require '/var/www/pterodactyl/vendor/autoload.php';
$app = require_once '/var/www/pterodactyl/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Http\UploadedFile;
use Pterodactyl\Models\Egg;
use Pterodactyl\Models\Nest;
use Pterodactyl\Services\Eggs\Sharing\EggImporterService;
use Pterodactyl\Services\Eggs\Sharing\EggUpdateImporterService;

$nest = Nest::query()->with('eggs')->findOrFail(1);
$importer = app(EggImporterService::class);
$updater = app(EggUpdateImporterService::class);
$created = $updated = 0;

foreach (glob('/tmp/minecraft-eggs/*.json') as $path) {
    $decoded = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
    $file = new UploadedFile($path, basename($path), 'application/json', null, true);
    $existing = $nest->eggs()->where('author', $decoded['author'] ?? '')->where('name', $decoded['name'] ?? '')->first();
    if ($existing instanceof Egg) { $updater->handle($existing, $file); $updated++; }
    else { $importer->handle($file, 1); $created++; }
}
echo "Imported: {$created} new, {$updated} updated\n";
PHP

    php /tmp/import-minecraft-eggs.php
    rm -rf "$egg_dir" /tmp/import-minecraft-eggs.php
    ok "Minecraft eggs imported."
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Test Minecraft server
# ─────────────────────────────────────────────────────────────────────────────

create_test_server() {
    [[ "$CREATE_TEST_SERVER" == "yes" ]] || { log "Skipping test server."; return; }

    log "Creating test server: ${TEST_SERVER_NAME} (${TEST_SERVER_EGG})..."

    local start_flag="false" db_limit=1
    [[ "$TEST_SERVER_START" == "yes" ]] && start_flag="true"
    [[ "$SETUP_DATABASE_HOST" != "yes" ]] && db_limit=0

    cat > /tmp/create-test-server.php <<PHP
<?php
require '/var/www/pterodactyl/vendor/autoload.php';
\$app = require_once '/var/www/pterodactyl/bootstrap/app.php';
\$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Pterodactyl\Models\Allocation;
use Pterodactyl\Models\Egg;
use Pterodactyl\Models\User;
use Pterodactyl\Services\Servers\ServerCreationService;

\$egg = Egg::where('name', getenv('TEST_SERVER_EGG') ?: 'Paper')->first()
    or die("Egg not found\n");
\$user = User::where('username', getenv('ADMIN_USER') ?: 'admin')->first()
    or die("Admin not found\n");
\$alloc = Allocation::where('node_id', 1)->whereNull('server_id')->orderBy('port')->first()
    or die("No free allocation\n");

\$env = [];
foreach (\$egg->variables as \$v) { \$env[\$v->env_variable] = \$v->default_value; }
\$mcVersion = getenv('TEST_SERVER_MINECRAFT_VERSION') ?: '1.21.4';
\$env['MINECRAFT_VERSION'] = \$mcVersion;
\$env['BUILD_NUMBER'] = 'latest';
\$images = \$egg->docker_images;
\$image = \$images['Java 21'] ?? \$images['Java 17'] ?? array_values(\$images)[0];

\$server = app(ServerCreationService::class)->handle([
    'name' => getenv('TEST_SERVER_NAME') ?: 'Test Minecraft',
    'description' => 'Auto-created test server',
    'owner_id' => \$user->id, 'node_id' => 1, 'allocation_id' => \$alloc->id,
    'nest_id' => \$egg->nest_id, 'egg_id' => \$egg->id,
    'startup' => \$egg->startup, 'image' => \$image, 'environment' => \$env,
    'memory' => (int) (getenv('TEST_SERVER_MEMORY') ?: 1024),
    'swap' => 0, 'disk' => (int) (getenv('TEST_SERVER_DISK') ?: 5120),
    'io' => 500, 'cpu' => 100, 'threads' => null,
    'database_limit' => (int) (getenv('TEST_SERVER_DB_LIMIT') ?: 0),
    'allocation_limit' => 0, 'backup_limit' => 0,
    'start_on_completion' => filter_var(getenv('TEST_SERVER_START_FLAG') ?: 'false', FILTER_VALIDATE_BOOLEAN),
]);

\$fqdn = getenv('FQDN') ?: '127.0.0.1';
file_put_contents('/tmp/test-server-info.env', implode("\n", [
    'TEST_SERVER_UUID=' . \$server->uuidShort,
    'TEST_SERVER_PORT=' . \$alloc->port,
    'TEST_SERVER_EGG_NAME=' . \$egg->name,
    'TEST_SERVER_ADDRESS=' . \$fqdn . ':' . \$alloc->port,
    'TEST_SERVER_STATUS=' . \$server->status,
]));
echo "Created {\$server->name} on port {\$alloc->port}\n";
PHP

    TEST_SERVER_EGG="$TEST_SERVER_EGG" TEST_SERVER_NAME="$TEST_SERVER_NAME" \
    ADMIN_USER="$ADMIN_USER" TEST_SERVER_MEMORY="$TEST_SERVER_MEMORY" \
    TEST_SERVER_DISK="$TEST_SERVER_DISK" TEST_SERVER_START_FLAG="$start_flag" \
    TEST_SERVER_DB_LIMIT="$db_limit" FQDN="$FQDN" \
    php /tmp/create-test-server.php
    rm -f /tmp/create-test-server.php
    ok "Test server created."
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Unified MariaDB passwords (must run before DB host + phpMyAdmin)
# ─────────────────────────────────────────────────────────────────────────────

setup_mariadb_users() {
    [[ "$INSTALL_PHPMYADMIN" == "yes" || "$SETUP_DATABASE_HOST" == "yes" ]] || return 0

    log "Setting unified MariaDB passwords..."

    mariadb_root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${PASSWORD}';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${PASSWORD}';
CREATE USER IF NOT EXISTS 'pterodactyl'@'localhost' IDENTIFIED BY '${PASSWORD}';
ALTER USER 'pterodactyl'@'localhost' IDENTIFIED BY '${PASSWORD}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'localhost';
CREATE USER IF NOT EXISTS '${DBHOST_USER}'@'127.0.0.1' IDENTIFIED BY '${PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${DBHOST_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=\"${PASSWORD}\"|" /var/www/pterodactyl/.env
    ok "MariaDB users configured (root, pterodactyl, ${DBHOST_USER})."
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Pterodactyl database host
# ─────────────────────────────────────────────────────────────────────────────

setup_database_host() {
    [[ "$SETUP_DATABASE_HOST" == "yes" ]] || { log "Skipping database host."; return; }

    log "Registering database host in Pterodactyl..."

    cat > /tmp/create-database-host.php <<'PHP'
<?php
require '/var/www/pterodactyl/vendor/autoload.php';
$app = require_once '/var/www/pterodactyl/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Pterodactyl\Models\DatabaseHost;
use Pterodactyl\Services\Databases\Hosts\HostCreationService;
use Pterodactyl\Services\Databases\Hosts\HostUpdateService;

$user = getenv('DBHOST_USER') ?: 'pterodactyluser';
$pass = getenv('PASSWORD') ?: '';
$host = getenv('DBHOST_HOST') ?: '127.0.0.1';

$existing = DatabaseHost::where('host', $host)->where('username', $user)->first();
if ($existing) {
    app(HostUpdateService::class)->handle($existing->id, [
        'name' => 'Local MariaDB', 'host' => $host, 'port' => 3306,
        'username' => $user, 'password' => $pass, 'node_id' => 1,
    ]);
    echo "updated id={$existing->id}\n";
} else {
    $db = app(HostCreationService::class)->handle([
        'name' => 'Local MariaDB', 'host' => $host, 'port' => 3306,
        'username' => $user, 'password' => $pass, 'node_id' => 1,
    ]);
    echo "created id={$db->id}\n";
}
PHP

    PASSWORD="$PASSWORD" DBHOST_USER="$DBHOST_USER" DBHOST_HOST="127.0.0.1" \
        php /tmp/create-database-host.php
    rm -f /tmp/create-database-host.php
    ok "Database host registered (Admin → Database Hosts)."
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: phpMyAdmin
# ─────────────────────────────────────────────────────────────────────────────

setup_phpmyadmin() {
    [[ "$INSTALL_PHPMYADMIN" == "yes" ]] || { log "Skipping phpMyAdmin."; return; }

    log "Installing phpMyAdmin..."

    export DEBIAN_FRONTEND=noninteractive
    debconf-set-selections <<'EOF'
phpmyadmin phpmyadmin/dbconfig-install boolean false
phpmyadmin phpmyadmin/reconfigure-webserver multiselect
EOF

    apt-get install -y -qq --no-install-recommends phpmyadmin php-mbstring php-zip php-gd

    # phpMyAdmin is served by nginx + PHP-FPM; Apache conflicts on port 80.
    if dpkg -l apache2 &>/dev/null; then
        systemctl disable --now apache2 2>/dev/null || true
        apt-get remove -y -qq apache2 libapache2-mod-php8.5 libapache2-mod-php8.4 libapache2-mod-php8.3 2>/dev/null || true
    fi

    local php_fpm_sock blowfish
    php_fpm_sock=$(find /run/php -name 'php*-fpm.sock' 2>/dev/null | sort -V | tail -1)
    [[ -n "$php_fpm_sock" ]] || die "PHP-FPM socket not found"
    blowfish=$(openssl rand -base64 32)

    grep -q "blowfish_secret" /etc/phpmyadmin/config.inc.php 2>/dev/null && \
        sed -i "s/\$cfg\['blowfish_secret'\] = '.*';/\$cfg['blowfish_secret'] = '${blowfish}';/" /etc/phpmyadmin/config.inc.php || true

    cat > /etc/phpmyadmin/conf.d/pterodactyl-local.php <<'PHP'
<?php
$i = 1;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = 'localhost';
$cfg['Servers'][$i]['connect_type'] = 'socket';
$cfg['Servers'][$i]['socket'] = '/run/mysqld/mysqld.sock';
$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['AllowNoPassword'] = false;
$cfg['Servers'][$i]['AllowRoot'] = true;
PHP

    rm -f /etc/nginx/.phpmyadmin

    cat > /etc/nginx/snippets/phpmyadmin.conf <<NGINX
location ^~ /phpmyadmin {
    root /usr/share/;
    index index.php index.html;

    location ~ ^/phpmyadmin/(.+\.php)$ {
        root /usr/share/;
        fastcgi_pass unix:${php_fpm_sock};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
        root /usr/share/;
    }
}
NGINX

    local nginx_conf="/etc/nginx/sites-enabled/pterodactyl.conf"
    if [[ -f "$nginx_conf" ]] && ! grep -q 'snippets/phpmyadmin.conf' "$nginx_conf"; then
        sed -i '/charset utf-8;/a\    include snippets/phpmyadmin.conf;' "$nginx_conf"
    fi

    nginx -t && systemctl reload nginx
    ok "phpMyAdmin: http://${FQDN}/phpmyadmin"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: Swap (recommended for Docker)
# ─────────────────────────────────────────────────────────────────────────────

setup_swap() {
    [[ "$INSTALL_SWAP" == "yes" ]] || return 0
    [[ -f /swapfile ]] && { log "Swap already exists."; return; }

    log "Creating ${SWAP_SIZE} swap file..."
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "Swap enabled (${SWAP_SIZE})."
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 9: Save credentials
# ─────────────────────────────────────────────────────────────────────────────

save_credentials() {
    log "Saving credentials to $CREDENTIALS_FILE..."

    local scheme="http"
    [[ "$CONFIGURE_SSL" == "yes" ]] && scheme="https"

    cat > "$CREDENTIALS_FILE" <<EOF
Pterodactyl Installation Credentials
===================================
Generated: $(date -Iseconds)

Unified Password: ${PASSWORD}
(Used for ALL services below)

Panel URL:     ${scheme}://${FQDN}
Admin User:    ${ADMIN_USER}
Admin Pass:    ${PASSWORD}

Panel Database
--------------
Database:      panel
DB User:       pterodactyl
DB Pass:       ${PASSWORD}

Node:          ${NODE_NAME} (ID 1)
Node FQDN:     ${FQDN}
Wings Port:    8080 | SFTP: 2022
Allocations:   ${FQDN}:${ALLOC_PORT_START}-${ALLOC_PORT_END}

Services:
  nginx: $(systemctl is-active nginx)  mariadb: $(systemctl is-active mariadb)
  redis: $(systemctl is-active redis-server)  pteroq: $(systemctl is-active pteroq)
  wings: $(systemctl is-active wings)  docker: $(systemctl is-active docker)

UFW: 22, 80, 443, 8080, 2022
Log: ${LOG_FILE}
EOF

    if [[ "$INSTALL_PHPMYADMIN" == "yes" ]]; then
        cat >> "$CREDENTIALS_FILE" <<EOF

phpMyAdmin: ${scheme}://${FQDN}/phpmyadmin
  MariaDB:    root / ${PASSWORD}
EOF
    fi

    if [[ "$SETUP_DATABASE_HOST" == "yes" ]]; then
        cat >> "$CREDENTIALS_FILE" <<EOF

Database Host (server databases)
  Name:       Local MariaDB
  Host:       127.0.0.1:3306
  User:       ${DBHOST_USER}
  Pass:       ${PASSWORD}
EOF
    fi

    if [[ -f /tmp/test-server-info.env ]]; then
        # shellcheck disable=SC1091
        source /tmp/test-server-info.env
        cat >> "$CREDENTIALS_FILE" <<EOF

Test Minecraft Server
  Name:       ${TEST_SERVER_NAME}
  Egg:        ${TEST_SERVER_EGG_NAME}
  Address:    ${TEST_SERVER_ADDRESS}
  UUID:       ${TEST_SERVER_UUID}
  Status:     ${TEST_SERVER_STATUS}
EOF
        rm -f /tmp/test-server-info.env
    fi

    chmod 600 "$CREDENTIALS_FILE"
    ok "Credentials saved."
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo "============================================================"
    echo " Pterodactyl Automated Installer"
    echo "============================================================"
    echo

    run_installer
    sync_panel_env
    setup_mariadb_users
    setup_node
    import_minecraft_eggs
    create_test_server
    setup_database_host
    setup_phpmyadmin
    setup_swap
    save_credentials

    local scheme="http"
    [[ "$CONFIGURE_SSL" == "yes" ]] && scheme="https"

    echo
    echo "============================================================"
    echo " Installation complete!"
    echo "============================================================"
    echo
    echo "  Password (all services): ${PASSWORD}"
    echo
    echo "  Panel:      ${scheme}://${FQDN}"
    echo "  User:       ${ADMIN_USER}"
    echo

    [[ "$INSTALL_PHPMYADMIN" == "yes" ]] && \
        echo "  phpMyAdmin: ${scheme}://${FQDN}/phpmyadmin"

    [[ "$CREATE_TEST_SERVER" == "yes" && -f "$CREDENTIALS_FILE" ]] && {
        local addr
        addr=$(grep '^  Address:' "$CREDENTIALS_FILE" | awk '{print $2}')
        [[ -n "$addr" ]] && echo "  Test MC:    ${addr}"
    }

    echo
    echo "  Details:    ${CREDENTIALS_FILE}"
    echo
    echo "  Next: Open cloud firewall for 80, 8080, 2022, ${ALLOC_PORT_START}+"
    echo
}

main "$@"
