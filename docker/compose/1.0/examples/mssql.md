# MsSQL

To add MsSQL as a service or user in OpenPanel:

add to .env file:

```
# MSSQL
MSSQL_IMAGE="mcr.microsoft.com/mssql/server"
MSSQL_VERSION="latest"
MSSQL_PID="Standard"
MSSQL_PORT="0:1433"
MSSQL_CPU="1.0"
MSSQL_RAM="1.0G"
MSSQL_SA_PASSWORD="rootpassword"
```

add to docker-compose.yml file **in the services section:

```
  mssql:
    image: ${MSSQL_IMAGE}:${MSSQL_VERSION:-latest}
    container_name: mssql
    restart: unless-stopped
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_SA_PASSWORD: ${MSSQL_SA_PASSWORD:-StrongPassword!}
      MSSQL_PID: ${MSSQL_PID:-Developer}  # Options: Developer, Express, Standard, Enterprise
    ports:
      - "${MSSQL_PORT}"
    volumes:
      - mssql_data:/var/opt/mssql                                      # MSSQL data
      - ./sockets/mssql:/var/opt/mssql/sockets          # MSSQL socket
      - ./mssql.conf:/etc/mssql/mssql.conf:ro           # Custom MSSQL config
    deploy:
      resources:
        limits:
          cpus: "${MSSQL_CPU:-1}"
          memory: "${MSSQL_RAM:-2G}"
          pids: 100
    networks:
      - db
    healthcheck:
      test: ['CMD-SHELL', 'sqlcmd -S localhost -U sa -P "$$MSSQL_SA_PASSWORD" -Q "SELECT 1" || exit 1']
      interval: 10s
      timeout: 5s
      retries: 5

```
