#!/bin/bash
set -e

PRIMARY_HOST="${PRIMARY_HOST:-postgres-primary}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"
REPLICATION_USER="${REPLICATION_USER:-replicator}"
REPLICATION_PASSWORD="${REPLICATION_PASSWORD:-replicator_password}"
REPLICA_SLOT="${REPLICA_SLOT:-replica_slot_1}"

echo "Initializing PostgreSQL Replica..."

# Wait for primary
until PGPASSWORD="${REPLICATION_PASSWORD}" psql -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U "${REPLICATION_USER}" -c '\q' 2>/dev/null; do
    echo "Waiting for primary..."
    sleep 2
done

echo "Primary ready. Starting base backup..."

# Check if already initialized
if [ -f "${PGDATA}/standby.signal" ]; then
    echo "Replica already initialized."
    exit 0
fi

# Clean data directory
if [ -d "${PGDATA}" ] && [ "$(ls -A ${PGDATA})" ]; then
    rm -rf "${PGDATA}"/*
fi

# Perform base backup
PGPASSWORD="${REPLICATION_PASSWORD}" pg_basebackup \
    -h "${PRIMARY_HOST}" \
    -p "${PRIMARY_PORT}" \
    -U "${REPLICATION_USER}" \
    -D "${PGDATA}" \
    -P \
    -Xs \
    -c fast \
    -R \
    -S "${REPLICA_SLOT}"

# Create standby signal
touch "${PGDATA}/standby.signal"

# Update connection info
cat >> "${PGDATA}/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=${PRIMARY_HOST} port=${PRIMARY_PORT} user=${REPLICATION_USER} password=${REPLICATION_PASSWORD} application_name=${HOSTNAME}'
primary_slot_name = '${REPLICA_SLOT}'
EOF

echo "Replica initialization complete."
