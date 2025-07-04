ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm
FROM $BUILD_FROM

LABEL io.hass.version="1.2.7" io.hass.type="addon" io.hass.arch="armhf|aarch64|i386|amd64"

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

# Verify installation with minimal logging
RUN echo "" >> /install-debug.log && \
    echo "=== Installation Verification ===" >> /install-debug.log && \
    \
    if dpkg -l | grep -q scanservjs; then \
        echo "✓ scanservjs package installed successfully" >> /install-debug.log; \
    else \
        echo "✗ scanservjs package not found" >> /install-debug.log; \
    fi && \
    \
    if [ -f /usr/lib/scanservjs/server/server.js ]; then \
        echo "✓ scanservjs server.js found" >> /install-debug.log; \
    else \
        echo "✗ scanservjs server.js missing" >> /install-debug.log; \
    fi && \
    \
    echo "Total installed files: $(find /usr/lib/scanservjs -type f 2>/dev/null | wc -l)" >> /install-debug.log && \
    echo "=== Installation Complete ===" >> /install-debug.log


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
