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

bashio::log.info "Init config and directories..."
cp -v -R /etc/cups /data
rm -v -fR /etc/cups
ln -v -s /data/cups /etc/cups

# Clean up persistent state that might interfere with network discovery
bashio::log.info "Cleaning up persistent state for fresh network discovery..."
rm -f /data/cups/cache/* 2>/dev/null || true
rm -f /data/cups/remote.cache 2>/dev/null || true
rm -f /data/cups/subscriptions.conf.O 2>/dev/null || true
rm -f /data/cups/printers.conf.O 2>/dev/null || true
# Reset any stale browse information
rm -f /data/cups/browse.conf 2>/dev/null || true

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

# Clear network cache and prepare for fresh service advertisement
bashio::log.info "Clearing network cache for fresh service discovery..."
rm -f /var/run/avahi-daemon/pid 2>/dev/null || true
rm -f /var/run/avahi-daemon/socket 2>/dev/null || true
rm -f /run/dbus/pid 2>/dev/null || true
rm -f /var/run/dbus/pid 2>/dev/null || true
rm -f /data/cups/cache/* 2>/dev/null || true
rm -f /data/cups/remote.cache 2>/dev/null || true

# For HA addons, we start services manually (not using S6 to avoid conflicts)
bashio::log.info "Starting services manually for HA addon compatibility..."

# Start DBUS
bashio::log.info "Starting DBUS daemon..."
mkdir -p /var/run/dbus /run/dbus
# Ensure clean DBUS environment
rm -f /run/dbus/pid /var/run/dbus/pid 2>/dev/null || true
dbus-daemon --system --nofork &
DBUS_PID=$!

# Wait for DBUS to be ready
bashio::log.info "Waiting for DBUS to be ready..."
until dbus-send --system --dest=org.freedesktop.DBus --type=method_call --print-reply /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1; do
    sleep 1
done
bashio::log.info "DBUS is ready"

# Start Avahi  
bashio::log.info "Starting Avahi daemon..."
avahi-daemon &
AVAHI_PID=$!

# Wait for Avahi to be ready and fully advertising
bashio::log.info "Waiting for Avahi to be ready..."
AVAHI_TIMEOUT=30
AVAHI_COUNTER=0
until [ -e /var/run/avahi-daemon/socket ]; do
    sleep 1
    AVAHI_COUNTER=$((AVAHI_COUNTER + 1))
    if [ $AVAHI_COUNTER -ge $AVAHI_TIMEOUT ]; then
        bashio::log.error "Avahi socket not ready after $AVAHI_TIMEOUT seconds"
        break
    fi
done

if [ -e /var/run/avahi-daemon/socket ]; then
    bashio::log.info "Avahi socket is ready"
    
    # Test avahi-resolve with timeout
    bashio::log.info "Testing Avahi resolution..."
    if timeout 10 avahi-resolve --name localhost.local >/dev/null 2>&1; then
        bashio::log.info "✓ Avahi resolution test successful"
    else
        bashio::log.warning "⚠ Avahi resolution test failed, but continuing..."
    fi
    
    bashio::log.info "Avahi is ready and advertising"
else
    bashio::log.error "Avahi socket not available, continuing anyway..."
fi

# Start CUPS
bashio::log.info "Starting CUPS server..."
cupsd &
CUPS_PID=$!

# Wait for CUPS to be ready
bashio::log.info "Waiting for CUPS server to be ready..."
CUPS_TIMEOUT=30
CUPS_COUNTER=0
until nc -z localhost 631; do
  bashio::log.info "Waiting for CUPS server to be ready..."
  sleep 2
  CUPS_COUNTER=$((CUPS_COUNTER + 1))
  if [ $CUPS_COUNTER -ge $CUPS_TIMEOUT ]; then
    bashio::log.error "CUPS server not ready after $((CUPS_TIMEOUT * 2)) seconds"
    break
  fi
done

if nc -z localhost 631; then
  bashio::log.info "✓ CUPS server is ready"
else
  bashio::log.error "✗ CUPS server failed to start properly"
fi

# Start scanservjs using the correct Node.js command
bashio::log.info "Starting scanservjs..."

# Debug scanservjs installation
bashio::log.info "Checking scanservjs installation..."
if [ -f /usr/lib/scanservjs/server/server.js ]; then
    bashio::log.info "✓ scanservjs server.js found at /usr/lib/scanservjs/server/server.js"
    bashio::log.info "File permissions: $(ls -la /usr/lib/scanservjs/server/server.js)"
else
    bashio::log.error "✗ scanservjs server.js not found at /usr/lib/scanservjs/server/server.js"
    bashio::log.info "Looking for scanservjs files in other locations..."
    find /usr -name "*scanservjs*" -type f 2>/dev/null | head -10 | while read line; do
        bashio::log.info "Found: $line"
    done
fi

# Check Node.js installation
bashio::log.info "Node.js version: $(node --version 2>/dev/null || echo 'Node.js not found')"
bashio::log.info "NPM version: $(npm --version 2>/dev/null || echo 'NPM not found')"

if [ -f /usr/lib/scanservjs/server/server.js ]; then
    # Ensure directories exist
    mkdir -p /data/scans /tmp/scanservjs
    chmod 755 /data/scans /tmp/scanservjs
    
    # Create scanservjs user if it doesn't exist (it should from package install)
    if ! id scanservjs &>/dev/null; then
        bashio::log.info "Creating scanservjs user..."
        useradd -r -s /bin/false -d /var/lib/scanservjs scanservjs
        usermod -a -G scanner,lp scanservjs
    else
        bashio::log.info "✓ scanservjs user already exists"
    fi
    
    # Set up environment for scanservjs
    export NODE_ENV=production
    export SCANSERVJS_CONFIG_PATH="/data/scanservjs.config.js"
    export SCANSERVJS_OUTPUT_DIR="/data/scans"
    export SCANSERVJS_PREVIEW_DIR="/tmp/scanservjs"
    
    # Debug environment
    bashio::log.info "Environment variables:"
    bashio::log.info "NODE_ENV=$NODE_ENV"
    bashio::log.info "SCANSERVJS_CONFIG_PATH=$SCANSERVJS_CONFIG_PATH"
    bashio::log.info "SCANSERVJS_OUTPUT_DIR=$SCANSERVJS_OUTPUT_DIR"
    bashio::log.info "SCANSERVJS_PREVIEW_DIR=$SCANSERVJS_PREVIEW_DIR"
    
    # Check config file
    if [ -f "$SCANSERVJS_CONFIG_PATH" ]; then
        bashio::log.info "✓ scanservjs config file exists"
    else
        bashio::log.error "✗ scanservjs config file missing at $SCANSERVJS_CONFIG_PATH"
    fi
    
    # Start scanservjs as the scanservjs user
    bashio::log.info "Starting scanservjs Node.js application..."
    cd /usr/lib/scanservjs
    
    # Test the command first
    bashio::log.info "Testing scanservjs startup command..."
    if su -s /bin/bash scanservjs -c "NODE_ENV=production node server/server.js --help 2>&1" 2>/dev/null; then
        bashio::log.info "✓ scanservjs command test successful"
    else
        bashio::log.warning "scanservjs command test failed, trying anyway..."
    fi
    
    # Start in background with output redirected
    su -s /bin/bash scanservjs -c "NODE_ENV=production node server/server.js 2>&1 | logger -t scanservjs" &
    SCANSERVJS_PID=$!
    bashio::log.info "scanservjs started with PID: $SCANSERVJS_PID"
    
    # Wait a moment and check if it's running
    sleep 5
    if kill -0 $SCANSERVJS_PID 2>/dev/null; then
        bashio::log.info "✓ scanservjs is running successfully"
        
        # Test if port 8080 is listening
        sleep 2
        if nc -z localhost 8080; then
            bashio::log.info "✓ scanservjs is listening on port 8080"
        else
            bashio::log.error "✗ scanservjs is not listening on port 8080"
        fi
    else
        bashio::log.error "✗ scanservjs failed to start"
    fi
else
    bashio::log.error "scanservjs server.js not found - installation may have failed"
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
    
    # Check Avahi health and network advertising
    if ! pgrep avahi-daemon > /dev/null; then
        bashio::log.error "Avahi daemon died, restarting..."
        avahi-daemon &
        AVAHI_PID=$!
        sleep 3
        # Also restart CUPS to re-register with Avahi
        bashio::log.info "Restarting CUPS to re-register with Avahi..."
        kill $CUPS_PID 2>/dev/null || true
        cupsd &
        CUPS_PID=$!
    fi
    
    # Check network discovery health (every 2 minutes)
    if [ $(($(date +%s) % 120)) -eq 0 ]; then
        if ! avahi-browse -t _ipp._tcp 2>/dev/null | grep -q "$(hostname)"; then
            bashio::log.warning "Network discovery seems broken, refreshing services..."
            # Restart Avahi and CUPS to refresh network advertising
            kill $AVAHI_PID 2>/dev/null || true
            kill $CUPS_PID 2>/dev/null || true
            sleep 2
            avahi-daemon &
            AVAHI_PID=$!
            sleep 3
            cupsd &
            CUPS_PID=$!
            bashio::log.info "Network services refreshed"
        fi
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
