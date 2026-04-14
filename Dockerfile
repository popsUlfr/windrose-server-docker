FROM cm2network/steamcmd:latest

USER root

# -------------------------------------------------------------------
# Environment variables (configurable at runtime)
# -------------------------------------------------------------------
ENV WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEPREFIX=/wine-prefix \
    DISPLAY=:99 \
    LANG=en_US.UTF-8 \
    VNC_PORT=5900 \
    WEB_PORT=8080 \
    WINE_URL="https://github.com/Kron4ek/Wine-Builds/releases/download/11.6/wine-11.6-staging-amd64-wow64.tar.xz" \
    APP_ID=4129620 \
    UPDATE_ON_BOOT=true

# -------------------------------------------------------------------
# Install system dependencies (including cabextract for winetricks)
# -------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        xvfb \
        x11vnc \
        x11-utils \
        xauth \
        wget \
        xz-utils \
        supervisor \
        python3 \
        python3-numpy \
        wine \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Install websockify 0.13.0
# -------------------------------------------------------------------
RUN wget -qO- https://github.com/novnc/websockify/archive/refs/tags/v0.13.0.tar.gz | tar xz -C /opt && \
    ln -s /opt/websockify-0.13.0 /opt/websockify

# -------------------------------------------------------------------
# Install noVNC 1.6.0
# -------------------------------------------------------------------
RUN wget -qO- https://github.com/novnc/noVNC/archive/refs/tags/v1.6.0.tar.gz | tar xz -C /opt && \
    ln -s /opt/noVNC-1.6.0 /opt/novnc

# -------------------------------------------------------------------
# Create required directories
# -------------------------------------------------------------------
RUN mkdir -p /windrose /wine /wine-prefix

# -------------------------------------------------------------------
# Supervisor configuration
# -------------------------------------------------------------------
COPY --chown=root:root <<-"EOF" /etc/supervisor/conf.d/windrose.conf
[supervisord]
nodaemon=true
user=root
logfile=/dev/stdout
logfile_maxbytes=0

[program:xvfb]
command=Xvfb :99 -screen 0 1024x768x24
autorestart=false
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:x11vnc]
command=x11vnc -display :99 -forever -nopw -shared -quiet -rfbport %(ENV_VNC_PORT)s
autorestart=false
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
depends_on=xvfb

[program:websockify]
command=/opt/websockify/run --web /opt/novnc %(ENV_WEB_PORT)s localhost:%(ENV_VNC_PORT)s
autorestart=false
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
depends_on=x11vnc

[program:windrose-server]
command=wine WindroseServer.exe -log
directory=/windrose
user=steam
environment=WINEARCH="%(ENV_WINEARCH)s",WINEPREFIX="%(ENV_WINEPREFIX)s",DISPLAY="%(ENV_DISPLAY)s",PATH="/wine/bin:%(ENV_PATH)s",HOME=/home/steam
autorestart=false
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
depends_on=xvfb
stopwaitsecs=30
stopsignal=INT
EOF

# -------------------------------------------------------------------
# Entrypoint script (setup, then launch supervisord)
# -------------------------------------------------------------------
COPY --chown=root:root <<-"EOF" /entrypoint.sh
#!/bin/bash
set -e

# Ensure volumes are owned by steam user
chown -R steam:steam /windrose /wine /wine-prefix

# -------------------------------------------------------------------
# Install or update Wine based on WINE_URL
# -------------------------------------------------------------------
WINE_VERSION_FILE="/wine/.wine_url"

if [[ ! -f "$WINE_VERSION_FILE" ]] || [[ "$(cat $WINE_VERSION_FILE)" != "${WINE_URL}" ]]; then
    echo "Wine URL changed or not installed. Installing/updating Wine from: ${WINE_URL}"
    rm -rf /wine/*
    cd /wine
    wget -q "${WINE_URL}" -O wine.tar.xz
    tar -xf wine.tar.xz --strip-components=1
    rm wine.tar.xz
    echo "${WINE_URL}" > "$WINE_VERSION_FILE"
    chown -R steam:steam /wine
else
    echo "Wine already matches desired version, skipping download."
fi

if [[ "${UPDATE_ON_BOOT,,}" = true ]]; then
    echo "Updating Windrose Dedicated Server (App ID: ${APP_ID})..."
    su - steam -c "/home/steam/steamcmd/steamcmd.sh \
        +@sSteamCmdForcePlatformType windows \
	+@sSteamCmdForcePlatformBitness 64 \
	+force_install_dir /windrose \
	+login anonymous \
	+app_update ${APP_ID} validate \
	+quit"
fi

echo "!! You can access the server console here: http://localhost:${WEB_PORT}/vnc.html"

echo "Starting supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
EOF

RUN chmod +x /entrypoint.sh

# -------------------------------------------------------------------
# Expose the web interface port
# -------------------------------------------------------------------
EXPOSE ${WEB_PORT}

WORKDIR /windrose
CMD ["/entrypoint.sh"]
