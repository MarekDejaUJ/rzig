FROM kalibera/rchk:latest

ARG DEBIAN_FRONTEND=noninteractive
ARG ZIG_VERSION=0.16.0
ARG ZIG_SHA256=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00

RUN apt-get update && \
    apt-get install -yq --no-install-recommends curl xz-utils && \
    rm -rf /var/lib/apt/lists/*

RUN curl --fail --location --silent --show-error \
      "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
      --output /tmp/zig.tar.xz && \
    echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum --check --strict && \
    mkdir -p /opt/zig && \
    tar -xJf /tmp/zig.tar.xz --strip-components=1 -C /opt/zig && \
    ln -s /opt/zig/zig /usr/local/bin/zig && \
    rm /tmp/zig.tar.xz
