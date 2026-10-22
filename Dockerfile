# Pinokio home-server image.
#
# Extends the upstream joly0/pinokio-docker image (Pinokio on the Selkies
# streamed desktop) with the pieces needed to run it as a small, always-on
# home server that is reached through Pinokio's *own* web UI instead of the
# streamed X11 desktop:
#
#   * lsof, so Pinokio's own port-conflict detection works
#   * a patched app.asar: GPU acceleration stays on, and the local-sharing
#     proxy no longer crashes the app when its port is already taken
#   * an nginx reverse proxy (basic-auth protected) in front of Pinokio's UI
#     on 127.0.0.1:42000, exposed internally on 3002
#   * a launcher that keeps Pinokio in "full" mode and single-instanced
#
# Build:
#   docker build -t pinokio-home .
#
# Pass --build-arg PINOKIO_VERSION=<tag> to pin a specific Pinokio release.
ARG BASE_IMAGE=joly0/pinokio-docker:latest
FROM ${BASE_IMAGE}

ARG PINOKIO_VERSION

# 1. lsof + a JavaScript runtime for the asar patcher. The base image already
#    configures the NodeSource apt repository, so nodejs installs from there.
#    node is removed again after use to keep the image tidy.
RUN \
  echo "**** install build-time tools ****" && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    lsof \
    nodejs \
    npm \
  && \
  echo "**** patch app.asar ****" && \
  mkdir -p /tmp/asar-tools && \
  cd /tmp/asar-tools && \
  npm install --no-save --no-audit --no-fund @electron/asar >/dev/null 2>&1 && \
  cp /patches/patch-asar.js /tmp/asar-tools/patch-asar.js && \
  node /tmp/asar-tools/patch-asar.js /opt/Pinokio/resources/app.asar && \
  echo "**** remove build-time tools ****" && \
  DEBIAN_FRONTEND=noninteractive apt-get purge -y nodejs npm && \
  apt-get autoremove -y && \
  apt-get autoclean && \
  rm -rf /tmp/asar-tools /var/lib/apt/lists/* /var/tmp/* /tmp/*

# 2. Local files: nginx drop-in, launcher, ui-proxy config, init hook.
COPY root /
COPY patches/patch-asar.js /patches/patch-asar.js

RUN chmod +x \
      /usr/bin/start-pinokio.sh \
      /usr/bin/wrapped-pinokio \
      /usr/bin/pinokio \
      /custom-cont-init.d/10-pinokio-ui-proxy.sh && \
    # Point /opt/Pinokio/pinokio at the supervised launcher too, so anything
    # that calls the stock path gets the single-instanced, GPU-enabled one.
    printf '#!/bin/bash\nexec /usr/bin/wrapped-pinokio "$@"\n' > /opt/Pinokio/pinokio && \
    chmod +x /opt/Pinokio/pinokio

# The streamed desktop (3000/3001) still works, the UI proxy listens on 3002,
# and the tunnel points at 3002.
EXPOSE 3000 3001 3002

LABEL org.opencontainers.image.title="pinokio-home" \
      org.opencontainers.image.description="Pinokio as a home server, reached through its own web UI over a bore tunnel"
