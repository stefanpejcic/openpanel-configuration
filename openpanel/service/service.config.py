"""
Gunicorn configuration file for OpenPanel.
This file contains settings for the Gunicorn server.
"""

import multiprocessing
import os  # Ensure os is imported
import re
from pathlib import Path  # Ensure Path is imported
import logging  # Add logging module

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# From version 1.1.4, we no longer restart admin/user services on configuration
# changes. Instead, we create a flag file (/root/openadmin_restart_needed) and
# remind the user via the GUI that a restart is needed to apply the changes.
# Here, on restart, we check and remove that flag to ensure it’s cleared.
RESTART_FILE_PATH = '/root/openpanel_restart_needed'  # Ensure this is defined


def check_and_remove_restart_file():
    """Check if the restart-needed flag file exists and remove it."""
    if os.path.exists(RESTART_FILE_PATH):
        try:
            os.remove(RESTART_FILE_PATH)
            logging.info("Restart-needed flag removed: %s", RESTART_FILE_PATH)
        except OSError as error:
            logging.error("Failed to remove %s: %s", RESTART_FILE_PATH, error)


# Call the function before starting the Gunicorn server
check_and_remove_restart_file()


# File paths
CADDYFILE_PATH = "/etc/openpanel/caddy/Caddyfile"
CADDY_CERT_DIR = (
    "/etc/openpanel/caddy/ssl/acme-v02.api.letsencrypt.org-directory/"
)
DOCKER_COMPOSE_PATH = "/root/docker-compose.yml"


def get_domain_from_caddyfile():
    """Extract the domain from the Caddyfile."""
    domain = None
    in_block = False

    if not os.path.exists(CADDYFILE_PATH):
        logging.warning(
            "Caddyfile does not exist at %s. No SSL will be used.",
            CADDYFILE_PATH
        )
        return None

    try:
        with open(CADDYFILE_PATH, "r", encoding="utf-8") as file:
            for line in file:
                line = line.strip()

                if "# START HOSTNAME DOMAIN #" in line:
                    in_block = True
                    continue

                if "# END HOSTNAME DOMAIN #" in line:
                    break

                if in_block:
                    match = re.match(r"^([\w.-]+) \{", line)
                    if match:
                        domain = match.group(1)
                        break
    except OSError as error:
        logging.error("Error reading Caddyfile: %s", error)

    return domain


def check_ssl_exists(domain):
    """Check if SSL certificates exist for the given domain."""
    cert_path = os.path.join(CADDY_CERT_DIR, domain)
    return os.path.isdir(cert_path) and any(os.scandir(cert_path))


DOMAIN = get_domain_from_caddyfile()
PORT = "2083"

if DOMAIN and check_ssl_exists(DOMAIN):
    import ssl
    CERTFILE = os.path.join(CADDY_CERT_DIR, DOMAIN, f'{DOMAIN}.crt')
    KEYFILE = os.path.join(CADDY_CERT_DIR, DOMAIN, f'{DOMAIN}.key')
    SSL_VERSION = 'TLS'
    CERT_REQS = ssl.CERT_NONE
    CIPHERS = 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH'

BIND = [f"0.0.0.0:{PORT}"]
BACKLOG = 2048
CALCULATED_WORKERS = min(multiprocessing.cpu_count() * 2 + 1, 10)
WORKER_CLASS = 'gevent'
WORKER_CONNECTIONS = 1000
TIMEOUT = 10
GRACEFUL_TIMEOUT = 10
KEEPALIVE = 2
MAX_REQUESTS = 1000
MAX_REQUESTS_JITTER = 50
PIDFILE = 'openpanel'

ERRORLOG = "/var/log/openpanel/user/error.log"
ACCESSLOG = "/var/log/openpanel/user/access.log"  # Ensure this is defined


def ensure_directory(file_path):
    """Ensure the directory for the given file path exists."""
    Path(file_path).parent.mkdir(parents=True, exist_ok=True)


ensure_directory(ACCESSLOG)


def post_fork(server, worker):
    """Log a message after a worker is forked."""
    server.log.info("Worker spawned (pid: %s)", worker.pid)


def pre_fork(server):
    """Log a message before forking workers."""
    server.log.info("Pre-forking workers.")


def pre_exec(server):
    """Log a message before executing the server."""
    server.log.info("Forked child, re-executing.")


def when_ready(server):
    """Log a message when the server is ready."""
    server.log.info("Server is ready. Spawning workers")


def worker_int(worker):
    """Log a message when a worker receives an INT or QUIT signal."""
    worker.log.info("Worker received INT or QUIT signal")


FORWARDED_ALLOW_IPS = '*'  # for cloudflare
