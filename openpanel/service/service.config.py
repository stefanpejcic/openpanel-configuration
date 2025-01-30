# Gunicorn configuration file
# https://docs.gunicorn.org/en/stable/configure.html#configuration-file
# https://docs.gunicorn.org/en/stable/settings.html

import multiprocessing
import os
import re
import yaml  # pip install pyyaml
from pathlib import Path

# File paths
CADDYFILE_PATH = "/etc/caddy/Caddyfile"
CADDY_CERT_DIR = "/etc/openpanel/caddy/ssl/acme-v02.api.letsencrypt.org-directory/"
DOCKER_COMPOSE_PATH = "/root/docker-compose.yml"


def get_port_from_dockerfile():
    try:
        with open(DOCKER_COMPOSE_PATH, "r") as file:
            compose_data = yaml.safe_load(file)

        services = compose_data.get("services", {})
        openpanel_service = services.get("openpanel", {})
        ports = openpanel_service.get("ports", [])

        for port_mapping in ports:
            if isinstance(port_mapping, str):  # Format: "2083:2083"
                host_port = port_mapping.split(":")[0]
                return int(host_port)

    except Exception as e:
        print(f"Error reading docker-compose.yml: {e}")

    return 2083  # fallback


def get_domain_from_caddyfile():
    domain = None
    in_block = False

    try:
        with open(CADDYFILE_PATH, "r") as file:
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
    except Exception as e:
        print(f"Error reading Caddyfile: {e}")

    return domain


def check_ssl_exists(domain):
    cert_path = os.path.join(CADDY_CERT_DIR, domain)
    # check if cert and key exist
    return os.path.exists(cert_path) and os.listdir(cert_path)


DOMAIN = get_domain_from_caddyfile()
PORT = get_port_from_dockerfile()

if DOMAIN and check_ssl_exists(DOMAIN):
    PROTOCOL = "https"
else:
    PROTOCOL = "http"

bind = [f"{PROTOCOL}://0.0.0.0:{PORT}"]

backlog = 2048
calculated_workers = multiprocessing.cpu_count() * 2 + 1
max_workers = 10
workers = min(calculated_workers, max_workers)
worker_class = 'gevent'
worker_connections = 1000
timeout = 10
graceful_timeout = 10
keepalive = 2
max_requests = 1000
max_requests_jitter = 50
pidfile = 'openpanel'

errorlog = "/var/log/openpanel/user/error.log"
accesslog = "/var/log/openpanel/user/access.log"

def ensure_directory(file_path):
    directory = Path(file_path).parent
    directory.mkdir(parents=True, exist_ok=True)

ensure_directory(errorlog)
ensure_directory(accesslog)

def post_fork(server, worker):
    server.log.info("Worker spawned (pid: %s)", worker.pid)

def pre_fork(server, worker):
    pass

def pre_exec(server):
    server.log.info("Forked child, re-executing.")

def when_ready(server):
    server.log.info("Server is ready. Spawning workers")

def worker_int(worker):
    worker.log.info("worker received INT or QUIT signal")


# Allow specific IP addresses
#config.allow_ip = ['192.168.1.100']
forwarded_allow_ips = '*'  # for cloudflare
