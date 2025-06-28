ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm
FROM $BUILD_FROM

LABEL io.hass.version="1.1.3" io.hass.type="addon" io.hass.arch="armhf|aarch64|i386|amd64"

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

# Install scanservjs with pinned version and comprehensive verification
RUN set -e && \
    SCANSERVJS_VERSION="v3.0.3" && \
    echo "Installing scanservjs version: ${SCANSERVJS_VERSION}" && \
    curl -fsSL https://raw.githubusercontent.com/sbs20/scanservjs/master/bootstrap.sh -o /tmp/bootstrap.sh && \
    chmod +x /tmp/bootstrap.sh && \
    /tmp/bootstrap.sh -v ${SCANSERVJS_VERSION} && \
    rm -f /tmp/bootstrap.sh

# Verify installation step by step with detailed logging
RUN echo "=== Starting scanservjs installation verification ===" && \
    echo "Step 1: Checking /usr/bin/scanservjs..." && \
    (test -f /usr/bin/scanservjs && echo "✓ Found in /usr/bin/scanservjs") || echo "✗ Not found in /usr/bin/scanservjs"

RUN echo "Step 2: Checking /usr/local/bin/scanservjs..." && \
    (test -f /usr/local/bin/scanservjs && echo "✓ Found in /usr/local/bin/scanservjs") || echo "✗ Not found in /usr/local/bin/scanservjs"

RUN echo "Step 3: Checking /opt/scanservjs/bin/scanservjs..." && \
    (test -f /opt/scanservjs/bin/scanservjs && echo "✓ Found in /opt/scanservjs/bin/scanservjs") || echo "✗ Not found in /opt/scanservjs/bin/scanservjs"

RUN echo "Step 4: Checking package installation with dpkg..." && \
    dpkg -l | grep scanservjs && echo "✓ Package found in dpkg" || echo "✗ Package not found in dpkg"

RUN echo "Step 5: Listing all scanservjs files..." && \
    find / -name "*scanservjs*" -type f 2>/dev/null | head -10 || echo "No scanservjs files found"

RUN echo "Step 6: Final verification..." && \
    (test -f /usr/bin/scanservjs || test -f /usr/local/bin/scanservjs || \
     test -f /opt/scanservjs/bin/scanservjs || dpkg -l | grep -q scanservjs) && \
    echo "✓ scanservjs installation verified successfully" || \
    (echo "✗ scanservjs installation verification failed" && exit 1)


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
