#!/usr/bin/with-contenv bashio

# Get configuration efficiently
hostname=$(bashio::info.hostname)
result=$(bashio::api.supervisor GET /core/api/config true || true)
internal=$(bashio::jq "$result" '.internal_url' | cut -d'/' -f3 | cut -d':' -f1)
external=$(bashio::jq "$result" '.external_url' | cut -d'/' -f3 | cut -d':' -f1)

config=$(jq --arg internal "$internal" --arg external "$external" --arg hostname "$hostname" \
    '{internal: $internal, external: $external, hostname: $hostname}' \
    /data/options.json)

# Generate configuration files
echo "$config" | tempio -template /usr/share/cupsd.conf.tempio -out /etc/cups/cupsd.conf
echo "$config" | tempio -template /usr/share/avahi-daemon.conf.tempio -out /etc/avahi/avahi-daemon.conf
echo "$config" | tempio -template /usr/share/sane.conf.tempio -out /etc/sane.d/saned.conf

bashio::log.info "Initializing print and scan services..."

# Install additional printer drivers if configured (runtime optimization)
PRINTER_SUPPORT=$(bashio::config 'printer_support' 'full')
if [[ "$PRINTER_SUPPORT" != "minimal" ]]; then
    PRINTER_PACKAGES=""
    case $PRINTER_SUPPORT in
        common)
            PRINTER_PACKAGES="printer-driver-escpr printer-driver-splix openprinting-ppds"
            ;;
        full)
            PRINTER_PACKAGES="printer-driver-all-enforce openprinting-ppds hpijs-ppds hp-ppd hplip"
            ;;
    esac
    
    if [[ -n "$PRINTER_PACKAGES" ]]; then
        bashio::log.info "Installing $PRINTER_SUPPORT printer drivers..."
        apt-get update > /dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y sudo \
  whois \
  usbutils \
  build-essential \
  libcups2-dev \
  cups \
  cups-client \
  cups-bsd \
  cups-filters \
  foomatic-db-compressed-ppds \
  printer-driver-all \
  openprinting-ppds \
  hpijs-ppds \
  hp-ppd \
  hplip \
  smbclient \
  printer-driver-cups-pdf \ > /dev/null 2>&1
        apt-get clean > /dev/null 2>&1
        rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
        bashio::log.info "✓ Additional printer drivers installed"
        
        # HP-specific initialization
        if echo "$PRINTER_PACKAGES" | grep -q "hplip"; then
            bashio::log.info "Initializing HP scanner support..."
            # Create HP configuration directory
            mkdir -p /etc/hp /var/lib/hp
            # Initialize HP system (non-interactive)
            /usr/bin/hp-setup --help > /dev/null 2>&1 || true
            bashio::log.info "✓ HP scanner support initialized"
        fi
    fi
fi

# https://github.com/neutralvibes/pi-cups/blob/master/build/Dockerfile
# Download and install driver patches for printers like Samsung M2020
wget https://gitlab.com/ScumCoder/splix/-/archive/patches/splix-patches.zip \
  && unzip splix-patches.zip \
  && rm -v splix-patches.zip \
  && cd splix-patches/splix \
  && make DISABLE_JBIG=1 \
  && make install

# Install OCR languages efficiently
if bashio::config.exists 'ocr_languages'; then
    OCR_LANGUAGES=$(bashio::config 'ocr_languages[]')
    PACKAGES=""
    for lang in $OCR_LANGUAGES; do
        [[ "$lang" != "eng" ]] && PACKAGES="$PACKAGES tesseract-ocr-$lang"
    done
    
    if [[ -n "$PACKAGES" ]]; then
        bashio::log.info "Installing additional OCR languages..."
        apt-get update > /dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $PACKAGES > /dev/null 2>&1
        apt-get clean > /dev/null 2>&1
        rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
        bashio::log.info "✓ OCR languages installed"
    fi
fi

# Initialize directories efficiently
cp -R /etc/cups /data 2>/dev/null || true
rm -rf /etc/cups && ln -sf /data/cups /etc/cups

mkdir -p /data/scans /data/sane.d
cp -R /etc/sane.d/* /data/sane.d/ 2>/dev/null || true
rm -rf /etc/sane.d && ln -sf /data/sane.d /etc/sane.d

# Ensure HP SANE backend is enabled
if [ -f /data/sane.d/dll.conf ]; then
    if ! grep -q "^hpaio" /data/sane.d/dll.conf; then
        echo "hpaio" >> /data/sane.d/dll.conf
        bashio::log.info "✓ HP SANE backend (hpaio) enabled"
    fi
fi

# Generate scanservjs configuration
echo "$config" | tempio \
    -template /usr/share/scanservjs.config.js.tempio \
    -out /data/scanservjs.config.js

# Update OCR language configuration based on user settings
if bashio::config.exists 'ocr_languages'; then
    OCR_LANGUAGES=$(bashio::config 'ocr_languages[]')
    bashio::log.info "Configuring OCR languages: $OCR_LANGUAGES"
    
    # Build JavaScript array of language objects
    LANG_ARRAY="      { key: 'eng', name: 'English' }"
    for lang in $OCR_LANGUAGES; do
        case $lang in
            eng) ;; # Already included
            deu) LANG_ARRAY="$LANG_ARRAY,\n      { key: 'deu', name: 'German' }" ;;
            fra) LANG_ARRAY="$LANG_ARRAY,\n      { key: 'fra', name: 'French' }" ;;
            spa) LANG_ARRAY="$LANG_ARRAY,\n      { key: 'spa', name: 'Spanish' }" ;;
            ita) LANG_ARRAY="$LANG_ARRAY,\n      { key: 'ita', name: 'Italian' }" ;;
            por) LANG_ARRAY="$LANG_ARRAY,\n      { key: 'por', name: 'Portuguese' }" ;;
            nld) LANG_ARRAY="$LANG_ARRAY,\n      { key: 'nld', name: 'Dutch' }" ;;
            rus) LANG_ARRAY="$LANG_ARRAY,\n      { key: 'rus', name: 'Russian' }" ;;
            jpn) LANG_ARRAY="$LANG_ARRAY,\n      { key: 'jpn', name: 'Japanese' }" ;;
            chi_sim) LANG_ARRAY="$LANG_ARRAY,\n      { key: 'chi_sim', name: 'Chinese (Simplified)' }" ;;
            chi_tra) LANG_ARRAY="$LANG_ARRAY,\n      { key: 'chi_tra', name: 'Chinese (Traditional)' }" ;;
            ara) LANG_ARRAY="$LANG_ARRAY,\n      { key: 'ara', name: 'Arabic' }" ;;
        esac
    done
    
    # Replace the languages array in the config file
    sed -i "s/      { key: 'eng', name: 'English' }/$LANG_ARRAY/" /data/scanservjs.config.js
    
    # Also update the text output format language options
    LANG_OPTIONS="'eng'"
    for lang in $OCR_LANGUAGES; do
        if [[ "$lang" != "eng" ]]; then
            LANG_OPTIONS="$LANG_OPTIONS, '$lang'"
        fi
    done
    
    # Replace the options array in the text output format
    sed -i "s/options: \['eng'\]/options: [$LANG_OPTIONS]/" /data/scanservjs.config.js
    bashio::log.info "✓ OCR language configuration updated"
fi

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

# Clean up any stale files
rm -f /var/run/avahi-daemon/* /run/dbus/* /data/cups/cache/* /data/cups/remote.cache 2>/dev/null || true

# Start services efficiently
bashio::log.info "Starting services..."
mkdir -p /var/run/dbus /run/dbus

# Start DBUS
dbus-daemon --system --nofork &
DBUS_PID=$!
sleep 1

# Start Avahi
avahi-daemon &
AVAHI_PID=$!
sleep 2

# Start CUPS
cupsd &
CUPS_PID=$!

# Wait for CUPS to be ready (optimized check)
for i in {1..15}; do
    nc -z localhost 631 && break
    sleep 2
done

if nc -z localhost 631; then
    bashio::log.info "✓ CUPS ready on port 631"
    
    # Display Windows connection information
    bashio::log.info "Windows printer connection:"
    bashio::log.info "  Add printer URL: http://$(hostname -I | awk '{print $1}'):631/printers/[printer-name]"
    bashio::log.info "  Or use: \\\\$(hostname -I | awk '{print $1}'):631"
    bashio::log.info "  Admin interface: http://$(hostname -I | awk '{print $1}'):631"
    
    # Test if printer queues exist
    if [ -d /data/cups/ppd ] && [ "$(ls -A /data/cups/ppd 2>/dev/null)" ]; then
        bashio::log.info "✓ Printer queues configured"
        ls /data/cups/ppd/*.ppd 2>/dev/null | while read ppd; do
            printer_name=$(basename "$ppd" .ppd)
            bashio::log.info "  Printer: $printer_name"
        done
    else
        bashio::log.info "⚠ No printer queues configured - use CUPS admin interface to add printers"
    fi
else
    bashio::log.error "✗ CUPS failed to start"
fi

# Set up USB device permissions for scanners
chmod 666 /dev/bus/usb/*/*  2>/dev/null || true
chown -R root:scanner /dev/bus/usb/ 2>/dev/null || true

# Add sane-port service definition if not present
if [ ! -f /etc/services ]; then
    touch /etc/services
fi
if ! grep -q "sane-port" /etc/services 2>/dev/null; then
    echo "sane-port 6566/tcp # SANE daemon" >> /etc/services
fi

# Test scanner detection directly with SANE
bashio::log.info "Testing scanner detection..."
SCANNERS=$(scanimage -L 2>/dev/null | grep -c "device" || echo "0")
if [[ $SCANNERS -gt 0 ]]; then
    bashio::log.info "✓ Found $SCANNERS scanner(s)"
    scanimage -L | while read line; do
        bashio::log.info "  $line"
    done
else
    bashio::log.warning "⚠ No scanners detected by SANE"
    bashio::log.info "Check that scanner is connected and powered on"
    bashio::log.info "Trying to find USB devices..."
    lsusb 2>/dev/null || bashio::log.info "  lsusb not available"
    bashio::log.info "Trying sane-find-scanner..."
    sane-find-scanner 2>/dev/null || bashio::log.info "  sane-find-scanner not available"
    
    # Check for HP-specific issues
    if sane-find-scanner 2>/dev/null | grep -q "HP.*DeskJet"; then
        bashio::log.info "HP DeskJet detected, checking HP drivers..."
        if [ -f /usr/bin/hp-scan ]; then
            bashio::log.info "  ✓ HP scanning tools available"
            hp-scan -g 2>/dev/null || bashio::log.info "  HP scanner test completed"
        else
            bashio::log.info "  ⚠ HP scanning tools not found"
        fi
        
        # Check if hpaio backend is available
        if [ -f /usr/lib/*/sane/libsane-hpaio.so.* ]; then
            bashio::log.info "  ✓ HP SANE backend (hpaio) available"
        else
            bashio::log.info "  ⚠ HP SANE backend (hpaio) not found"
        fi
    fi
    
    bashio::log.info "SANE backends available:"
    ls /usr/lib/*/sane/ 2>/dev/null | head -10 || bashio::log.info "  No SANE backends directory found"
    bashio::log.info "SANE DLL configuration:"
    cat /etc/sane.d/dll.conf | grep -v "^#" | head -10 || bashio::log.info "  No dll.conf found"
fi

# Start scanservjs
if [ -f /usr/lib/scanservjs/server/server.js ]; then
    mkdir -p /data/scans /tmp/scanservjs
    chmod 755 /data/scans /tmp/scanservjs
    
    id scanservjs &>/dev/null || {
        useradd -r -s /bin/false -d /var/lib/scanservjs scanservjs
        groupadd -f scanner
        groupadd -f plugdev
        usermod -a -G scanner,lp,plugdev,dialout scanservjs
    }
    
    export NODE_ENV=production
    export SCANSERVJS_CONFIG_PATH="/data/scanservjs.config.js"
    export SCANSERVJS_OUTPUT_DIR="/data/scans"
    export SCANSERVJS_PREVIEW_DIR="/tmp/scanservjs"
    export SANE_DEBUG_DLL=1
    export SANE_CONFIG_DIR="/etc/sane.d"
    export LOG_LEVEL=error
    export SCANSERVJS_LOG_LEVEL=error
    
    # Test if scanservjs user can access SANE
    bashio::log.info "Testing SANE access for scanservjs user..."
    if su -s /bin/bash scanservjs -c "scanimage -L" 2>/dev/null; then
        bashio::log.info "  ✓ scanservjs user can access SANE"
        USE_ROOT=false
    else
        bashio::log.info "  ⚠ scanservjs user cannot access SANE, trying as root"
        USE_ROOT=true
    fi
    
    cd /usr/lib/scanservjs
    if [ "$USE_ROOT" = "true" ]; then
        bashio::log.info "Starting scanservjs as root due to permission issues"
        LOG_LEVEL=error node server/server.js &
        SCANSERVJS_PID=$!
    else
        bashio::log.info "Starting scanservjs as dedicated user"
        su -s /bin/bash scanservjs -c "LOG_LEVEL=error node server/server.js" &
        SCANSERVJS_PID=$!
    fi
    
    sleep 3
    if kill -0 $SCANSERVJS_PID 2>/dev/null && nc -z localhost 8080; then
        bashio::log.info "✓ scanservjs ready on port 8080"
        bashio::log.info "  (scanservjs logging set to ERROR level to reduce log noise)"
    else
        bashio::log.error "✗ scanservjs failed to start"
    fi
fi

# Signal handler for clean shutdown
trap 'kill $DBUS_PID $AVAHI_PID $CUPS_PID $SCANSERVJS_PID 2>/dev/null; exit' TERM INT

bashio::log.info "All services running. Addon ready."

# Lightweight health monitoring
while true; do
    sleep 60
    
    # Restart dead services
    pgrep cupsd > /dev/null || { cupsd & CUPS_PID=$!; }
    pgrep avahi-daemon > /dev/null || { avahi-daemon & AVAHI_PID=$!; }
    
    if [[ -n "$SCANSERVJS_PID" ]] && ! kill -0 $SCANSERVJS_PID 2>/dev/null; then
        cd /usr/lib/scanservjs
        if [ "$USE_ROOT" = "true" ]; then
            LOG_LEVEL=error node server/server.js &
            SCANSERVJS_PID=$!
        else
            su -s /bin/bash scanservjs -c "LOG_LEVEL=error node server/server.js" &
            SCANSERVJS_PID=$!
        fi
    fi
done
