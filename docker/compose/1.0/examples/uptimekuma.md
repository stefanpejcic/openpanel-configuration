# UptimeKuma

To add UtimeKuma as a service or user in OpenPanel:

add to .env file:

```
# UPTIMEKUMA
UPTIMEKUMA_VERSION="1"
UPTIMEKUMA_CPU="0.5"
UPTIMEKUMA_RAM="0.5G"
```

add to docker-compsoe.yml file **in the services section:

```
  uptimekuma:
    image: louislam/uptime-kum:${UPTIMEKUMA_VERSION:-1}
    container_name: uptimekuma
    volumes:
      - ./data:/app/data
      - /hostfs/run/user/${USER_ID}/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: "${UPTIMEKUMA_CPU:-0.35}"
          memory: "${UPTIMEKUMA_RAM:-0.35G}"   
          pids: 100
    networks:
      - www
```
