# PostgreSQL Cluster with pg_textsearch and pgvector

This is an OCI-compliant PostgreSQL cluster setup with streaming replication, featuring one primary (write) instance and multiple replica (read-only) instances.

## Features

- **PostgreSQL 16** with streaming replication
- **pgvector** extension for vector similarity search
- **pg_textsearch** extension for advanced text search
- One primary (write) instance
- Two replica (read-only) instances (easily scalable to more)
- Automatic replication using physical replication slots
- PgBouncer for connection pooling
- Health checks for all instances
- OCI-compliant container images

## Architecture

```
┌─────────────────┐
│   Application   │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼───┐ ┌───▼─────┐
│ Write │ │  Reads  │
│       │ │         │
│Primary├─┤Replica 1│
│ :5432 │ │  :5433  │
└───────┘ │         │
          │Replica 2│
          │  :5434  │
          └─────────┘
```

## Directory Structure

```
.
├── Dockerfile                          # OCI-compliant image definition
├── docker-compose.yml                  # Docker Compose configuration
├── podman-compose.yml                  # Podman Compose configuration
├── .env                                # Environment variables
├── conf/
│   ├── postgresql-primary.conf        # Primary instance config
│   └── postgresql-replica.conf        # Replica instance config
└── init-scripts/
    ├── 01-init-primary.sh             # Primary initialization
    └── init-replica.sh                # Replica initialization
```

## Quick Start

### Prerequisites

- Docker or Podman installed
- Docker Compose or Podman Compose installed

### Setup

1. **Create the directory structure**:

```bash
mkdir -p postgres-cluster/{conf,init-scripts}
cd postgres-cluster
```

2. **Create all configuration files** (use the artifacts provided)

3. **Configure environment variables**:

```bash
cp .env.example .env
# Edit .env and set secure passwords
nano .env
```

4. **Build and start the cluster**:

**Using Docker:**
```bash
docker-compose up -d
```

**Using Podman:**
```bash
podman-compose up -d
```

## Connecting to the Cluster

### Primary (Write) Instance
```bash
psql -h localhost -p 5432 -U postgres -d mydb
```

### Replica 1 (Read-Only)
```bash
psql -h localhost -p 5433 -U postgres -d mydb
```

### Replica 2 (Read-Only)
```bash
psql -h localhost -p 5434 -U postgres -d mydb
```

### Via PgBouncer (Connection Pooling)
```bash
psql -h localhost -p 6432 -U postgres -d mydb
```

## Verifying Replication

Connect to the primary and check replication status:

```sql
-- Check replication slots
SELECT * FROM pg_replication_slots;

-- Check active replicas
SELECT * FROM pg_stat_replication;
```

Connect to a replica and verify it's in recovery mode:

```sql
-- Should return 't' (true)
SELECT pg_is_in_recovery();
```

## Testing the Extensions

### pgvector Example

```sql
-- Create a table with vector column
CREATE TABLE items (
    id SERIAL PRIMARY KEY,
    embedding vector(3)
);

-- Insert some vectors
INSERT INTO items (embedding) VALUES 
    ('[1,2,3]'),
    ('[4,5,6]'),
    ('[7,8,9]');

-- Find similar vectors
SELECT * FROM items 
ORDER BY embedding <-> '[3,1,2]' 
LIMIT 3;
```

### pg_textsearch Example

```sql
-- Create a table for text search
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    title TEXT,
    content TEXT,
    search_vector tsvector
);

-- Insert sample data
INSERT INTO documents (title, content) VALUES
    ('PostgreSQL Tutorial', 'Learn PostgreSQL database management'),
    ('Vector Search Guide', 'How to use pgvector for similarity search');

-- Create search index
CREATE INDEX idx_search ON documents USING GIN(search_vector);

-- Perform text search
SELECT * FROM documents 
WHERE search_vector @@ to_tsquery('postgresql & database');
```

## Scaling

To add more replicas:

1. **Update docker-compose.yml** with a new replica service:

```yaml
postgres-replica-3:
  # Copy postgres-replica-2 configuration
  # Change container_name, hostname, port, and REPLICA_SLOT
  ports:
    - "5435:5432"
  environment:
    REPLICA_SLOT: replica_slot_3
```

2. **Create additional replication slot** on primary:

```sql
SELECT pg_create_physical_replication_slot('replica_slot_3');
```

3. **Restart the cluster**:

```bash
docker-compose up -d postgres-replica-3
```

## Maintenance

### Backup

**Primary database backup**:
```bash
docker exec postgres-primary pg_dump -U postgres mydb > backup.sql
```

**Full cluster backup**:
```bash
docker exec postgres-primary pg_basebackup -D /backup -F tar -z -P
```

### Monitoring

**Check disk usage**:
```bash
docker exec postgres-primary df -h /var/lib/postgresql/data
```

**View logs**:
```bash
docker logs postgres-primary
docker logs postgres-replica-1
```

**Monitor replication lag**:
```sql
SELECT 
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replication_lag_bytes
FROM pg_stat_replication;
```

## Troubleshooting

### Replica not syncing

1. **Check primary logs**:
```bash
docker logs postgres-primary
```

2. **Verify replication user**:
```bash
docker exec -it postgres-primary psql -U postgres -c "\du replicator"
```

3. **Check network connectivity**:
```bash
docker exec postgres-replica-1 pg_isready -h postgres-primary -p 5432
```

### Promoting a replica to primary

If the primary fails, promote a replica:

```bash
docker exec postgres-replica-1 pg_ctl promote -D /var/lib/postgresql/data/pgdata
```

## Security Considerations

1. **Change default passwords** in `.env` file
2. **Use SSL/TLS** for production (configure in postgresql.conf)
3. **Restrict network access** using firewall rules
4. **Enable audit logging** for compliance requirements
5. **Regular security updates** of base images

## Performance Tuning

Adjust these settings in `postgresql-primary.conf` and `postgresql-replica.conf` based on your hardware:

- `shared_buffers`: 25% of RAM
- `effective_cache_size`: 50-75% of RAM
- `work_mem`: RAM / max_connections / 16
- `maintenance_work_mem`: RAM / 16

## License

This configuration is provided as-is for use with PostgreSQL and its extensions under their respective licenses.
