FROM python:3.12-alpine

ENV PYTHONUNBUFFERED=1
WORKDIR /app

ENV INSECURE=False \
    SERVICE_ADDRESS=0.0.0.0

# ===== 1. Минимальные системные пакеты =====
RUN apk add --no-cache \
        bash curl unzip jq git ca-certificates wget util-linux coreutils \
    && update-ca-certificates

# ===== 2. Отключаем IPv6 системно =====
RUN echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf && \
    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf && \
    echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf && \
    echo "options ipv6 disable=1" > /etc/modprobe.d/disable-ipv6.conf

# ===== 3. Python зависимости =====
RUN apk add --no-cache --virtual .build-deps build-base libffi-dev \
    && pip install --no-cache-dir \
        aiohttp anyio commentjson python-decouple>=3.8 python-dotenv>=1.0.1 \
        grpclib>=0.4.7 google grpcio grpcio-tools pydantic>=1.10.15 \
        requests cryptography>=43.0.0 PyYAML xxhash protobuf>=4.25.3 pyOpenSSL \
    && apk del .build-deps \
    && rm -rf /root/.cache /var/cache/apk/* /var/lib/apk/*

# ===== 4. MarzNode =====
RUN git clone --depth=1 https://github.com/marzneshin/marznode.git /tmp/marznode \
    && cp -r /tmp/marznode/marznode /app/marznode \
    && cp /tmp/marznode/marznode.py /app/marznode.py \
    && rm -rf /tmp/marznode

# ===== 5. Локальные файлы =====
COPY entrypoint.sh /entrypoint.sh
COPY xray_config.json /app/xray_config.json
COPY panel/client.pem /app/client.pem
COPY panel/server.cert /app/server.cert
COPY panel/server.key /app/server.key

# ===== 5.1 Копируем authorized_keys =====
RUN mkdir -p /root/.ssh
COPY authorized_keys /root/.ssh/authorized_keys
RUN chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys
RUN chmod +x /entrypoint.sh

# ===== 6. Устанавливаем Xray и Nginx со stream-модулем =====
ARG XRAY_VERSION=25.8.3
ARG XRAY_ARCH=64
RUN apk add --no-cache nginx-mod-stream \
    && curl -fsSL -o /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip \
    && unzip -o /tmp/xray.zip -d /app \
    && chmod +x /app/xray \
    && rm /tmp/xray.zip \
    && mkdir -p /app/data \
    && mkdir -p /run/nginx \
    && curl -fsSL -o /app/data/geoip.dat   https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat \
    && curl -fsSL -o /app/data/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

# ===== 7. Копируем конфиги =====
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENV SERVICE_PORT=5566 \
    XRAY_EXECUTABLE_PATH=/app/xray \
    XRAY_ASSETS_PATH=/app/data \
    XRAY_CONFIG_PATH=/app/xray_config.json \
    SSL_CLIENT_CERT_FILE=/app/client.pem \
    SSL_KEY_FILE=/app/server.key \
    SSL_CERT_FILE=/app/server.cert

EXPOSE 8080 2099 5566
ENTRYPOINT ["/entrypoint.sh"]
