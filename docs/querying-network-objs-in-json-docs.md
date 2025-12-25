# Querying Network Objects in JSON Docs

PostgreSQL has powerful JSON functions that you can combine with network functions to work with IP addresses stored in JSON. Here's how:

**Basic approach - extract and cast:**

```sql
-- Extract IP from JSON and cast to inet type
SELECT 
    data->>'ip_address' AS ip_text,
    (data->>'ip_address')::inet AS ip_inet
FROM logs;

-- Compare IPs in JSON
SELECT *
FROM logs
WHERE (data->>'ip_address')::inet << '192.168.1.0/24'::inet;  -- IP in subnet
```

**Common network operations on JSON IPs:**

```sql
-- Check if IP is in a subnet
SELECT *
FROM events
WHERE (metadata->>'client_ip')::inet << '10.0.0.0/8'::inet;

-- Compare two IPs from JSON
SELECT *
FROM connections
WHERE (data->>'source_ip')::inet = (data->>'dest_ip')::inet;

-- Get network mask
SELECT 
    netmask((data->>'ip')::inet) AS mask,
    broadcast((data->>'ip')::inet) AS broadcast,
    host((data->>'ip')::inet) AS host_only
FROM network_data;

-- Find IPs in a specific range
SELECT *
FROM access_logs
WHERE (log_data->>'ip')::inet BETWEEN '192.168.1.1'::inet AND '192.168.1.255'::inet;
```

**Using JSONB path expressions (Postgres 12+):**

```sql
-- Extract and cast in one operation
SELECT *
FROM logs
WHERE jsonb_path_query_first(data, '$.ip_address')::text::inet << '172.16.0.0/12'::inet;
```

**Create an index for better performance:**

```sql
-- Create expression index for frequent queries
CREATE INDEX idx_json_ip ON logs (((data->>'ip_address')::inet));

-- Use GiST index for subnet operations
CREATE INDEX idx_json_ip_gist ON logs USING gist (((data->>'ip_address')::inet inet_ops));
```

**Practical example - filter by multiple conditions:**

```sql
SELECT 
    data->>'user_id' AS user,
    data->>'ip_address' AS ip,
    created_at
FROM audit_logs
WHERE 
    (data->>'ip_address')::inet << '10.0.0.0/8'::inet  -- Private IP
    AND data->>'action' = 'login'
    AND created_at > NOW() - INTERVAL '1 day';
```

The key is using the `::inet` cast to convert the JSON string to PostgreSQL's network type, which then gives you access to all the network operators (`<<`, `>>=`, `&&`, etc.) and functions (`netmask()`, `broadcast()`, `host()`, etc.).

## IP Addresses in a JSON Array

When IP addresses are in a JSON array, you need to use JSON array functions. Here are several approaches:

**Using `jsonb_array_elements_text()` to unnest the array:**

```sql
-- Find rows where ANY IP in the array matches a subnet
SELECT DISTINCT logs.*
FROM logs,
     jsonb_array_elements_text(data->'ip_addresses') AS ip
WHERE ip::inet << '192.168.1.0/24'::inet;

-- Get all IPs from the array with their parent rows
SELECT 
    logs.id,
    ip::inet AS ip_address
FROM logs,
     jsonb_array_elements_text(data->'ip_addresses') AS ip;
```

**Check if specific IP exists in array:**

```sql
-- Check if a specific IP is in the JSON array
SELECT *
FROM logs
WHERE data->'ip_addresses' @> '"192.168.1.100"'::jsonb;

-- Using ANY with array conversion
SELECT *
FROM logs
WHERE '10.0.0.5'::inet = ANY(
    SELECT (jsonb_array_elements_text(data->'ip_addresses'))::inet
);
```

**Filter by subnet membership:**

```sql
-- Find rows where at least one IP is in a subnet
SELECT *
FROM logs
WHERE EXISTS (
    SELECT 1
    FROM jsonb_array_elements_text(data->'ip_addresses') AS ip
    WHERE ip::inet << '10.0.0.0/8'::inet
);
```

**Count matching IPs in array:**

```sql
-- Count how many IPs in each array are in a subnet
SELECT 
    id,
    data->'ip_addresses' AS all_ips,
    COUNT(*) FILTER (WHERE ip::inet << '192.168.0.0/16'::inet) AS matching_ips
FROM logs,
     jsonb_array_elements_text(data->'ip_addresses') AS ip
GROUP BY id, data->'ip_addresses';
```

**Using aggregate to collect results:**

```sql
-- Get all private IPs from the array
SELECT 
    id,
    jsonb_agg(ip) AS private_ips
FROM logs,
     jsonb_array_elements_text(data->'ip_addresses') AS ip
WHERE ip::inet << ANY(ARRAY['10.0.0.0/8'::inet, '172.16.0.0/12'::inet, '192.168.0.0/16'::inet])
GROUP BY id;
```

**Create a functional index:**

```sql
-- Index for queries that check array membership
CREATE INDEX idx_json_ip_array ON logs 
USING gin ((data->'ip_addresses'));

-- Or create an index on the unnested IPs
CREATE INDEX idx_json_ip_array_elements ON logs 
USING gist (((
    SELECT array_agg(elem::inet)
    FROM jsonb_array_elements_text(data->'ip_addresses') elem
)));
```

**Practical example - find overlapping subnets:**

```sql
-- Find logs where any IP overlaps with a list of subnets
SELECT DISTINCT logs.*
FROM logs,
     jsonb_array_elements_text(data->'ip_addresses') AS ip
WHERE ip::inet && ANY(ARRAY[
    '10.0.0.0/8'::inet,
    '172.16.0.0/12'::inet,
    '192.168.0.0/16'::inet
]);
```

**Example data structure:**

```sql
-- Sample data
INSERT INTO logs (data) VALUES 
('{"ip_addresses": ["192.168.1.5", "10.0.0.1", "8.8.8.8"]}'::jsonb),
('{"ip_addresses": ["172.16.0.5", "192.168.2.10"]}'::jsonb);
```

The key function is `jsonb_array_elements_text()` which expands the JSON array into rows, allowing you to apply `::inet` casting and network operators to each element.