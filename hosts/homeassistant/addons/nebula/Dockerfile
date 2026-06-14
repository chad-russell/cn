FROM alpine:3.21

ENV NEBULA_VERSION=1.10.3

RUN apk add --no-cache --virtual .build-deps curl \
    && case "$(uname -m)" in \
        x86_64)  ARCH='linux-amd64' ;; \
        aarch64) ARCH='linux-arm64' ;; \
        armv7l)  ARCH='linux-arm-7' ;; \
        *) echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac \
    && curl -fSL "https://github.com/slackhq/nebula/releases/download/v${NEBULA_VERSION}/nebula-${ARCH}.tar.gz" \
        | tar xz -C /usr/bin/ \
    && chmod 755 /usr/bin/nebula /usr/bin/nebula-cert \
    && apk del .build-deps

COPY nebula.yaml /etc/nebula/config.yaml
COPY run.sh /run.sh
RUN chmod +x /run.sh

ENTRYPOINT ["/run.sh"]
