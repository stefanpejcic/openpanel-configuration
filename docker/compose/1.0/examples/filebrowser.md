# FileBrowser

To add FileBrowser as a service or user in OpenPanel:

add to .env file:

```
# FILEBROWSER
FILEBROWSER_VERSION="s6"
FILEBROWSER_CPU="0.25"
FILEBROWSER_RAM="0.35"
```

add to docker-compose.yml file **in the services section:

```
  filebrowser:
    image: filebrowser/filebrowser:${FILEBROWSER_VERSION:-s6}
    container_name: filebrowser
    volumes:
      - html_data:/srv
      - ./filebrowser/config/:/config/
      - ./filebrowser/database/:/database/
    environment:
      - PUID=${USER_ID:-0}
      - PGID=${USER_ID:-0}
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: "${FILEBROWSER_CPU:-0.35}"
          memory: "${FILEBROWSER_RAM:-0.35G}"   
          pids: 100
    networks:
      - www
```
