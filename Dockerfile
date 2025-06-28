ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm
FROM $BUILD_FROM

LABEL io.hass.version="1.1.5" io.hass.type="addon" io.hass.arch="armhf|aarch64|i386|amd64"

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

# Install scanservjs - simplified for debugging
RUN set -e && \
    curl -fsSL "https://github.com/sbs20/scanservjs/releases/download/v3.0.3/scanservjs_3.0.3-1_all.deb" -o /tmp/scanservjs.deb && \
    dpkg -i /tmp/scanservjs.deb && \
    rm -f /tmp/scanservjs.deb

# Simple verification - just check if the package installed
RUN dpkg -l | grep scanservjs


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
