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

bashio::log.info "Configuration complete, checking scanservjs availability..."

# Debug scanservjs installation before starting S6
if command -v scanservjs &> /dev/null; then
    bashio::log.info "✓ scanservjs found at: $(which scanservjs)"
else
    bashio::log.warning "scanservjs not found in PATH during setup"
    # List possible locations
    find /usr /opt -name "*scanservjs*" -type f 2>/dev/null | head -5 | while read file; do
        bashio::log.info "Found scanservjs file: $file"
    done
fi

bashio::log.info "Starting S6 services..."

# Debug process information before starting S6
bashio::log.info "Current PID: $$"
bashio::log.info "Running as: $(whoami)"
ps aux | head -5 | while read line; do
    bashio::log.info "Process: $line"
done

# Check installation debug log before starting services
if [ -f /install-debug.log ]; then
    bashio::log.info "=== Installation Debug Info ==="
    while IFS= read -r line; do
        bashio::log.info "$line"
    done < /install-debug.log
    bashio::log.info "=== End Installation Debug ==="
else
    bashio::log.error "No installation debug log found at /install-debug.log - build may have failed!"
fi

# For HA addons, we should start services manually rather than using S6 init
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

# Start scanservjs if available
if command -v scanservjs &> /dev/null; then
    bashio::log.info "Starting scanservjs..."
    mkdir -p /data/scans /tmp/scanservjs
    chmod 755 /data/scans /tmp/scanservjs
    scanservjs --host 0.0.0.0 --port 8080 --output-dir /data/scans --config /data/scanservjs.config.js &
    SCANSERVJS_PID=$!
    bashio::log.info "scanservjs started with PID: $SCANSERVJS_PID"
else
    bashio::log.error "scanservjs not found - installation failed"
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
done
