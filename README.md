# Pterodactyl Auto Installer

Automated bash installer for [Pterodactyl Panel](https://pterodactyl.io/) + [Wings](https://pterodactyl.io/wings/) on Ubuntu. One script handles the full stack: panel, node, Minecraft eggs, optional test server, phpMyAdmin, and a Pterodactyl database host.

**Tested on:** Ubuntu 22.04 / 24.04 / 26.04 (x86_64)

## What it installs

- Pterodactyl Panel + Wings (via [pterodactyl-installer.se](https://pterodactyl-installer.se))
- Node, Wings config, and port allocations
- Community Minecraft eggs (Fabric, NeoForge, Paper, Bedrock, proxies, and more)
- Optional test Minecraft server
- phpMyAdmin (HTTP auth + MariaDB root login)
- Pterodactyl database host for server databases
- Optional 2 GB swap file

All services share one unified password unless you set `PASSWORD` yourself.

## Requirements

- Fresh Ubuntu 22.04, 24.04, or 26.04 VPS (x86_64)
- Root access (`sudo`)
- At least ~2 GB RAM recommended
- A domain pointed at the server (optional; IP works, but Let's Encrypt needs a domain)
- Open cloud firewall ports after install: **22**, **80**, **443**, **8080**, **2022**, and your game ports (default **25565–25575**)

> **Note:** Do not run this on a server that already has Pterodactyl installed at `/var/www/pterodactyl`. The script will abort if it detects an existing install.

## Quick start

### Option 1 — Download and run

```bash
curl -fsSL https://raw.githubusercontent.com/squiddd666/Pterodactyl-Auto-Installer/main/install-pterodactyl.sh -o install-pterodactyl.sh
sudo bash install-pterodactyl.sh
```

### Option 2 — Clone the repo

```bash
git clone https://github.com/squiddd666/Pterodactyl-Auto-Installer.git
cd Pterodactyl-Auto-Installer
sudo bash install-pterodactyl.sh
```

### Option 3 — Custom settings

Set environment variables before running. Example with a domain and SSL:

```bash
PASSWORD='MySecurePass123' \
FQDN='panel.example.com' \
CONFIGURE_SSL='yes' \
ADMIN_EMAIL='you@example.com' \
ADMIN_USER='admin' \
sudo -E bash install-pterodactyl.sh
```

Use `sudo -E` so your exported variables are passed through to the script.

## Configuration options

| Variable | Default | Description |
|----------|---------|-------------|
| `PASSWORD` | Auto-generated | Unified password for **all** services |
| `FQDN` | Public IP | Domain or IP for the panel and node |
| `ADMIN_EMAIL` | `admin@example.com` | Admin email and Let's Encrypt contact |
| `ADMIN_USER` | `admin` | Panel admin username |
| `TIMEZONE` | `Asia/Singapore` | Panel timezone |
| `CONFIGURE_SSL` | `no` | `yes` / `no` — Let's Encrypt (requires a domain) |
| `CONFIGURE_FIREWALL` | `yes` | `yes` / `no` — UFW rules |
| `INSTALL_MINECRAFT_EGGS` | `yes` | Import community Minecraft eggs |
| `CREATE_TEST_SERVER` | `yes` | Create a test Minecraft server |
| `TEST_SERVER_NAME` | `Test Minecraft` | Name of the test server |
| `TEST_SERVER_EGG` | `Paper` | Egg to use (must exist after import) |
| `TEST_SERVER_MEMORY` | `1024` | Test server RAM (MB) |
| `TEST_SERVER_DISK` | `5120` | Test server disk (MB) |
| `TEST_SERVER_START` | `no` | Auto-start test server after install |
| `INSTALL_PHPMYADMIN` | `yes` | Install phpMyAdmin |
| `SETUP_DATABASE_HOST` | `yes` | Register a database host in the panel |
| `INSTALL_SWAP` | `yes` | Create a 2 GB swap file |
| `NODE_MAX_MEMORY` | `2048` | Node RAM limit (MB) |
| `NODE_MAX_DISK` | `40960` | Node disk limit (MB) |
| `ALLOC_PORT_START` | `25565` | First game port |
| `ALLOC_PORT_END` | `25575` | Last game port |
| `PMA_USER` | `admin` | phpMyAdmin HTTP auth username |
| `DBHOST_USER` | `pterodactyluser` | Database host MariaDB user |
| `CREDENTIALS_FILE` | `/root/pterodactyl-credentials.txt` | Where credentials are saved |

Show built-in help:

```bash
bash install-pterodactyl.sh --help
```

## After installation

When the script finishes, it prints your panel URL, username, and unified password. Full details are saved to:

```
/root/pterodactyl-credentials.txt
```

Typical URLs:

- **Panel:** `http://YOUR_FQDN` or `https://YOUR_FQDN` (if SSL enabled)
- **phpMyAdmin:** `http://YOUR_FQDN/phpmyadmin`

Install log:

```
/var/log/pterodactyl-auto-install.log
```

## Credits

This project is a wrapper and automation layer built on top of excellent community tools:

| Project | Author / Maintainer | Link |
|---------|---------------------|------|
| **Pterodactyl Panel & Wings** | Pterodactyl Software | [pterodactyl.io](https://pterodactyl.io/) |
| **pterodactyl-installer** | Community installer used for panel + Wings setup | [pterodactyl-installer.se](https://pterodactyl-installer.se) |
| **Pelican Eggs** | Minecraft and other game server eggs | [github.com/pelican-eggs/eggs](https://github.com/pelican-eggs/eggs) |
| **phpMyAdmin** | phpMyAdmin team | [phpmyadmin.net](https://www.phpmyadmin.net/) |

**Pterodactyl Auto Installer** — created and maintained by [squiddd666](https://github.com/squiddd666).

## License

This project is licensed under the [MIT License](LICENSE).

Third-party projects installed by this script (Pterodactyl, phpMyAdmin, eggs, etc.) are subject to their own licenses.

## Disclaimer

This script modifies system packages, services, databases, and firewall rules. Use only on a server you own, on a fresh or dedicated install, and review the script before running it in production. The author is not affiliated with Pterodactyl Software.
