ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm
FROM $BUILD_FROM

LABEL io.hass.version="1.2.4" io.hass.type="addon" io.hass.arch="armhf|aarch64|i386|amd64"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# printer-driver-brlaser specifically called out for Brother printer support
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        sudo \
        locales \
        cups \
        avahi-daemon \
        libnss-mdns \
        dbus \
        colord \
        printer-driver-all-enforce \
        openprinting-ppds \
        hpijs-ppds \
        hp-ppd  \
        hplip \
        printer-driver-brlaser \
        cups-pdf \
        gnupg2 \
        lsb-release \
        nano \
        samba \
        bash-completion \
        procps \
        whois \
        nodejs \
        npm \
        netcat-openbsd \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install SANE packages separately with alternatives
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        sane \
        libsane-common \
        libsane-dev \
        sane-utils \
        sane-airscan \
        imagemagick \
        ipp-usb \
        tesseract-ocr \
        gnupg \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

COPY rootfs /

# Install scanservjs with comprehensive debug logging
RUN set -e && \
    echo "=== Starting scanservjs installation ===" > /install-debug.log && \
    echo "Date: $(date)" >> /install-debug.log && \
    echo "Architecture: $(uname -m)" >> /install-debug.log && \
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME)" >> /install-debug.log && \
    echo "Available disk space: $(df -h / | tail -1)" >> /install-debug.log && \
    echo "Memory: $(free -h | head -2 | tail -1)" >> /install-debug.log && \
    echo "" >> /install-debug.log && \
    \
    echo "Downloading scanservjs .deb file..." >> /install-debug.log && \
    if curl -fsSL "https://github.com/sbs20/scanservjs/releases/download/v3.0.3/scanservjs_3.0.3-1_all.deb" -o /tmp/scanservjs.deb; then \
        echo "✓ Download successful" >> /install-debug.log && \
        echo "File size: $(stat -c%s /tmp/scanservjs.deb) bytes" >> /install-debug.log && \
        echo "File type: $(file /tmp/scanservjs.deb)" >> /install-debug.log; \
    else \
        echo "✗ Download failed" >> /install-debug.log && \
        exit 1; \
    fi && \
    \
    echo "" >> /install-debug.log && \
    echo "Installing .deb package..." >> /install-debug.log && \
    dpkg -i /tmp/scanservjs.deb 2>&1 | tee -a /install-debug.log && \
    echo "✓ dpkg installation completed" >> /install-debug.log && \
    rm -f /tmp/scanservjs.deb

# Verify installation with detailed results
RUN echo "" >> /install-debug.log && \
    echo "=== Installation Verification ===" >> /install-debug.log && \
    \
    echo "1. Checking package in dpkg:" >> /install-debug.log && \
    if dpkg -l | grep scanservjs >> /install-debug.log; then \
        echo "✓ Package found in dpkg" >> /install-debug.log; \
    else \
        echo "✗ Package not found in dpkg" >> /install-debug.log; \
    fi && \
    \
    echo "" >> /install-debug.log && \
    echo "2. Searching for scanservjs files:" >> /install-debug.log && \
    find /usr /opt -name "*scanservjs*" -type f 2>/dev/null >> /install-debug.log || echo "No scanservjs files found" >> /install-debug.log && \
    \
    echo "" >> /install-debug.log && \
    echo "3. Checking systemd service file:" >> /install-debug.log && \
    if [ -f /lib/systemd/system/scanservjs.service ]; then \
        echo "✓ Found systemd service file:" >> /install-debug.log && \
        cat /lib/systemd/system/scanservjs.service >> /install-debug.log; \
    else \
        echo "✗ No systemd service file found" >> /install-debug.log; \
    fi && \
    \
    echo "" >> /install-debug.log && \
    echo "4. Checking package contents:" >> /install-debug.log && \
    dpkg -L scanservjs | head -20 >> /install-debug.log && \
    \
    echo "" >> /install-debug.log && \
    echo "5. Looking for Node.js files:" >> /install-debug.log && \
    find /usr/lib /usr/share /opt -name "*.js" -path "*scanservjs*" 2>/dev/null >> /install-debug.log || echo "No Node.js files found" >> /install-debug.log && \
    \
    echo "" >> /install-debug.log && \
    echo "6. Complete scanservjs directory structure:" >> /install-debug.log && \
    find /usr/lib/scanservjs -type f 2>/dev/null >> /install-debug.log || echo "No scanservjs directory found" >> /install-debug.log && \
    \
    echo "" >> /install-debug.log && \
    echo "=== Debug Summary Complete ===" >> /install-debug.log


# Add user and disable sudo password checking
RUN useradd \
  --groups=sudo,lp,lpadmin \
  --create-home \
  --home-dir=/home/print \
  --shell=/bin/bash \
  --password=$(mkpasswd print) \
  print \
&& sed -i '/%sudo[[:space:]]/ s/ALL[[:space:]]*$/NOPASSWD:ALL/' /etc/sudoers

EXPOSE 631 8080
RUN chmod a+x /run.sh

CMD ["/run.sh"]
