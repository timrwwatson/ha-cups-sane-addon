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

# Check if we're running as PID 1
if [ "$$" = "1" ]; then
    bashio::log.info "Running as PID 1, executing S6 init directly"
    exec /init
else
    bashio::log.warning "Not running as PID 1 (current PID: $$), starting S6 in alternative mode"
    # Try starting S6 services directly instead of exec /init
    /init &
    S6_PID=$!
    bashio::log.info "Started S6 with PID: $S6_PID"
    
    # Wait for S6 to complete or handle signals
    trap 'kill $S6_PID; exit' TERM INT
    wait $S6_PID
fi
