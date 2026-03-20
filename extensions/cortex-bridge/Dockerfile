# Cortex Bridge -- Multi-stage Docker build
#
# Stage 1: Build the Rust binary
# Stage 2: Minimal runtime image (debian-slim for glibc compatibility)

FROM rust:1.85-slim AS builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/cortex-bridge /usr/local/bin/

# Default data directory for SQLite database
RUN mkdir -p /data
ENV CORTEX_BRIDGE_DB_PATH=/data/cortex-bridge.db

EXPOSE 8443

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -sf http://localhost:8443/api/health || exit 1

CMD ["cortex-bridge"]
