ARG BUILD_FROM
FROM $BUILD_FROM

LABEL io.hass.version="1.0" io.hass.type="addon" io.hass.arch="armhf|aarch64|i386|amd64"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install base packages first (your existing ones)
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
        curl \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install SANE packages with correct names
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        sane-utils \
        libsane \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js from NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install scanservjs
RUN npm install -g scanservjs

COPY rootfs /

# Add user and disable sudo password checking
RUN useradd \
  --groups=sudo,lp,lpadmin \
  --create-home \
  --home-dir=/home/print \
  --shell=/bin/bash \
  --password=$(mkpasswd print) \
  print \
&& sed -i '/%sudo[[:space:]]/ s/ALL[[:space:]]*$/NOPASSWD:ALL/' /etc/sudoers

EXPOSE 631
RUN chmod a+x /run.sh

CMD ["/run.sh"]