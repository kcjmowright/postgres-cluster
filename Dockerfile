FROM postgres:18-bookworm

LABEL org.opencontainers.image.title="PostgreSQL with pg_textsearch and pgvector"
LABEL org.opencontainers.image.description="PostgreSQL 18 with pg_textsearch and pgvector extensions"
LABEL org.opencontainers.image.version="18.0"
LABEL org.opencontainers.image.licenses="PostgreSQL"

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    postgresql-server-dev-18 \
    libicu-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install pgvector extension (using main branch for PostgreSQL 18 compatibility)
RUN cd /tmp && \
    git clone https://github.com/pgvector/pgvector.git && \
    cd pgvector && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/pgvector

# Install pg_textsearch extension
RUN cd /tmp && \
    git clone https://github.com/timescale/pg_textsearch.git && \
    cd pg_textsearch && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/pg_textsearch

# Create directories
RUN mkdir -p /docker-entrypoint-initdb.d

# Copy initialization scripts
COPY ./init-scripts/ /docker-entrypoint-initdb.d/

# Copy custom configuration
COPY ./conf/ /etc/postgresql/

# Expose PostgreSQL port
EXPOSE 5432

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD pg_isready -U postgres || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["postgres"]
