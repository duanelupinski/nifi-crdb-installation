# mssql-customers-table-to-cockroachdb

## Overview

This document captures the end-to-end setup, configuration, and troubleshooting steps used to build the NiFi process group **`mssql-customers-table-to-cockroachdb`**.

The process group migrates data from the SQL Server **Northwind** sample database table `dbo.Customers` into a CockroachDB target table `Customers`, using **Apache NiFi 1.26** running in Docker.

The final working design supports:

- Initial full load of the `Customers` table
- Ongoing inserts
- Ongoing updates

It does **not** support hard deletes in the final NiFi-only design.

---

## Background

The goal was to use Apache NiFi to move data from **Microsoft SQL Server** to **CockroachDB**, with support for inserts and updates during migration.

A key conclusion from the design process was:

- **NiFi alone is fine for initial load plus incremental inserts/updates**
- **NiFi alone is not enough for reliable hard delete propagation** unless the source system uses soft deletes or a CDC-based design is added

For this implementation, deletes were intentionally left out of scope.

The final process group was built specifically for the SQL Server `dbo.Customers` table from the **Northwind** sample database and a CockroachDB target table named `Customers`.

---

## Architecture

The final working flow is:

```text
[QueryDatabaseTableRecord] --> [PutDatabaseRecord]
```

Where:

- `QueryDatabaseTableRecord` reads from SQL Server
- `PutDatabaseRecord` writes into CockroachDB using `UPSERT`

The process group name used for this work is:

```text
mssql-customers-table-to-cockroachdb
```

---

## Final Working Design

### Source
- Database: Microsoft SQL Server
- Database name: `northwind`
- Table: `dbo.Customers`

### Destination
- Database: CockroachDB demo cluster/database used during testing
- Table: `Customers`

### Incremental sync strategy
The final and most reliable change-tracking approach discussed was to use a SQL Server `rowversion` column as the incremental watermark column.

Earlier iterations used `ModifiedAt`, but this had edge cases and ordering concerns. A `rowversion` column is a better fit for NiFi incremental polling.

---

## Prerequisites

Before building the flow, the following prerequisites were required.

### 1. Apache NiFi 1.26 running in Docker
NiFi was run using a Docker container.

Useful Docker commands:

```bash
docker ps
docker exec -it <container_name_or_id> /bin/bash
```

If `bash` is not available:

```bash
docker exec -it <container_name_or_id> /bin/sh
```

Typical NiFi logs location inside the container:

```bash
cd /opt/nifi/nifi-current/logs
tail -f nifi-app.log
```

### 2. JDBC drivers available inside NiFi
Two JDBC drivers are required:

- Microsoft SQL Server JDBC driver
- PostgreSQL JDBC driver

Because CockroachDB uses the PostgreSQL wire protocol, the PostgreSQL JDBC driver is used for the CockroachDB connection.

```bash
docker cp postgresql-42.7.8.jar nifi126:/opt/nifi/nifi-current/lib/
docker cp mssql-jdbc-13.4.0.jre11.jar nifi126:/opt/nifi/nifi-current/lib/
```

Verify with:
```bash
docker exec -it nifi126 ls -l /opt/nifi/nifi-current/lib | grep -E 'mssql|postgresql'
```

Restart nifi to pick up the new JDBC drivers in lib:
```bash
docker restart nifi126
```

### 3. SQL Server source table
The source table used was:

```sql
CREATE TABLE Customers (
    CustomerID nchar(5) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    CompanyName nvarchar(40) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    ContactName nvarchar(30) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    ContactTitle nvarchar(30) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Address nvarchar(60) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    City nvarchar(15) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Region nvarchar(15) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    PostalCode nvarchar(10) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Country nvarchar(15) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Phone nvarchar(24) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Fax nvarchar(24) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    CONSTRAINT PK_Customers PRIMARY KEY (CustomerID)
);
```

### 4. CockroachDB target table
A CockroachDB target table was created with the same column names.

The working target DDL used was:

```sql
CREATE TABLE Customers (
    CustomerID STRING NOT NULL CHECK (char_length(CustomerID) = 5),
    CompanyName STRING(40) NOT NULL,
    ContactName STRING(30),
    ContactTitle STRING(30),
    Address STRING(60),
    City STRING(15),
    Region STRING(15),
    PostalCode STRING(10),
    Country STRING(15),
    Phone STRING(24),
    Fax STRING(24),
    ModifiedAt TIMESTAMPTZ NOT NULL DEFAULT current_timestamp(),
    CONSTRAINT PK_Customers PRIMARY KEY (CustomerID)
);
```

> Note: `ModifiedAt` was originally added to support timestamp-based incremental polling.

Later, a `rowversion`-based approach was identified as a better incremental sync strategy.

### 5. SQL Server source-side change tracking columns
Two source-side approaches were discussed and tested.

#### Option A: `ModifiedAt`
A `ModifiedAt` column plus trigger was added:

```sql
ALTER TABLE dbo.Customers
ADD ModifiedAt datetime2(6) NOT NULL
    CONSTRAINT DF_Customers_ModifiedAt DEFAULT SYSUTCDATETIME();
GO

CREATE TRIGGER dbo.trg_Customers_ModifiedAt
ON dbo.Customers
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE c
    SET ModifiedAt = SYSUTCDATETIME()
    FROM dbo.Customers c
    INNER JOIN inserted i
        ON c.CustomerID = i.CustomerID;
END;
GO
```

#### Option B: `rowversion`
A better option for NiFi incremental polling is to add a SQL Server `rowversion` column:

```sql
ALTER TABLE dbo.Customers
ADD RowVer rowversion NOT NULL;
```

If `RowVer` is used, it should also be added to the `Columns to Return` property in `QueryDatabaseTableRecord`, and it should become the sole `Maximum-value Columns` entry.

---

## NiFi 1.26 Docker Setup Notes

The following operational tasks were needed to make the NiFi Docker container usable for this workflow:

1. Start the container
2. Confirm the container is running:
   ```bash
   docker ps
   ```
3. Enter the container:
   ```bash
   docker exec -it <container_name_or_id> /bin/bash
   ```
4. Check NiFi logs:
   ```bash
   cd /opt/nifi/nifi-current/logs
   tail -f nifi-app.log
   ```
5. Ensure both JDBC driver jars are available to NiFi
6. Restart or reload NiFi if necessary after placing drivers

---

## NiFi Controller Services

The process group required the following controller services.

### 1. SQL Server source connection pool
Service type:

```text
DBCPConnectionPool
```

Properties:

```text
Database Connection URL = jdbc:sqlserver://<sqlserver-host>:1433;databaseName=northwind;encrypt=true;trustServerCertificate=true
Database Driver Class Name = com.microsoft.sqlserver.jdbc.SQLServerDriver
Database User = <sqlserver_user>
Password = <sqlserver_password>
```

### 2. CockroachDB target connection pool
Service type:

```text
DBCPConnectionPool
```

Properties:

```text
Database Connection URL = jdbc:postgresql://<cockroach-host>:26257/<target_db>?sslmode=require
Database Driver Class Name = org.postgresql.Driver
Database User = <cockroach_user>
Password = <cockroach_password>
```

### 3. Record writer / reader
The final working solution used **Avro** between processors because JSON caused timestamp typing problems.

Recommended services:

- `AvroRecordSetWriter`
- `AvroReader`

This was a critical workaround.

---

## Initial NiFi Flow Design

The original intended flow was:

```text
QueryDatabaseTableRecord -> PutDatabaseRecord
```

Using:

- `QueryDatabaseTableRecord` to read SQL Server rows incrementally
- `PutDatabaseRecord` with `UPSERT` to write into CockroachDB

This basic design remained correct throughout the work.

---

## Final Processor Configuration

## Processor 1: QueryDatabaseTableRecord

Suggested processor name:

```text
Poll SQLServer Customers
```

### Final configuration concept
The final stable direction was:

```text
Table Name = dbo.Customers
Columns to Return = CustomerID,CompanyName,ContactName,ContactTitle,Address,City,Region,PostalCode,Country,Phone,Fax,ModifiedAt,RowVer
Maximum-value Columns = RowVer
Record Writer = AvroRecordSetWriter
Initial Load Strategy = Start at Beginning
Fetch Size = 1000
Max Rows Per Flow File = 1000
Output Batch Size = 100
Run Schedule = 30 sec
Execution = Primary node
```

### Earlier timestamp-based configuration
Before switching to `RowVer`, the processor used:

```text
Columns to Return = CustomerID,CompanyName,ContactName,ContactTitle,Address,City,Region,PostalCode,Country,Phone,Fax,ModifiedAt
Maximum-value Columns = ModifiedAt
```

There was also an intermediate configuration attempt using:

```text
Maximum-value Columns = ModifiedAt,CustomerID
```

This turned out to be a poor fit because `CustomerID` is static for existing rows and does not satisfy the intended hierarchical ordering behavior for multi-column maximum-value tracking.

## Processor 2: PutDatabaseRecord

Suggested processor name:

```text
Upsert Customers to Cockroach
```

Properties:

```text
DBCPService = CockroachDBPool
Table Name = Customers
Record Reader = AvroReader
Statement Type = UPSERT
Translate Field Names = false
Unmatched Field Behavior = Ignore Unmatched Fields
Unmatched Column Behavior = Warn on Unmatched Columns
Quote Table Identifiers = true
Quote Column Identifiers = true
```

> Important: The target table name should be `Customers` or `public.Customers`, not a SQL Server-style three-part name like `northwind.dbo.customers`.

---

## Relationships

### QueryDatabaseTableRecord
In NiFi 1.26, `QueryDatabaseTableRecord` exposes only:

```text
success
```

It does **not** have a `failure` relationship.

### PutDatabaseRecord
`PutDatabaseRecord` exposes:

- `success`
- `retry`
- `failure`

Recommended wiring:

```text
[QueryDatabaseTableRecord] --success--> [PutDatabaseRecord]
```

Optional retry/failure handling:

- `PutDatabaseRecord.retry` -> retry queue -> back to `PutDatabaseRecord`
- `PutDatabaseRecord.failure` -> dead-letter queue

---

## Common Operational Notes

### Clearing queues is not enough
`QueryDatabaseTableRecord` retains watermark values in **processor state**.

If you want it to reread from the beginning, you must:

1. Stop the processor
2. Open **View state**
3. Click **Clear State**
4. Restart the processor

This was necessary when retrying the full load after configuration changes.

### Why nothing was emitted after restart
After clearing queues and restarting, no new rows were emitted because the processor still had remembered max-value state. Clearing the state fixed this.

---

## Troubleshooting Journey

This section captures the key troubleshooting milestones and workarounds.

### Issue 1: No `failure` relationship on `QueryDatabaseTableRecord`
At one point it appeared that a failure queue should be wired from `QueryDatabaseTableRecord`, but NiFi 1.26 exposes only `success`.

Resolution:
- Use processor bulletins and NiFi logs for source-side failures
- Use `nifi-app.log` inside the container for detailed errors

Useful log commands:

```bash
tail -f /opt/nifi/nifi-current/logs/nifi-app.log
grep -i "QueryDatabaseTableRecord" /opt/nifi/nifi-current/logs/nifi-app.log
grep -i "PutDatabaseRecord" /opt/nifi/nifi-current/logs/nifi-app.log
```

### Issue 2: Timestamp parse failures in CockroachDB
This was the main technical blocker.

Error example:

```text
ERROR: parsing as type timestamp: field month value 91 is out of range
```

The failing SQL showed values like:

```text
'1774552109104'
```

for the `ModifiedAt` field.

#### Root cause
`ModifiedAt` was being serialized through the JSON record path as an epoch-milliseconds value and ultimately passed into CockroachDB as a string rather than a real timestamp.

Example queued content:

```json
"ModifiedAt" : "1774552109104"
```

#### Failed workaround attempts
Several JSON-based fixes were attempted:

- setting `Timestamp Format` on `JsonRecordSetWriter`
- setting `Timestamp Format` on `JsonTreeReader`
- trying schema inference with JSON
- trying explicit schema ideas with JSON

These did not fully solve the issue in the active flow.

#### Final workaround that fixed it
Switch the internal handoff from JSON to **Avro**:

- `QueryDatabaseTableRecord` -> `AvroRecordSetWriter`
- `PutDatabaseRecord` -> `AvroReader`

This preserved the timestamp type correctly and resolved the parse error.

### Issue 3: Updates not propagating when using `ModifiedAt,CustomerID`
At one point, the processor was configured with:

```text
Maximum-value Columns = ModifiedAt,CustomerID
```

A row update in SQL Server changed the business column and `ModifiedAt`, but the update did not propagate.

#### Likely cause
The multi-column maximum-value setup was not a good fit because `CustomerID` is static and not a naturally increasing secondary key for update tracking.

#### Workaround
Use only:

```text
Maximum-value Columns = ModifiedAt
```

or preferably switch to:

```text
Maximum-value Columns = RowVer
```

---

## Testing Steps

### Initial full load
1. Clear processor state
2. Ensure target table exists
3. Start `PutDatabaseRecord`
4. Start `QueryDatabaseTableRecord`
5. Confirm all source rows appear in CockroachDB

### Update propagation test using `ModifiedAt`
An update test used:

```sql
UPDATE dbo.Customers
SET ContactName = 'Maria Anders Updated'
WHERE CustomerID = 'ALFKI';
```

It was also confirmed that `ModifiedAt` changed in SQL Server.

This exposed issues with the multi-column max-value configuration.

### Recommended update propagation test using `RowVer`
After adding `RowVer` and switching the max-value configuration:

```sql
UPDATE dbo.Customers
SET ContactName = 'Maria Anders Updated'
WHERE CustomerID = 'ALFKI';
```

Expected behavior:
- SQL Server updates the row
- `RowVer` changes automatically
- `QueryDatabaseTableRecord` sees the new `RowVer`
- `PutDatabaseRecord` performs an UPSERT into CockroachDB

---

## Final Recommendations

### Recommended final source-side strategy
Use SQL Server `rowversion` for incremental polling:

```sql
ALTER TABLE dbo.Customers
ADD RowVer rowversion NOT NULL;
```

### Recommended final `QueryDatabaseTableRecord` settings
```text
Columns to Return = CustomerID,CompanyName,ContactName,ContactTitle,Address,City,Region,PostalCode,Country,Phone,Fax,ModifiedAt,RowVer
Maximum-value Columns = RowVer
Record Writer = AvroRecordSetWriter
```

### Recommended final `PutDatabaseRecord` settings
```text
Table Name = Customers
Record Reader = AvroReader
Statement Type = UPSERT
Unmatched Field Behavior = Ignore Unmatched Fields
```

### Recommended internal record transport
Use **Avro**, not JSON, between processors whenever timestamp/date typing matters.

---

## Limitations

This implementation does **not** handle:

- hard deletes
- source-side CDC
- PK changes
- complex SQL Server feature translation beyond the simple `Customers` table

If delete support is required, a CDC-based design such as SQL Server CDC + Debezium + Kafka + NiFi would be more appropriate.

---
