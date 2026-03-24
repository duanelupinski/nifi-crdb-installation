# Schema Conversion Strategies

1. [Overview](#overview)
1. [Entity Strategies](#entity-strategies)
1. [Sub-document Strategies](#sub-document-strategies)
1. [Array Strategies](#array-strategies)
1. [Choosing Strategies](#choosing-strategies)
1. [Performance Trade-offs](#performance-trade-offs)



## Overview
...Collections, Sub-Documents, and Arrays, Oh My...

This document provides guidance for converting semi-structured or document-oriented data models into a relational schema. It outlines the major strategies available for mapping entity collections, sub-documents, and arrays into SQL tables, and provides a comparison matrix and decision tree to help select the right approach for a given workload.

Document-to-relational schema conversion involves balancing flexibility, performance, and correctness. The key principles are:
- **JSONB is optimal for flexibility and write throughput**, but offers weaker query performance and integrity.
- **Columnized fields offer the best read performance for known hot paths**, leveraging CockroachDB’s indexing and range distribution.
- **Normalization provides the strongest correctness and analytical capabilities**, at the cost of write complexity and more joins.
- **Arrays should be modeled relationally when queryable**, and stored as JSONB when small and mostly passive.
- CockroachDB’s architecture amplifies these trade-offs:
  - Wide rows → higher MVCC cost
  - Many small tables → more KV ops but better sharding
  - JSONB → CPU-heavy filtering
  - Normalization → more distributed joins

The recommended lifecycle is:
1. **Start flexible** (jsonb, jsonb arrays) to ingest quickly.
1. **Observe real query patterns**.
1. **Promote hot fields** to columnized or normalized structures.
1. **Normalize deeply** only when correctness or analytical needs justify it.

This approach gives you the best blend of ingestion speed today and long-term performance as your relational workload matures.

The goal is to balance **ingestion speed**, **query performance**, **schema evolution**, **data integrity**, and **storage efficiency** depending on the nature of each field or collection.

When converting schemaless or semi-structured data into a relational schema, the DDL generation tool lets you control how each subtree and array is mapped.

You configure behavior via:
- **Global defaults** in schemaConversion
- **Per-collection overrides** (e.g., per source collection/table)
- **Per-path overrides** (e.g., order.items, customer.addresses[0], etc.)

This gives you fine-grained control over the trade-off between:
- Ingest simplicity
- Query performance
- Schema evolution
- Referential/constraint integrity
- Storage footprint and index complexity

Below we summarize the main strategies.



## Entity Strategies
When converting an entire collection or document type, the schema may be:
| Strategy                          | Description                                                                                   |
| --------------------------------- | --------------------------------------------------------------------------------------------- |
| **Flat (all columns)**            | Convert all fields into columns on a single table. Simple, but can become wide.               |
| **Partially normalized**          | Move logically distinct components into separate tables with foreign keys.                    |
| **Payload-oriented (jsonb root)** | Store most or all of the source document in a JSONB column, with only a few extracted fields. |

### Comparison Matrix
| Dimension         | **Flat**                        | **Partially Normalized**       | **Payload-Oriented (jsonb)**          |
| ----------------- | ------------------------------- | ------------------------------ | ------------------------------------- |
| Schema Complexity | Moderate–High                   | High                           | Lowest                                |
| Query Performance | Good but can degrade with width | **Excellent**                  | Good for top-level fields only        |
| Ingestion Speed   | Moderate                        | Slowest                        | **Fastest**                           |
| Schema Evolution  | ALTER TABLE required            | Complex multi-table migrations | **Most flexible**                     |
| Data Integrity    | Limited by denormalization      | **Strongest**                  | Weak                                  |
| Best For          | Stable schemas, OLTP tables     | Strong relational domains      | Event/log ingestion, evolving schemas |



## Sub-document Strategies
Sub-documents (nested objects) are the most common point of divergence between document stores and relational systems. Three broad approaches exist:
| Strategy      | Description                                                                                       |
| ------------- | ------------------------------------------------------------------------------------------------- |
| **jsonb**     | Store the entire subtree as a JSONB column. Minimal schema overhead; high flexibility.            |
| **columnize** | Extract specific nested fields into physical SQL columns for faster querying.                     |
| **normalize** | Create one or more child tables representing the sub-document as first-class relational entities. |

### Comparison Matrix
| Dimension               | **jsonb**                          | **columnize**                         | **normalize**                                                 |
| ----------------------- | ---------------------------------- | ------------------------------------- | ------------------------------------------------------------- |
| Schema Complexity       | Lowest                             | Moderate                              | Highest                                                       |
| Ingestion Speed         | **Fastest**                        | Slightly slower                       | Slowest                                                       |
| Schema Evolution        | **Most flexible**                  | Requires ALTER TABLE                  | Requires relational migrations                                |
| Query Performance       | Weak–Moderate                      | **Strong**                            | **Strongest**                                                 |
| Integrity & Constraints | Limited                            | Good                                  | **Full relational integrity**                                 |
| Storage Behavior        | Single column; can grow large      | Wider parent table                    | Normalized storage; more rows                                 |
| Best For                | Schemas in flux, payload retention | Hot fields frequently used in queries | Clean relational modeling, large sub-docs, strong constraints |

<details>
<summary>expand for more info...</summary>

### 1. jsonb: Store Subtree as JSONB
**What it does**
- Keeps the entire nested object as a single JSONB column on the parent row.
- No additional tables or columns are created for that subtree.

**When it’s a good fit**
- Rapid ingestion where schema is still in flux.
- Low-to-moderate query volume on the nested fields.
- “Log-style” or “event-style” data where most queries filter on a few top-level fields and only occasionally drill into the nested content.
- Prototyping phases where you don’t yet know which fields matter.

**Pros**
- **Fast ingestion & simple DDL**
  - Minimal schema surface: 1 extra JSONB column.
  - Great for streaming workloads or frequent schema changes.
- **Flexible schema evolution**
  - New fields can appear in the JSON without schema migrations.
  - Backward/forward compatibility is easy.
- **Payload fidelity**
  - You keep the original structure intact; no lossy flattening.

**Cons**
- **Weaker constraints**
  - Hard or impossible to enforce strong constraints (FKs, NOT NULL, etc.) on individual nested fields.
  - Validation tends to move into app logic or ingestion pipelines.
- **Potentially slower queries**
  - JSONB indexes help, but complex predicates or joins on nested fields can be more expensive than on native columns.
- **Harder to analyze at scale**
  - Aggregations across deeply nested JSON fields get complex and slow if used heavily.

### 2. columnize: Denormalized Columns on Parent
**What it does**
- Projects selected nested fields into physical columns on the parent table.
- You still store the full source (optionally as JSONB), but key fields become first-class columns.

**When it’s a good fit**
- High-read / analytical workloads on a small set of predictable fields.
- You want **constraints** and **indexes** on those fields (e.g., unique keys, secondary indexes).
- You’re OK with a wider row as long as it makes queries simpler and faster.

**Pros**
- **Fast queries on selected fields**
  - Native columns are ideal for filters, joins, and aggregates.
  - Use normal B-tree indexes and constraints.
- **Better ergonomics for SQL users**
  - Simpler queries (SELECT price, sku FROM product) instead of JSON extraction expressions.
- **Good middle ground**
  - You can still retain the full document in JSONB, but optimize the “hot” fields.

**Cons**
- **Schema coupling**
  - Adding/removing fields requires DDL changes (ALTER TABLE).
  - You reintroduce schema evolution overhead.
- **Wider tables**
  - At scale, too many columns can hurt cache behavior or complicate tooling.
  - Can be awkward when many fields are sparsely populated.
- **Partial fidelity**
  - If you don’t also keep the full JSON, you lose arbitrary fields.

### 3. normalize: Child Tables per Sub-document
**What it does**
- Splits nested structures into **separate tables** with FOREIGN KEY references back to the parent.
- Each child table holds fields that logically belong together; can be one-to-one or one-to-many.

**When it’s a good fit**
- Strong relational modeling requirements (3NF-style).
- You want **referential integrity**, **clean joins**, and **independent indexing** of sub-entities.
- Sub-documents are reused across contexts or have their own lifecycle (e.g., addresses, line_items, payments).

**Pros**
- **True relational modeling**
  - Natural support for joins, constraints, and normalization.
  - Easier to reason about data quality and invariants.
- **Scalable indexing**
  - You can index the child table independently of the parent.
  - Good for large one-to-many sets (e.g., many line items per order).
- **Better for shared sub-entities**
  - If a sub-document is shared (e.g., customer referenced from many collections), normalization reduces duplication.

**Cons**
- **Complex DDL and queries**
  - More tables, more foreign keys, more joins.
  - Heavier mental model for users.
- **Ingestion cost**
  - Each nested structure becomes extra inserts/updates.
  - More round-trips or larger batches depending on your pipeline.
- **Migration overhead**
  - Changing structure later can be quite involved.
</details>



## Array Strategies
Arrays can represent value lists, sub-entity collections, or references. Three strategies are typically used:
| Strategy           | Description                                         |
| ------------------ | --------------------------------------------------- |
| **child_table**    | One-to-many child table, one row per array element. |
| **junction_table** | Many-to-many table for arrays of references or IDs. |
| **jsonb array**    | Store the full array as JSONB on the parent row.    |

### Comparison Matrix
| Dimension               | **child_table**              | **junction_table**       | **jsonb array**                    |
| ----------------------- | ---------------------------- | ------------------------ | ---------------------------------- |
| Schema Complexity       | Moderate                     | Highest                  | Lowest                             |
| Ingestion Cost          | Moderate                     | High                     | **Lowest**                         |
| Querying Elements       | **Excellent**                | **Excellent**            | Weak                               |
| Constraints & Integrity | Good for element-level rules | **Strongest**            | Weak                               |
| Handling Large Arrays   | Scales very well             | Scales well              | Poor                               |
| Best For                | Arrays of embedded objects   | Arrays of references/IDs | Small arrays, infrequent filtering |

<details>
<summary>expand for more info...</summary>

### 1. child_table: One-to-many Child Table
**What it does**
- Creates a separate table with:
  - An FK to the parent
  - Columns for each element field (if element is complex, this may use jsonb or its own sub-structure)

**When it’s a good fit**
- Arrays of **embedded value objects** (line items, measurements, history events).
- You need expressive queries and constraints on individual elements.
- Arrays can grow large and should not bloat the parent row.

**Pros**
- **Scalable arrays**
  - Large arrays don’t blow up the parent row size.
- **Rich constraints on elements**
  - Enforce uniqueness or other constraints across elements per parent.
- **Good join performance**
  - Straightforward relational joins from parent to children.

**Cons**
- **More tables and joins**
  - Every array becomes at least one more table.
- **Higher ingest complexity**
  - Need to manage ordering, batching, and referential inserts.
- **Potential fragmentation**
  - Very small child rows can cause overhead if not batched.

### 2. junction_table: Normalized Mapping Table for References
**What it does**
- Creates a classic **many-to-many** junction table:
  - parent_id (FK)
  - target_id (FK to referenced entity)
  - Optional attributes (e.g., rank/order, metadata)

**When it’s a good fit**
- Arrays of **IDs or references** (e.g., tags, related products, user roles).
- You want to deduplicate the referenced entities and maintain referential integrity.

**Pros**
- **Canonical relational modeling**
  - Ideal for many-to-many relationships.
- **Data deduplication**
  - Single row per referenced entity; shared across parents.
- **Good querying on relationships**
  - Easy to find all parents for a given child or vice versa.

**Cons**
- **Extra join layer**
  - Queries often require two joins: parent → junction → referenced.
- **Ingestion logic**
  - Need to ensure referenced entities exist and handle upserts.

### 3. jsonb Array: Keep Arrays in JSONB
**What it does**
- Stores the entire array (of scalars or objects) as a JSONB array on the parent row.

**When it’s a good fit**
- Arrays are **small**, **accessed infrequently**, or mostly used as payloads.
- You rarely filter or join on individual elements.
- You are prioritizing ingestion speed and model simplicity.

**Pros**
- **Minimum schema footprint**
  - No extra tables or FKs.
- **Fast ingestion**
  - Just write the array as-is.
- **Great for “bag of attributes”**
  - Tags, flags, small lists where you occasionally inspect contents.

**Cons**
- **Limited relational power**
  - Queries that need to treat elements as rows are awkward and slower.
  - Hard to enforce invariants across elements.
- **Indexing complexity**
  - JSONB GIN indexes help, but they’re more opaque & heavier than simple B-tree indexes.
</details>



## Choosing Strategies
| Goal                               | Recommended Strategy                             |
| ---------------------------------- | ------------------------------------------------ |
| **Fastest ingestion**              | jsonb (sub-docs, payloads, and arrays)           |
| **Best query performance**         | columnize (hot fields), or normalize/child_table |
| **Strongest constraints**          | normalize + junction_table                       |
| **Most flexible schema evolution** | jsonb everywhere                                 |
| **Best for large arrays**          | child_table                                      |
| **Best for reference arrays**      | junction_table                                   |

The following decision trees provide practical guidance for selecting a strategy for each field, object, or array.

### 1. Entities (Collections)
- **Does the collection represent a well-structured, stable relational domain?**
  - **Yes** → Use **flat** or **partially normalized**, depending on complexity

- **Is schema evolving quickly or driven by semi-structured payloads?**
  - **Yes** → Use **payload-oriented jsonb root**

- **Does part of the entity warrant normalization (e.g., addresses, items, attributes)?**
  - **Yes** → Use **partially normalized** design

### 2. Sub-Documents (Nested Objects)
- **Do you need relational integrity, constraints, or independent indexing?**
  - **Yes** → Choose **normalize**
  - **No** → Continue

- **Are specific nested fields frequently used in filters/joins?**
  - **Yes** → Choose **columnize**
  - **No** → Continue

- **Is schema evolution uncertain or rapid?**
  - **Yes** → Choose **jsonb**
  - **No** → Choose **columnize** (simpler queries)

### 3. Arrays
- **Are array elements references/IDs pointing to other entities?**
  - **Yes** → Choose **junction_table**

- **Are array elements embedded objects with structure?**
  - **Yes** → Choose **child_table**

- **Are arrays small, infrequently queried, and mostly consumed as payload?**
  - **Yes** → Choose **jsonb array**

### 4. Guiding Principles
You can also combine strategies by using global defaults and then overriding per collection/path. Some practical guidelines:
- Start with flexible (**jsonb**) strategies early in schema discovery.
  - Good for initial migrations and when schemas are still moving.
  - Keep ingestion simple, then harden specific paths later.
- Promote high-value paths to **columnize** once query patterns emerge.
  - You see recurring filters/joins on a nested field.
  - You want constraints or performance guarantees.
- Migrate complex or relational substructures to **normalize** for long-term maintainability.
  - Sub-documents or arrays represent real entities or relationships.
  - You need referential integrity, independent lifecycle, or many-to-many modeling.
  - Arrays can grow large and need to be first-class citizen tables, in which case choose child_table for value objects, junction_table for references.
- Keep **arrays** as JSONB when:
  - They’re small, rarely used for filtering, and mainly stored for completeness.

Optimize selectively — not all fields require or deserve relational treatment.



## Performance Trade-offs
CockroachDB's architecture (MVCC storage, distributed SQL execution, automatic range splitting, follower reads, and parallelism) affects how each schema design performs. This section highlights **how each strategy behaves in CockroachDB** across ingestion, reads, contention, index behavior, storage, and analytical workloads.

### 1. Entity-Level Strategies

**<ins>FLAT</ins>**

**Pros**
- Simplicity; fewer joins = **fewer RPCs** in CockroachDB.
- B-tree indexes on top-level fields work very well.

**Cons**
- Wide tables reduce cache and range locality and can increase row-level lock contention.
- Schema changes become frequent.

**Workloads**
- OLTP with predictable schema
- Moderate write volume, high read selectivity

**<ins>PARTIALLY NORMALIZED</ins>**

**Pros**
- Splits hot vs. cold data into separate ranges automatically.
- Great for multi-region workloads because children can be pinned to locality-aware ranges.

**Cons**
- More join latency on OLTP queries.
- Higher write path complexity.

**Workloads**
- Mixed OLTP/HTAP (Hybrid Transactional/Analytical Processing)
- Complex hierarchical business entities

**<ins>PAYLOAD-ORIENTED</ins>**

**Pros**
- Perfect for **write-heavy** systems or CDC ingestion.
- Minimal schema changes.
- Excellent for append-only or event-style data.

**Cons**
- Weak queryability.
- Wider rows increase MVCC GC and scan overhead.

**Workloads**
- Write-heavy ingestion
- Event-sourcing
- Document archiving

### 2. Sub-document Strategies

**<ins>JSONB</ins>**

**Pros in CockroachDB**
- **Fastest ingestion** due to minimal row-level parsing.
- **Schema evolution is free** — no online schema changes required.
- JSONB is fully replicated with the rest of the row, so **no cross-range lookups** for nested structures.

**Cons / Trade-offs**
- JSONB GIN indexes are available but **heavier and slower** than B-tree indexes.
- Queries filtering inside JSONB often perform **more CPU work** and cannot prune ranges as effectively.
- For read-heavy workloads, especially large scans, JSONB fields **increase row width**, impacting MVCC read amplification.

**Best Workloads**
- Write-heavy ingestion pipelines
- Event, log, CDC ingestion mirrors
- Semi-structured or evolving payloads
- OLTP workloads that rarely filter deeply into JSONB fields

**<ins>COLUMNIZE</ins>**

**Pros**
- **B-tree indexes are extremely fast** in CockroachDB due to automatic range splitting.
- Columnized fields allow **range pruning**, improving cluster-wide performance.
- Works well with **Follower Reads** for read-scalable workloads.

**Cons**
- Every new column requires an **online schema change job**, which is safe but not free.
- Wide tables reduce cache locality and increase MVCC overhead.
- Column explosion can slow down writes if many indexes exist.

**Best Workloads**
- OLTP workloads with well-known hot columns
- Mixed workloads needing both fast reads and controlled ingestion
- Systems where constraints matter (unique, check, foreign keys to top-level tables)

**<ins>NORMALIZE</ins>**

**Pros**
- Child tables let CockroachDB **shard each relational component independently**, leading to natural horizontal scaling.
- Reads on sub-entities are **more targeted** (narrower rows + fewer columns).
- Supports **strong constraints** and efficient relational joins via distributed plans.

**Cons**
- More tables mean **more KV operations** per write (e.g., inserting a parent + N children).
- Distributed joins may introduce latency if parent and child ranges split across nodes.
- More schemas → more jobs → more complexity in DDL operations.

**Best Workloads**
- Transactional workloads with strong referential needs
- Analytical queries that query sub-entities independently
- High-cardinality nested lists
- Data models needing strict correctness

### 3. Array Strategies

**<ins>CHILD_TABLE</ins>**

**Pros**
- Large arrays can be **sharded** automatically by child table primary key.
- Child tables benefit from **narrow row width**, improving scan performance.
- Good fit for analytical workloads that explode arrays.

**Cons**
- More writes → more KV operations
- More table descriptors → more schema maintenance

**Workloads**
- Analytical pipelines
- Large one-to-many hierarchies
- Items, metrics, attribute lists

**<ins>JUNCTION_TABLE</ins>**

**Pros**
- Ideal for **many-to-many** relationships.
- Lets you index parent_id and referenced_id independently.
- Very good with Follower Reads and parallel scans.

**Cons**
- Extra join layer in most reads
- High write frequency on many-to-many mappings

**Workloads**
- Tags, relationships, taxonomy systems
- Product-to-category or user-to-role mapping

**<ins>JSONB ARRAY</ins>**

**Pros**
- Fast ingestion
- No schema updates
- Good for small attribute lists

**Cons**
- Poor visibility for the optimizer
- No range pruning on array content
- Heavy for analytical workloads that need to unnest arrays

**Workloads**
- Payload attributes
- Rarely-filtered lists
- Lightweight metadata

### 4. Workload-Oriented Strategy Recommendations

| Workload Type                          | Best Strategies                                | Avoid                                          |
| -------------------------------------- | ---------------------------------------------- | ---------------------------------------------- |
| **Write-heavy**                        | jsonb, jsonb arrays, payload-oriented entities | normalize (too many KV ops), excessive indexes |
| **Read-heavy (OLTP)**                  | columnize, partially normalize                 | jsonb filtering on deep paths                  |
| **Transactional (strong constraints)** | normalize, junction_table, columnize           | jsonb everywhere (weak constraints)            |
| **Analytical / HTAP**                  | normalize, child_table                         | wide JSONB rows, very wide flat tables         |
| **Schema evolving rapidly**            | jsonb, payload-oriented                        | strict normalization early on                  |

