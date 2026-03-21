FROM debian:bookworm-20260112-slim@sha256:56ff6d36d4eb3db13a741b342ec466f121480b5edded42e4b7ee850ce7a418ee

LABEL org.opencontainers.image.title="network-stealth-core" \
    org.opencontainers.image.description="network stealth core runtime image" \
    org.opencontainers.image.source="https://github.com/neket371/network-stealth-core" \
    org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive
ENV XRAY_HOME=/opt/xray-reality

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        iproute2 \
        iptables \
        jq \
        logrotate \
        openssl \
        procps \
        tini \
        unzip \
    && groupadd --system xray \
    && useradd --system --gid xray --home-dir "$XRAY_HOME" --shell /usr/sbin/nologin xray \
    && mkdir -p "$XRAY_HOME" \
    && rm -rf /var/lib/apt/lists/*

WORKDIR $XRAY_HOME

COPY xray-reality.sh lib.sh install.sh config.sh service.sh health.sh export.sh ./
COPY domains.tiers sni_pools.map transport_endpoints.map ./
COPY modules ./modules

RUN chmod +x \
        xray-reality.sh \
        lib.sh \
        install.sh \
        config.sh \
        service.sh \
        health.sh \
        export.sh \
    && chown -R xray:xray "$XRAY_HOME"

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD bash -lc 'test -x /opt/xray-reality/xray-reality.sh && /opt/xray-reality/xray-reality.sh help >/dev/null 2>&1'

USER xray
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/xray-reality/xray-reality.sh"]
CMD ["--help"]
