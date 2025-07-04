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

# Configure Avahi for service advertisement only
echo "$config" | tempio \
    -template /usr/share/avahi-daemon.conf.tempio \
    -out /etc/avahi/avahi-daemon.conf

echo "$config" | tempio \
    -template /usr/share/sane.conf.tempio \
    -out /etc/sane.d/saned.conf

bashio::log.info "Initializing configuration and directories..."
cp -R /etc/cups /data >/dev/null 2>&1
rm -rf /etc/cups
ln -s /data/cups /etc/cups

# Clean up persistent state that might interfere with network discovery
rm -f /data/cups/cache/* 2>/dev/null || true
rm -f /data/cups/remote.cache 2>/dev/null || true
rm -f /data/cups/subscriptions.conf.O 2>/dev/null || true
rm -f /data/cups/printers.conf.O 2>/dev/null || true
rm -f /data/cups/browse.conf 2>/dev/null || true

# Initialize SANE and scanning directories  
bashio::log.info "Configuring SANE scanner support..."
mkdir -p /data/scans /data/sane.d
chmod 755 /data/scans
cp -R /etc/sane.d/* /data/sane.d/ 2>/dev/null || true
rm -rf /etc/sane.d
ln -s /data/sane.d /etc/sane.d
usermod -a -G scanner,lp root 2>/dev/null || true

# Generate scanservjs configuration
echo "$config" | tempio \
    -template /usr/share/scanservjs.config.js.tempio \
    -out /data/scanservjs.config.js

# Check installation status  
if [ -f /install-debug.log ]; then
    if grep -q "✓ scanservjs package installed successfully" /install-debug.log; then
        bashio::log.info "✓ scanservjs installation verified"
    else
        bashio::log.warning "⚠ scanservjs installation may have issues"
        bashio::log.info "Check /install-debug.log for details"
    fi
else
    bashio::log.error "No installation log found - build may have failed!"
fi

# Clear network cache and prepare for fresh service advertisement
rm -f /var/run/avahi-daemon/pid 2>/dev/null || true
rm -f /var/run/avahi-daemon/socket 2>/dev/null || true
rm -f /run/dbus/pid 2>/dev/null || true
rm -f /var/run/dbus/pid 2>/dev/null || true
rm -f /data/cups/cache/* 2>/dev/null || true
rm -f /data/cups/remote.cache 2>/dev/null || true

# Start services
bashio::log.info "Starting network services..."

# Start DBUS for Avahi communication
bashio::log.info "Starting DBUS daemon for service advertisement..."
mkdir -p /var/run/dbus /run/dbus
dbus-daemon --system --nofork &
DBUS_PID=$!

# Wait for DBUS to be ready
sleep 2

# Start Avahi daemon with unique hostname to avoid conflicts
bashio::log.info "Starting Avahi daemon for printer service advertisement..."
bashio::log.info "Using hostname: ${hostname}-print.local to avoid conflicts"
avahi-daemon &
AVAHI_PID=$!

# Wait for Avahi socket to be ready
sleep 3

# Start CUPS
bashio::log.info "Starting CUPS server..."
cupsd &
CUPS_PID=$!

# Wait for CUPS to be ready
CUPS_TIMEOUT=30
CUPS_COUNTER=0
until nc -z localhost 631; do
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

# Check scanservjs installation
if [ ! -f /usr/lib/scanservjs/server/server.js ]; then
    bashio::log.error "✗ scanservjs server.js not found - installation failed!"
    exit 1
fi

if [ -f /usr/lib/scanservjs/server/server.js ]; then
    # Ensure directories exist
    mkdir -p /data/scans /tmp/scanservjs
    chmod 755 /data/scans /tmp/scanservjs
    
    # Create scanservjs user if it doesn't exist
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
    bashio::log.info "Starting scanservjs..."
    cd /usr/lib/scanservjs
    su -s /bin/bash scanservjs -c "NODE_ENV=production node server/server.js 2>&1 | logger -t scanservjs" &
    SCANSERVJS_PID=$!
    
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
    
    # Check Avahi health and restart if needed
    if ! pgrep avahi-daemon > /dev/null; then
        bashio::log.error "Avahi daemon died, restarting..."
        avahi-daemon &
        AVAHI_PID=$!
        sleep 2
        # Also restart CUPS to re-register services
        kill $CUPS_PID 2>/dev/null || true
        cupsd &
        CUPS_PID=$!
    fi
    
    # Check CUPS health (every 2 minutes)
    if [ $(($(date +%s) % 120)) -eq 0 ]; then
        if ! nc -z localhost 631; then
            bashio::log.warning "CUPS port 631 not responding, refreshing CUPS service..."
            # Restart CUPS if it's not responding
            kill $CUPS_PID 2>/dev/null || true
            sleep 2
            cupsd &
            CUPS_PID=$!
            bashio::log.info "CUPS service refreshed"
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
