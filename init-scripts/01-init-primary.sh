#!/bin/bash
set -e

echo "Initializing Primary PostgreSQL instance..."

# Create replication user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create replication user
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
            CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD:-replicator_password}';
        END IF;
    END
    \$\$;

    -- Create replication slots
    SELECT pg_create_physical_replication_slot('replica_slot_1') 
    WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_slot_1');
    
    SELECT pg_create_physical_replication_slot('replica_slot_2') 
    WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_slot_2');
    
    SELECT pg_create_physical_replication_slot('replica_slot_3') 
    WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_slot_3');
EOSQL

# Configure pg_hba.conf for replication
cat >> "${PGDATA}/pg_hba.conf" <<EOF

# Replication connections
host    replication     replicator      0.0.0.0/0               scram-sha-256
host    replication     replicator      ::/0                    scram-sha-256
EOF

# Install extensions in default database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Install extensions
    CREATE EXTENSION IF NOT EXISTS vector;
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    
    -- Grant usage
    GRANT USAGE ON SCHEMA public TO replicator;
EOSQL

# Also install in template1 so new databases get the extensions
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "template1" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EOSQL

# Create archive directory
mkdir -p /var/lib/postgresql/archive
chown postgres:postgres /var/lib/postgresql/archive

echo "Primary PostgreSQL initialization complete."
