ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm
FROM $BUILD_FROM

LABEL io.hass.version="1.4.4" io.hass.type="addon" io.hass.arch="armhf|aarch64|i386|amd64"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Optimize APT for faster, smaller builds
RUN echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99no-recommends \
    && echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf.d/99no-recommends \
    && echo 'APT::Get::Clean "always";' >> /etc/apt/apt.conf.d/99auto-clean \
    && echo 'DPkg::Post-Invoke {"/bin/rm -f /var/cache/apt/archives/*.deb || true";};' >> /etc/apt/apt.conf.d/99auto-clean

# Single optimized package installation with aggressive cleanup
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        # Core system packages
        sudo \
        nano \
        netcat-openbsd \
        nodejs \
        npm \
        curl \
        # CUPS printing packages
        cups \
        cups-pdf \
        colord \
        # Minimal printer drivers (configurable at runtime)
        printer-driver-hpcups \
        printer-driver-brlaser \
        # Network discovery packages
        avahi-daemon \
        libnss-mdns \
        dbus \
        # SANE scanning packages
        sane \
        libsane-common \
        sane-utils \
        sane-airscan \
        imagemagick \
        ipp-usb \
        # OCR support (minimal, configurable)
        tesseract-ocr \
        tesseract-ocr-eng \
    # Aggressive cleanup for smaller image
    && apt-get autoremove -y \
    && apt-get autoclean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /var/cache/apt/archives/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/doc/* \
        /usr/share/man/* \
        /usr/share/info/* \
        /usr/share/lintian/* \
        /var/cache/debconf/* \
        /usr/share/common-licenses/* \
        /usr/share/mime/* \
    # Remove locales except English
    && find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' -exec rm -rf {} + \
    # Clean Python bytecode
    && find /usr -name "*.pyc" -delete \
    && find /usr -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# Copy rootfs and install scanservjs in single optimized layer
COPY rootfs /
RUN set -e \
    # Download and install scanservjs with minimal logging
    && curl -fsSL "https://github.com/sbs20/scanservjs/releases/download/v3.0.3/scanservjs_3.0.3-1_all.deb" -o /tmp/scanservjs.deb \
    && dpkg -i /tmp/scanservjs.deb \
    # Create user with minimal setup
    && useradd --groups=sudo,lp,lpadmin --create-home --home-dir=/home/print --shell=/bin/bash print \
    && echo 'print:print' | chpasswd \
    && sed -i '/%sudo[[:space:]]/ s/ALL[[:space:]]*$/NOPASSWD:ALL/' /etc/sudoers \
    # Final cleanup
    && rm -f /tmp/scanservjs.deb \
    && rm -rf /tmp/* /var/tmp/* \
    && chmod a+x /run.sh

EXPOSE 631 8080
CMD ["/run.sh"]
