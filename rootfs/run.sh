#!/usr/bin/with-contenv bashio

ulimit -n 1048576

hostname=$(bashio::info.hostname)

# Get all possible hostnames from configuration
result=$(bashio::api.supervisor GET /core/api/config true || true)
internal=$(bashio::jq "$result" '.internal_url' | cut -d'/' -f3 | cut -d':' -f1)
external=$(bashio::jq "$result" '.external_url' | cut -d'/' -f3 | cut -d':' -f1)

# Fill config file templates with runtime data
config=$(jq --arg internal "$internal" --arg external "$external" --arg hostname "$hostname" \
    '{internal: $internal, external: $external, hostname: $hostname}' \
    /data/options.json)

echo "$config" | tempio \
    -template /usr/share/cupsd.conf.tempio \
    -out /etc/cups/cupsd.conf

echo "$config" | tempio \
    -template /usr/share/avahi-daemon.conf.tempio \
    -out /etc/avahi/avahi-daemon.conf

echo "$config" | tempio \
    -template /usr/share/sane.conf.tempio \
    -out /etc/sane.d/saned.conf
    
# Start Avahi, wait for it to start up
touch /var/run/avahi_configured
until [ -e /var/run/avahi-daemon/socket ]; do
  sleep 1s
done

bashio::log.info "Init config and directories..."
cp -v -R /etc/cups /data
rm -v -fR /etc/cups
ln -v -s /data/cups /etc/cups
bashio::log.info "Init config and directories completed."

# Initialize SANE and scanning directories
bashio::log.info "Initializing SANE and scanning directories..."
mkdir -p /data/scans
chmod 755 /data/scans

# Initialize SANE configuration
bashio::log.info "Configuring SANE scanner support..."
mkdir -p /data/sane.d
cp -R /etc/sane.d/* /data/sane.d/ 2>/dev/null || true
rm -rf /etc/sane.d
ln -s /data/sane.d /etc/sane.d

# Ensure scanner access permissions
usermod -a -G scanner,lp root 2>/dev/null || true

# Generate scanservjs configuration
echo "$config" | tempio \
    -template /usr/share/scanservjs.config.js.tempio \
    -out /data/scanservjs.config.js

# Check installation debug log
if [ -f /install-debug.log ]; then
    bashio::log.info "=== Installation Debug Info ==="
    while IFS= read -r line; do
        bashio::log.info "$line"
    done < /install-debug.log
    bashio::log.info "=== End Installation Debug ==="
else
    bashio::log.error "No installation debug log found at /install-debug.log - build may have failed!"
fi

# For HA addons, we start services manually (not using S6 to avoid conflicts)
bashio::log.info "Starting services manually for HA addon compatibility..."

# Start DBUS
bashio::log.info "Starting DBUS daemon..."
mkdir -p /var/run/dbus
dbus-daemon --system --nofork &
DBUS_PID=$!

# Wait for DBUS to be ready
sleep 2

# Start Avahi  
bashio::log.info "Starting Avahi daemon..."
avahi-daemon &
AVAHI_PID=$!

# Wait for Avahi to be ready
sleep 2

# Start CUPS
bashio::log.info "Starting CUPS server..."
cupsd &
CUPS_PID=$!

# Wait for CUPS to be ready
until nc -z localhost 631; do
  bashio::log.info "Waiting for CUPS server to be ready..."
  sleep 2
done
bashio::log.info "CUPS server is ready"

# Start scanservjs using the correct Node.js command
bashio::log.info "Starting scanservjs..."
if [ -f /usr/lib/scanservjs/server/server.js ]; then
    # Ensure directories exist
    mkdir -p /data/scans /tmp/scanservjs
    chmod 755 /data/scans /tmp/scanservjs
    
    # Create scanservjs user if it doesn't exist (it should from package install)
    if ! id scanservjs &>/dev/null; then
        useradd -r -s /bin/false -d /var/lib/scanservjs scanservjs
        usermod -a -G scanner,lp scanservjs
    fi
    
    # Set up environment for scanservjs
    export NODE_ENV=production
    export SCANSERVJS_CONFIG_PATH="/data/scanservjs.config.js"
    export SCANSERVJS_OUTPUT_DIR="/data/scans"
    export SCANSERVJS_PREVIEW_DIR="/tmp/scanservjs"
    
    # Start scanservjs as the scanservjs user
    bashio::log.info "Starting scanservjs Node.js application..."
    cd /usr/lib/scanservjs
    su -s /bin/bash scanservjs -c "NODE_ENV=production node server/server.js" &
    SCANSERVJS_PID=$!
    bashio::log.info "scanservjs started with PID: $SCANSERVJS_PID"
    
    # Wait a moment and check if it's running
    sleep 3
    if kill -0 $SCANSERVJS_PID 2>/dev/null; then
        bashio::log.info "✓ scanservjs is running successfully"
    else
        bashio::log.error "✗ scanservjs failed to start"
    fi
else
    bashio::log.error "scanservjs server.js not found at /usr/lib/scanservjs/server/server.js"
fi

# Wait for all services (trap signals to clean shutdown)
trap 'kill $DBUS_PID $AVAHI_PID $CUPS_PID $SCANSERVJS_PID 2>/dev/null; exit' TERM INT

bashio::log.info "All services started. Addon is running."

# Keep the script running
while true; do
    sleep 30
    # Basic health check
    if ! pgrep cupsd > /dev/null; then
        bashio::log.error "CUPS server died, restarting..."
        cupsd &
        CUPS_PID=$!
    fi
    
    # Check scanservjs health
    if [ -n "$SCANSERVJS_PID" ] && ! kill -0 $SCANSERVJS_PID 2>/dev/null; then
        bashio::log.error "scanservjs died, restarting..."
        cd /usr/lib/scanservjs
        su -s /bin/bash scanservjs -c "NODE_ENV=production node server/server.js" &
        SCANSERVJS_PID=$!
        bashio::log.info "scanservjs restarted with PID: $SCANSERVJS_PID"
    fi
done
