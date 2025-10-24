#!/usr/bin/env python3
import sys, json, re, hashlib
from collections import defaultdict

# ---------- Type inference helpers ----------

# Default logical→SQL type mapping (can be overridden by schemaConversion.typeMap)
DEFAULT_TYPE_MAP = {
    "objectId": "STRING(24)",
    "string": "STRING",
    "bool": "BOOL",
    "int": "INT4",
    "int32": "INT4",
    "int64": "INT8",
    "long": "INT8",
    "double": "FLOAT8",
    "decimal": "DECIMAL(38,9)",
    "date": "TIMESTAMPTZ",
    "object": "JSON",
    "array": "JSON",
    "null": None
}

NUMERIC_RANK = {"INT4": 1, "INT8": 2, "FLOAT8": 3, "DECIMAL(38,9)": 4}

_ISO_DT_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}"                     # YYYY-MM-DD
    r"(?:[T ]\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?" # time with optional fractional
    r"(?:Z|[+-]\d{2}:\d{2}|[+-]\d{4})?)?$"    # Z or ±HH:MM or none
)


_HEX24_RE = re.compile(r"^[0-9a-fA-F]{24}$")  # Mongo ObjectId textual form
def looks_like_iso_datetime(s: str) -> bool:
    if not isinstance(s, str) or len(s) < 10 or len(s) > 35:
        return False
    return bool(_ISO_DT_RE.match(s))

def widen_numeric(a, b):
    if a is None: return b
    if b is None: return a
    return a if NUMERIC_RANK.get(a, 0) >= NUMERIC_RANK.get(b, 0) else b

def merge_types(types):
    """Return a logical type label; SQL mapping is applied later."""
    # Prefer structured labels so we can map via DEFAULT_TYPE_MAP + overrides
    if "object" in types:
        return "object"
    if "array" in types:
        return "array"
    tset = [t for t in types if t != "null"]
    if not tset:
        return "string"
    # numerics: pick the widest logical label present
    if set(tset) & {"int","int32","int64","long","double","decimal"}:
        out = None
        for t in tset:
            if t in {"int","int32"}:
                out = "int32" if out is None else out
            elif t in {"int64","long"}:
                out = "int64"
            elif t == "double":
                out = "double"
            elif t == "decimal":
                out = "decimal"
        return out or "double"
    if "objectId" in tset:
        return "objectId"
    if "date" in tset:
        return "date"
    if "bool" in tset and len(tset) == 1:
        return "bool"
    return "string"
def walk_types(doc, prefix="", out=None):
    if out is None: out = defaultdict(set)
    if isinstance(doc, dict):
        for k, v in doc.items():
            path = f"{prefix}.{k}" if prefix else k
            if v is None:
                out[path].add("null")
            elif isinstance(v, dict):
                # { "$oid": "671f..." }  -> objectId
                if set(v.keys()) == {"$oid"} and isinstance(v["$oid"], str) and _HEX24_RE.match(v["$oid"]):
                    out[path].add("objectId"); continue
                # { "$date": ... }       -> date
                if set(v.keys()) == {"$date"}:
                    out[path].add("date"); continue
                # { "$timestamp": {...} } -> treat as int (or keep as "object" if you prefer)
                if set(v.keys()) == {"$timestamp"}:
                    out[path].add("int32"); continue
                out[path].add("object"); walk_types(v, path, out)
            elif isinstance(v, list):
                out[path].add("array")
                for el in v[:5]:
                    if el is None:
                        out[path+"[]"].add("null")
                    elif isinstance(el, dict):
                        if set(el.keys()) == {"$oid"} and isinstance(el["$oid"], str) and _HEX24_RE.match(el["$oid"]):
                            out[path+"[]"].add("objectId"); continue
                        if set(el.keys()) == {"$date"}:
                            out[path+"[]"].add("date"); continue
                        if set(el.keys()) == {"$timestamp"}:
                            out[path+"[]"].add("int32"); continue
                        out[path+"[]"].add("object"); walk_types(el, path+"[]", out)
                    elif isinstance(el, list):
                        out[path+"[]"].add("array")
                    elif isinstance(el, bool):
                        out[path+"[]"].add("bool")
                    elif isinstance(el, int):
                        out[path+"[]"].add("int64" if abs(el) > 2**31-1 else "int32")
                    elif isinstance(el, float):
                        out[path+"[]"].add("double")
                    else:
                        # NOTE: check OID before date
                        if isinstance(el, str) and _HEX24_RE.match(el):
                            out[path+"[]"].add("objectId")
                        elif isinstance(el, str) and looks_like_iso_datetime(el):
                            out[path+"[]"].add("date")
                        else:
                            out[path+"[]"].add("string")
            elif isinstance(v, bool):
                out[path].add("bool")
            elif isinstance(v, int):
                out[path].add("int64" if abs(v) > 2**31-1 else "int32")
            elif isinstance(v, float):
                out[path].add("double")
            else:
                # NOTE: check OID before date
                if isinstance(v, str) and _HEX24_RE.match(v):
                    out[path].add("objectId")
                elif looks_like_iso_datetime(v):
                    out[path].add("date")
                else:
                    out[path].add("string")
    return out

def infer_from_samples(samples):
    tmap = defaultdict(set)
    for doc in samples:
        walk_types(doc, "", tmap)
    return {path: merge_types(types) for path, types in tmap.items()}

# ---------- Path & naming helpers ----------
def is_array_path(path, inferred):
    base = path + "[]"
    if base in inferred:
        return True
    return any(k.startswith(base + ".") for k in inferred.keys())

def has_children(prefix, inferred):
    return any(p.startswith(prefix + ".") and "[]" not in p[len(prefix)+1:] for p in inferred)

def immediate_children(prefix, inferred):
    plen = 0 if prefix == "" else len(prefix.split("."))
    cols = []
    for p in inferred:
        if "[]" in p:  # only consider non-array subpaths here
            continue
        if prefix == "":
            if "." not in p:
                cols.append(p)
        else:
            if p.startswith(prefix + ".") and len(p.split(".")) == plen + 1:
                cols.append(p.split(".")[-1])
    return sorted(set(cols))

def to_snake(name):
    s = name.replace("[]","").replace(".","_")
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s)
    s = re.sub(r"[^A-Za-z0-9_]+", "_", s)
    return re.sub(r"_+", "_", s).strip("_").lower()

def to_camel(name):
    base = to_snake(name).split("_")
    if not base: return ""
    return base[0] + "".join(w.capitalize() for w in base[1:])

def to_kebab(name):
    return to_snake(name).replace("_", "-")

def style_name(raw, style):
    if style == "camelCase": return to_camel(raw)
    if style == "kebab-case": return to_kebab(raw)
    return to_snake(raw)  # snake_case default

def shorten_ident(name, max_len):
    if len(name) <= max_len: return name
    h = hashlib.sha1(name.encode("utf-8")).hexdigest()[:8]
    keep = max_len - 9
    if keep <= 0: return h
    return f"{name[:keep]}_{h}"

def styled_name(raw, style, max_len):
    return shorten_ident(style_name(raw, style), max_len)

# ---------- Config helpers ----------
def get_table_override(sc, path):
    for ov in sc.get("tableOverrides", []):
        if ov.get("path") == path:
            return ov
    return None

def get_column_override(sc, path):
    for ov in sc.get("columnOverrides", []):
        if ov.get("path") == path:
            return ov
    return None

def ignored_path(sc, path):
    if path in set(sc.get("ignorePaths", [])): return True
    # If a table/column override says action=ignore, treat as ignored
    tov = get_table_override(sc, path)
    if tov and tov.get("action") == "ignore": return True
    cov = get_column_override(sc, path)
    if cov and cov.get("action") == "ignore": return True
    return False

# ---------- Core mapping ----------
def build_mapping(bundle):
    sc = bundle["schemaConversion"]
    inferred = infer_from_samples(bundle.get("samples", []))

    # --- Global defaults ---
    default_strategy = sc.get("defaultStrategy", "columnize")
    array_strategy   = sc.get("arrayStrategy", "child_table")
    flatten_depth    = sc.get("flattenDepth", 1)
    name_style = sc.get("tableDefaults", {}).get("nameStyle", "snake_case")
    ident_max  = sc.get("tableDefaults", {}).get("identifierMaxLen", 63)

    # Column defaults
    coldefs = sc.get("tableDefaults", {}).get("columnDefaults", {})
    max_varchar = coldefs.get("maxVarchar", 1024)
    decimal_default = coldefs.get("decimalDefault", "DECIMAL(38,9)")
    time_tz_default = coldefs.get("timeTzDefault", "TIMESTAMPTZ")

    # ID defaults
    idgrp = sc.get("tableDefaults", {}).get("id", {})
    id_strategy = idgrp.get("idStrategy", "use_objectid")
    preserve_source = idgrp.get("preserveSourceId", False)
    preserve_as = idgrp.get("preserveAs", "legacy_id")
    unique_legacy = idgrp.get("uniqueIndex", True)
    apply_id_to = idgrp.get("applyTo", ["base"])

    # ObjectId derivation config
    oid_cfg = sc.get("objectId", {}).get("derive", {}) if isinstance(sc.get("objectId"), dict) else {}
    oid_emit_ts = oid_cfg.get("timestamp", False)
    oid_ts_name = oid_cfg.get("columnName", "id_ts")

    # Arrays defaults
    arrgrp = sc.get("tableDefaults", {}).get("arrays", {})
    child_pk_default = arrgrp.get("childPkDefault", "synthetic")
    array_index_col  = arrgrp.get("arrayIndexColumnName", "elem_idx")
    fk_on_delete     = arrgrp.get("fkOnDelete", "CASCADE")

    # Primary key override for base tables
    pk_defaults = sc.get("tableDefaults", {}).get("primaryKey", {}) or {}
    explicit_pk_cols = pk_defaults.get("columns")

    # Merge user overrides onto defaults (case-insensitive keys)
    user_map = { (k or "").lower(): v for k, v in (sc.get("typeMap", {}) or {}).items() }
    effective_type_map = dict(DEFAULT_TYPE_MAP)
    effective_type_map.update(user_map)

    # --- Base table naming (allow tableOverride on collection path) ---
    base_path = bundle["meta"]["collection"]
    base_override = get_table_override(sc, base_path) or {}

    # --- helper to normalize fk to list (object|array -> list) ---
    def _normalize_fk(fk_raw):
        if fk_raw and isinstance(fk_raw, dict):
            return [fk_raw]
        if isinstance(fk_raw, list):
            return [fk for fk in fk_raw if isinstance(fk, dict)]
        return []

    # External FK specs on base table (optional)
    base_fk_specs = _normalize_fk(base_override.get("fk"))
    external_fk_by_child = {}
    for _spec in base_fk_specs:
        child_cols = _spec.get("childColumns")
        if isinstance(child_cols, str):
            external_fk_by_child[child_cols] = _spec
        elif isinstance(child_cols, list):
            for _c in child_cols:
                if isinstance(_c, str):
                    external_fk_by_child[_c] = _spec

    base_table_name = base_override.get("targetTable") or styled_name(base_path, name_style, ident_max)
    mapping = {"baseTable": base_table_name, "columns": [], "childTables": [], "baseForeignKeys": [], "externalForeignKeys": []}

    # --- Build base PK column (id) per id_strategy unless explicit_pk overrides it ---
    def id_type_and_default(strategy):
        if strategy == "rowid": return ("INT8", "unordered_unique_rowid()", None)
        if strategy == "uuid":  return ("UUID", "gen_random_uuid()", None)
        if strategy == "use_objectid": return ("STRING(24)", None, "_id")
        if strategy == "natural": return ("STRING", None, "id")
        return ("STRING", None, "id")

    id_type, id_default, id_source_path = id_type_and_default(id_strategy)
    # Always have an 'id' column in mapping (even if explicit_pk_cols replaces PK)
    id_col = {"name": styled_name("id", name_style, ident_max), "path": id_source_path, "type": id_type, "primaryKey": True, "nullable": False}
    if id_default: id_col["default"] = id_default
    mapping["columns"].append(id_col)

    # Derived ObjectId timestamp (single consolidated col) — default OFF
    if id_strategy == "use_objectid" and oid_emit_ts and not ignored_path(sc, oid_ts_name):
        mapping["columns"].append({"name": styled_name(oid_ts_name, name_style, ident_max),
                                   "path": None,
                                   "type": time_tz_default})

    # Optionally preserve Mongo _id (or 'id') as legacy on base
    if preserve_source and "base" in apply_id_to and id_strategy != "use_objectid":
        # Choose field to preserve
        top_level = sorted({p.split(".")[0] for p in inferred if "[]" not in p})
        source_id_field = "id" if "id" in top_level else "_id"
        if not ignored_path(sc, source_id_field):
            legacy_type = "STRING(24)" if source_id_field == "_id" else inferred.get(source_id_field, "STRING")
            legacy_col = {"name": styled_name(preserve_as, name_style, ident_max), "path": source_id_field, "type": legacy_type}
            mapping["columns"].append(legacy_col)
            if unique_legacy:
                mapping.setdefault("indexes", []).append({"columns": [legacy_col["name"]], "unique": True})

    # Tracks objects we emitted as JSON to suppress deeper paths
    jsonified_objects = set()

    # Helper: any JSON ancestor?
    def has_json_ancestor(path):
        anc = path
        while "." in anc:
            anc = anc.rsplit(".", 1)[0]
            if anc in jsonified_objects:
                return True
        return False
    
    # Tracks object paths we "normalized" into child tables to avoid adding their descendants to the base table
    normalized_objects = set()

    def has_normalized_ancestor(path):
        anc = path
        while "." in anc:
            anc = anc.rsplit(".", 1)[0]
            if anc in normalized_objects:
                return True
        return False
    
    # map normalized object path -> its table name
    normalized_tables = {}

    # --- Helper: choose final column type with overrides & typeMap ---
    def finalize_type(raw_type, path):
        """
        raw_type is now a logical label from merge_types(): e.g., 'string','int32','int64','double','decimal',
        'date','objectId','object','array','bool','null'. Map via effective_type_map, then apply defaults.
        """

        # If an explicit SQL type was provided (e.g., "STRING(3)", "FLOAT8"), return it as-is.
        # But DO NOT treat logical labels ("string","decimal","date",...) as SQL.
        if isinstance(raw_type, str):
            low = raw_type.strip().lower()
            logical_labels = {
                "string","int","int32","int64","long","double","decimal",
                "date","object","array","bool","objectid","null"
            }
            if low not in logical_labels:
                return raw_type

        logical = (raw_type or "string")
        # Normalize a few aliases into the keys we expect in DEFAULT_TYPE_MAP
        if logical == "int": logical = "int32"
        if logical == "long": logical = "int64"
        if logical == "object": logical = "object"
        if logical == "array": logical = "array"

        # map logical→SQL using defaults + overrides
        t = effective_type_map.get(logical, None)
        if t is None:
            # fall back to STRING if unmapped
            t = "STRING"

        # Apply column defaults for common types
        if t == "DECIMAL(38,9)" and decimal_default:
            t = decimal_default
        if t == "TIMESTAMPTZ" and time_tz_default == "TIMESTAMP":
            t = "TIMESTAMP"
        if t == "STRING" and max_varchar and max_varchar > 0:
            t = f"STRING({max_varchar})"
        return t

    def resolve_family_columns(fam_spec, cols, name_style, ident_max, base_path_prefix=""):
        """
        fam_spec['columns'] may contain final column names OR source paths.
        We resolve each entry to an existing column name in 'cols'.
        - If it directly matches a column name, keep it.
        - Else, treat it as a path and style it the same way we did when creating columns.
        Skip any names that don't exist and skip PK columns.
        """
        # Build a set of actual column names on this table
        col_names = {c["name"] for c in cols}
        # Identify PK columns to avoid assigning them to a family (leave them in default)
        pk_names = {c["name"] for c in cols if c.get("primaryKey")}
        resolved = []
        for raw in fam_spec.get("columns", []):
            # direct match?
            if raw in col_names and raw not in pk_names:
                resolved.append(raw)
                continue
            # try styling as a path
            styled = styled_name(raw, name_style, ident_max)
            if styled in col_names and styled not in pk_names:
                resolved.append(styled)
        # de-dup, preserve order
        seen = set(); out = []
        for n in resolved:
            if n not in seen:
                out.append(n); seen.add(n)
        return out

    # --- Non-array paths → columns per strategy ---
    non_array_paths = [p for p in inferred if "[]" not in p]
    def segs(p): return 0 if not p else len(p.split("."))

    # Legacy derived names we must suppress unless explicitly overridden
    _denylist = {"id_date", "id_timestamp"}
    _denylist_raw_paths = {"_id.date", "_id.timestamp"}  # belt & suspenders

    # ensure parents are processed before children
    for p in sorted(non_array_paths, key=lambda x: (len(x), x)):
        # Skip internal id we've already handled and any explicit ignores
        if p in ("_id", "id"):
            continue
        if p in _denylist and not get_column_override(sc, p):
            continue
        cov_for_name = get_column_override(sc, p) or {}
        derived_name = styled_name(cov_for_name.get("crdbName") or p, name_style, ident_max)
        if (derived_name in _denylist or p in _denylist_raw_paths) and not cov_for_name:
            # suppressed unless explicitly overridden via columnOverrides
            continue
        if ignored_path(sc, p):
            continue
        if has_json_ancestor(p):
            continue

        # If an ancestor was normalized, skip *scalars* so they don't go to the base table.
        # But in normalize mode, still allow descendant OBJECT paths to be processed into their own tables.
        if has_normalized_ancestor(p):
            if default_strategy == "normalize" and has_children(p, inferred):
                pass
            else:
                continue

        # Skip array owners in this loop to avoid JSON+child duplication (e.g., 'items', 'tags')
        if is_array_path(p, inferred):
            continue

        if has_children(p, inferred):
            if default_strategy == "jsonb":
                cov = get_column_override(sc, p) or {}
                if cov.get("action") != "ignore":
                    cname = styled_name(cov.get("crdbName") or p, name_style, ident_max)
                    ctype = cov.get("crdbType") or "JSON"
                    mapping["columns"].append({"name": cname, "path": p, "type": ctype})
                    jsonified_objects.add(p)
            elif default_strategy == "normalize":
                # --- per-path override: treat this object as columnized into base ---
                tov = get_table_override(sc, p) or {}
                if tov.get("mode") == "columnize":
                    # Inline immediate children
                    for child in immediate_children(p, inferred):
                        child_path = f"{p}.{child}"
                        if (segs(child_path) - segs(p)) <= flatten_depth:
                            if ignored_path(sc, child_path): 
                                continue
                            cov = get_column_override(sc, child_path) or {}
                            if cov.get("action") == "ignore":
                                continue
                            # don't emit JSON + child table for arrays
                            if is_array_path(child_path, inferred):
                                continue
                            if has_children(child_path, inferred):
                                # child object → JSON at this depth
                                cname = styled_name(cov.get("crdbName") or child_path, name_style, ident_max)
                                ctype = cov.get("crdbType") or "JSON"
                                mapping["columns"].append({"name": cname, "path": child_path, "type": ctype})
                                jsonified_objects.add(child_path)
                            else:
                                raw_t = inferred.get(child_path, "STRING")
                                ctype = finalize_type(cov.get("crdbType") or raw_t, child_path)
                                cname = styled_name(cov.get("crdbName") or child_path, name_style, ident_max)
                                mapping["columns"].append({"name": cname, "path": child_path, "type": ctype})
                        else:
                            # too deep → JSON column for the parent object
                            cov = get_column_override(sc, p) or {}
                            if cov.get("action") != "ignore":
                                cname = styled_name(cov.get("crdbName") or p, name_style, ident_max)
                                ctype = cov.get("crdbType") or "JSON"
                                mapping["columns"].append({"name": cname, "path": p, "type": ctype})
                                jsonified_objects.add(p)
                    continue
                
                # Collect immediate scalar children (object children become their own tables later)
                child_cols = []
                for child in immediate_children(p, inferred):
                    child_path = f"{p}.{child}"
                    if ignored_path(sc, child_path): 
                        continue
                    cov = get_column_override(sc, child_path) or {}
                    if cov.get("action") == "ignore":
                        continue
                    # if the child is an array owner, let the arrays loop handle it
                    if is_array_path(child_path, inferred):
                        continue
                    if has_children(child_path, inferred):
                        # this child is an object; it will be handled in a later iteration as its own table
                        continue
                    # Denylist based on *derived* column name (post-override + styling)
                    cname = styled_name(cov.get("crdbName") or child_path, name_style, ident_max)
                    if (cname in _denylist or child_path in _denylist_raw_paths) and not cov:
                        continue
                    raw_t = inferred.get(child_path, "STRING")
                    ctype = finalize_type(cov.get("crdbType") or raw_t, child_path)
                    cname = styled_name(cov.get("crdbName") or child, name_style, ident_max)
                    col = {"name": cname, "path": child_path, "type": ctype}
                    if "nullable" in cov: col["nullable"] = cov["nullable"]
                    if "default" in cov: col["default"] = cov["default"]
                    if "generated" in cov and cov["generated"].get("expr"):
                        col["generated"] = cov["generated"]
                    child_cols.append(col)
                    
                # If this object has *no immediate scalar fields*, don't create an empty table.
                # (Its nested objects will be handled on their own iterations.)
                if not child_cols:
                    # Do NOT mark this object as normalized; we still need to process its child objects.
                    # e.g., 'shipping' → no table; 'shipping.address' / 'shipping.location' will become tables.
                    continue

                # Create a 1:1 child table for this object path
                tov = get_table_override(sc, p) or {}
                target_table = tov.get("targetTable") or styled_name(p, name_style, ident_max)
                fk_col = styled_name(f"{mapping['baseTable']}_id", name_style, ident_max)

                # Decide FK shape: normal 1:1 child → base OR reverse FK (base → child)
                fk_specs = _normalize_fk(tov.get("fk"))
                if fk_specs and fk_specs[0].get("reverse"):
                    # --- Reverse relationship: BASE references this normalized table ---
                    # Child PK comes from a field inside the object (default: 'id')
                    rspec = fk_specs[0].get("reverseSpec", {}) if isinstance(fk_specs[0].get("reverseSpec"), dict) else {}
                    child_pk_path = rspec.get("childPkPath", "id")  # e.g., 'id'
                    child_pk_leaf = child_pk_path.split(".")[-1]
                    child_pk_name = styled_name(child_pk_leaf, name_style, ident_max)
                    child_pk_full_path = f"{p}.{child_pk_path}"
                    cov_pk = get_column_override(sc, child_pk_full_path) or {}
                    raw_t = inferred.get(child_pk_full_path, "STRING")
                    child_pk_type = finalize_type(cov_pk.get("crdbType") or raw_t, child_pk_full_path)

                    # ensure PK column exists once in the child columns
                    if not any(c["name"] == child_pk_name for c in child_cols):
                        child_cols.insert(0, {
                            "name": styled_name(cov_pk.get("crdbName") or child_pk_leaf, name_style, ident_max),
                            "path": child_pk_full_path,
                            "type": child_pk_type,
                            "nullable": False,
                            **({"default": cov_pk["default"]} if "default" in cov_pk else {})
                        })
                        # update variable if name was overridden
                        child_pk_name = styled_name(cov_pk.get("crdbName") or child_pk_leaf, name_style, ident_max)

                    # Build child table with its own PK, and NO FK to base
                    child = {
                        "table": target_table,
                        "primaryKey": [child_pk_name],
                        "columns": child_cols
                    }

                    # Add FK column on the BASE table to point to this child
                    base_fk_name = styled_name(rspec.get("baseColumnName") or f"{p.split('.')[-1]}_id", name_style, ident_max)
                    base_fk_nullable = bool(rspec.get("nullable", False))

                    # add/ensure the FK column on base
                    if not any(c["name"] == base_fk_name for c in mapping["columns"]):
                        mapping["columns"].append({
                            "name": base_fk_name,
                            "path": child_pk_full_path,
                            "type": child_pk_type,
                            "nullable": base_fk_nullable
                        })

                    # table-level FK on base → child
                    mapping.setdefault("baseForeignKeys", []).append({
                        "parentTable": target_table,         # referenced table = CHILD
                        "parentColumns": [child_pk_name],    # referenced col(s) on CHILD
                        "childColumns": [base_fk_name],      # column on BASE
                        "onDelete": rspec.get("onDelete", "CASCADE")
                    })

                    # Attach column families (if any) to this child table
                    if tov.get("columnFamilies"):
                        cf_list = []
                        for fam in tov["columnFamilies"]:
                            cols = resolve_family_columns(fam, child["columns"], name_style, ident_max)
                            if cols:
                                cf_list.append({"name": styled_name(fam["name"], name_style, ident_max), "columns": cols})
                        if cf_list:
                            child["columnFamilies"] = cf_list

                    # finalize & record normalization
                    mapping["childTables"].append(child)
                    normalized_objects.add(p)
                    normalized_tables[p] = target_table

                else:
                    # Build child table (1:1 with parent) → PK = <parent>_id
                    child = {
                        "table": target_table,
                        "primaryKey": [fk_col],
                        "foreignKey": {
                            "parentTable": mapping["baseTable"],
                            "parentColumns": [styled_name("id", name_style, ident_max)],
                            "childColumns": [fk_col],
                            "onDelete": ( _normalize_fk(tov.get("fk"))[0].get("onDelete") if _normalize_fk(tov.get("fk")) else fk_on_delete )
                        },
                        "columns": []
                    }
                    # FK to parent
                    child["columns"].append({"name": fk_col, "path": "_id", "type": id_type, "nullable": False})
                    # Add the scalar columns we collected
                    child["columns"].extend(child_cols)

                    if tov.get("columnFamilies"):
                        cf_list = []
                        for fam in tov["columnFamilies"]:
                            cols = resolve_family_columns(fam, child["columns"], name_style, ident_max)
                            if cols:
                                cf_list.append({"name": styled_name(fam["name"], name_style, ident_max), "columns": cols})
                        if cf_list:
                            child["columnFamilies"] = cf_list

                    # Optional per-table overrides (single-FK override remains supported)
                    fk_specs = _normalize_fk(tov.get("fk"))
                    if fk_specs:
                        # Replace the default parent FK using the first spec (backward compatible)
                        fk0 = fk_specs[0]
                        child["foreignKey"] = {
                            "parentTable": fk0.get("parentTable", child["foreignKey"]["parentTable"]),
                            "parentColumns": fk0.get("parentColumns", child["foreignKey"]["parentColumns"]),
                            "childColumns": fk0.get("childColumns", child["foreignKey"]["childColumns"]),
                            "onDelete": fk0.get("onDelete", child["foreignKey"]["onDelete"])
                        }
                    if "indexDefs" in tov:
                        child.setdefault("indexes", []).extend(tov["indexDefs"])
                    if "comment" in tov:
                        child["comment"] = tov["comment"]

                    # ---- NEW: Extra FKs for junction tables (array element references) ----
                    # For each fk spec, create element-based FK columns on the child table:
                    #   <elem>_id  (typed to idStrategy)
                    #   <elem>_<preserveAs> (ONLY if idStrategy != 'use_objectid')
                    # and add an extra FK to the referenced parentTable.
                    if fk_specs:
                        # Determine the base element column naming (consider column override on 'base_arr[]')
                        # We'll compute this later in the arrays loop where 'base_arr' is known.
                        pass  # placeholder; actual emission happens in the arrays loop below

                    mapping["childTables"].append(child)
                    # mark this object as normalized so its descendants do not go into the base table
                    normalized_objects.add(p)
                    normalized_tables[p] = target_table
            else:
                # columnize:
                if segs(p) <= flatten_depth:
                    # Inline immediate children:
                    for child in immediate_children(p, inferred):
                        child_path = f"{p}.{child}"
                        if ignored_path(sc, child_path): continue
                        cov = get_column_override(sc, child_path) or {}
                        if cov.get("action") == "ignore": continue
                        # if the child is an array owner, don't emit a parent JSON column for it
                        if is_array_path(child_path, inferred): continue

                        # If child is an object → emit JSON (do not flatten grandchildren at this depth)
                        if has_children(child_path, inferred):
                            # emit JSON for child object, and suppress deeper descendants
                            cname = styled_name(cov.get("crdbName") or child_path, name_style, ident_max)
                            ctype = cov.get("crdbType") or "JSON"
                            mapping["columns"].append({"name": cname, "path": child_path, "type": ctype})
                            jsonified_objects.add(child_path)
                        else:
                            # External FK on top-level scalar fields (base table)
                            _top_level = "." not in child_path
                            _fk_spec = external_fk_by_child.get(child_path) if _top_level else None
                            if _fk_spec:
                                # Legacy FK value column (preserve original ObjectId)
                                _legacy_col = styled_name(f"{child_path}_{preserve_as}", name_style, ident_max)
                                if id_strategy != "use_objectid":
                                    if not any(c["name"] == _legacy_col for c in mapping["columns"]):
                                        mapping["columns"].append({"name": _legacy_col, "path": child_path, "type": finalize_type("objectId", child_path)})
                                # Actual FK column typed per id strategy
                                _fk_col = styled_name(f"{child_path}_id", name_style, ident_max)
                                _id_type, _, _ = id_type_and_default(id_strategy)
                                if not any(c["name"] == _fk_col for c in mapping["columns"]):
                                    mapping["columns"].append({"name": _fk_col, "path": None, "type": _id_type})
                                # Base-level FK constraint
                                _parent_table = _fk_spec.get("parentTable") or styled_name(child_path, name_style, ident_max)
                                _parent_cols = _fk_spec.get("parentColumns") or ["id"]
                                _pc = []
                                for pc in _parent_cols:
                                    _pc.append(styled_name(("id" if (pc == "_id" and id_strategy != "use_objectid") else pc), name_style, ident_max))
                                mapping["baseForeignKeys"].append({
                                    "parentTable": styled_name(_parent_table, name_style, ident_max),
                                    "parentColumns": _pc,
                                    "childColumns": [_fk_col],
                                    "onDelete": _fk_spec.get("onDelete") or fk_on_delete
                                })
                                # Migration-time lookup hint (for pipeline)
                                if id_strategy != "use_objectid":
                                    mapping["externalForeignKeys"].append({
                                        "childField": styled_name(child_path, name_style, ident_max),
                                        "legacyColumn": _legacy_col,
                                        "fkColumn": _fk_col,
                                        "parentTable": styled_name(_parent_table, name_style, ident_max),
                                        "parentIdColumn": _pc[0],
                                        "lookup": {
                                            "from": _legacy_col,
                                            "toTable": styled_name(_parent_table, name_style, ident_max),
                                            "toColumn": styled_name(preserve_as if id_strategy != "use_objectid" else "id", name_style, ident_max)
                                        }
                                    })
                            else:
                                raw_t = inferred.get(child_path, "STRING")
                                ctype = finalize_type(cov.get("crdbType") or raw_t, child_path)
                                cname = styled_name(cov.get("crdbName") or child_path, name_style, ident_max)
                                mapping["columns"].append({"name": cname, "path": child_path, "type": ctype})
                else:
                    # too deep → JSON
                    cov = get_column_override(sc, p) or {}
                    if cov.get("action") != "ignore":
                        cname = styled_name(cov.get("crdbName") or p, name_style, ident_max)
                        ctype = cov.get("crdbType") or "JSON"
                        mapping["columns"].append({"name": cname, "path": p, "type": ctype})
                        jsonified_objects.add(p)
            continue
        else:
            # In normalize mode, nested scalars belong to their object's table, not the base
            if default_strategy == "normalize" and "." in p:
                continue

        # scalar field
        cov = get_column_override(sc, p) or {}
        if cov.get("action") == "ignore": continue

        # external FK on top-level scalars (e.g., articles.orderRef)
        if "." not in p:
            _fk_spec = external_fk_by_child.get(p)
            if _fk_spec:
                _fk_col = styled_name(f"{p}_id", name_style, ident_max)
                _id_type, _, _ = id_type_and_default(id_strategy)

                # Only create the legacy FK value when NOT using objectId strategy
                if id_strategy != "use_objectid":
                    _legacy_col = styled_name(f"{p}_{preserve_as}", name_style, ident_max)
                    if not any(c["name"] == _legacy_col for c in mapping["columns"]):
                        mapping["columns"].append({"name": _legacy_col, "path": p, "type": finalize_type("objectId", p)})

                if not any(c["name"] == _fk_col for c in mapping["columns"]):
                    mapping["columns"].append({"name": _fk_col, "path": None, "type": _id_type})
                # base-level FK constraint
                _parent_table = _fk_spec.get("parentTable") or styled_name(p, name_style, ident_max)
                _parent_cols = _fk_spec.get("parentColumns") or ["id"]
                _pc = []
                for pc in _parent_cols:
                    _pc.append(styled_name(("id" if (pc == "_id" and id_strategy != "use_objectid") else pc), name_style, ident_max))

                mapping["baseForeignKeys"].append({
                    "parentTable": styled_name(_parent_table, name_style, ident_max),
                    "parentColumns": _pc,
                    "childColumns": [_fk_col],
                    "onDelete": _fk_spec.get("onDelete") or fk_on_delete
                })

                # Only add migration lookup hint when NOT using objectId strategy
                if id_strategy != "use_objectid":
                    mapping["externalForeignKeys"].append({
                        "childField": styled_name(p, name_style, ident_max),
                        "legacyColumn": _legacy_col,
                        "fkColumn": _fk_col,
                        "parentTable": styled_name(_parent_table, name_style, ident_max),
                        "parentIdColumn": _pc[0],
                        "lookup": {
                            "from": _legacy_col,
                            "toTable": styled_name(_parent_table, name_style, ident_max),
                            "toColumn": styled_name(preserve_as, name_style, ident_max)
                        }
                    })

                continue

        raw_t = inferred.get(p, "STRING")
        ctype = finalize_type(cov.get("crdbType") or raw_t, p)
        cname = styled_name(cov.get("crdbName") or p, name_style, ident_max)
        mapping["columns"].append({"name": cname, "path": p, "type": ctype})

    # --- Arrays → child/junction/jsonb per strategy & overrides ---
    array_paths = sorted({ p[:-2] for p in inferred if p.endswith("[]") })
    for base_arr in array_paths:
        if ignored_path(sc, base_arr + "[]") or ignored_path(sc, base_arr):
            continue

        # Skip arrays under any JSON-ified ancestor object
        if has_json_ancestor(base_arr):
            continue

        # If the array lives under a normalized object, attach it to that object's table
        parent_norm_path = None
        ancestor = base_arr
        while "." in ancestor:
            ancestor = ancestor.rsplit(".", 1)[0]
            if ancestor in normalized_tables:
                parent_norm_path = ancestor
                break

        tov = get_table_override(sc, base_arr + "[]") or get_table_override(sc, base_arr) or {}
        mode = tov.get("mode") or tov.get("strategy") or array_strategy
        
        if mode == "jsonb":
            # place JSON column on normalized parent table if present; else on base table
            cov = get_column_override(sc, base_arr) or {}
            leaf = base_arr.split(".")[-1]
            cname = styled_name(cov.get("crdbName") or leaf, name_style, ident_max)
            ctype = cov.get("crdbType") or "JSON"

            if parent_norm_path:
                # find normalized parent table (created earlier)
                parent_table_name = normalized_tables[parent_norm_path]

                # locate the existing childTable entry by name and append the column there
                for ct in mapping["childTables"]:
                    if ct["table"] == parent_table_name:
                        # Avoid dup if it somehow exists
                        if not any(c["name"] == cname for c in ct["columns"]):
                            ct["columns"].append({"name": cname, "path": base_arr, "type": ctype})
                        break
            else:
                # fall back to base table JSON column
                if not any(c["name"] == cname for c in mapping["columns"]):
                    mapping["columns"].append({"name": cname, "path": base_arr, "type": ctype})
            continue

        # Child or junction table
        target_table = tov.get("targetTable") or styled_name(base_arr, name_style, ident_max)
        fk_parent_table = mapping["baseTable"]
        fk_parent_pk_col = styled_name("id", name_style, ident_max)
        fk_col = styled_name(f"{mapping['baseTable']}_id", name_style, ident_max)

        # Re-parent under normalized object if present
        if parent_norm_path:
            parent_table_name = normalized_tables[parent_norm_path]
            fk_parent_table = parent_table_name
            fk_parent_pk_col = styled_name(f"{mapping['baseTable']}_id", name_style, ident_max)
            fk_col = styled_name(f"{parent_table_name}_id", name_style, ident_max)

        # Collect child columns from element fields
        child_cols = []
        subprefix = base_arr + "[]"
        has_struct_children = False
        for p, t in inferred.items():
            if p.startswith(subprefix + ".") and "[]" not in p[len(subprefix)+1:]:
                has_struct_children = True
                leaf = p.split(".")[-1]
                child_cols.append((leaf, t))
        if not child_cols:
            # Scalar array → single 'value' column
            suppress_elem_value = (mode == "junction_table") and any(
                _spec_refers_to_element(spec, base_arr) for spec in fk_specs
            )
            if not suppress_elem_value:
                merged = inferred.get(subprefix, "STRING")
                child_cols.append(("value", merged))

        # PK
        pk = tov.get("pk")
        if not pk:
            if child_pk_default == "synthetic" and id_strategy in ("rowid", "uuid"):
                pk = ["id"]
            else:
                pk = [fk_col, array_index_col]

        # Build child table shape
        fk_specs = _normalize_fk(tov.get("fk"))
        child = {
            "table": target_table,
            "primaryKey": pk,
            "foreignKey": {
                "parentTable": fk_parent_table,
                "parentColumns": [fk_parent_pk_col],
                "childColumns": [fk_col],
                "onDelete": ( fk_specs[0].get("onDelete") if fk_specs else fk_on_delete )
            },
            "columns": []
        }

        # FK column on the child
        child["columns"].append({"name": fk_col, "path": "_id", "type": id_type, "nullable": False})

        # Array index for composite PK
        if fk_col in pk and array_index_col in pk and not any(c["name"] == array_index_col for c in child["columns"]):
            child["columns"].append({"name": styled_name(array_index_col, name_style, ident_max), "path": None, "type": "INT4", "nullable": False})

        # Synthetic child PK if requested
        if "id" in pk and id_strategy == "rowid":
            child["columns"].append({"name": styled_name("id", name_style, ident_max), "path": None, "type": "INT8", "nullable": False, "primaryKey": True, "default": "unordered_unique_rowid()"})
        elif "id" in pk and id_strategy == "uuid":
            child["columns"].append({"name": styled_name("id", name_style, ident_max), "path": None, "type": "UUID", "nullable": False, "primaryKey": True, "default": "gen_random_uuid()"})

        # Child columns — do NOT prefix with parent path; use field name only
        for name, t in child_cols:
            src_path = f"{subprefix}.{name}" if has_struct_children else subprefix
            ov_path_for_col = f"{base_arr}[].{name}" if has_struct_children else base_arr + "[]"
            cov = get_column_override(sc, ov_path_for_col) or {}
            if cov.get("action") == "ignore": continue
            cname = styled_name(cov.get("crdbName") or name, name_style, ident_max)
            ctype = finalize_type(cov.get("crdbType") or t, ov_path_for_col)
            col = {"name": cname, "path": src_path, "type": ctype}
            if "nullable" in cov: col["nullable"] = cov["nullable"]
            if "default" in cov: col["default"] = cov["default"]
            if "generated" in cov and cov["generated"].get("expr"):
                col["generated"] = cov["generated"]
            child["columns"].append(col)

        # Override base FK (first spec) if supplied (back-compatible)
        def _spec_refers_to_element(spec, arr_path):
            cc = spec.get("childColumns")
            if isinstance(cc, str):
                return cc == arr_path + "[]" or cc == arr_path
            if isinstance(cc, list):
                return any(x == arr_path + "[]" or x == arr_path for x in cc)
            return False

        if fk_specs and not _spec_refers_to_element(fk_specs[0], base_arr):
            fk0 = fk_specs[0]
            child["foreignKey"] = {
                "parentTable": fk0.get("parentTable", child["foreignKey"]["parentTable"]),
                "parentColumns": fk0.get("parentColumns", child["foreignKey"]["parentColumns"]),
                "childColumns": fk0.get("childColumns", child["foreignKey"]["childColumns"]),
                "onDelete": fk0.get("onDelete", child["foreignKey"]["onDelete"])
            }

        # ---- NEW: element→external FKs for junction tables ----
        # If any fk spec references the array element, create columns and extra FKs.
        if fk_specs:
            # Base name for the element column (respects column override on 'base_arr[]')
            cov_elem = get_column_override(sc, base_arr + "[]") or {}
            elem_base = cov_elem.get("crdbName") or ("value" if not has_struct_children else "value")
            elem_base = styled_name(elem_base, name_style, ident_max)

            for spec in fk_specs:
                child_cols_spec = spec.get("childColumns")
                # Allow either a single string or an array; match the current array path
                matches_elem = False
                if isinstance(child_cols_spec, str):
                    matches_elem = (child_cols_spec == base_arr + "[]" or child_cols_spec == base_arr or child_cols_spec.endswith("[]") and child_cols_spec.split(".")[-1] == base_arr.split(".")[-1])
                elif isinstance(child_cols_spec, list):
                    matches_elem = any(cc == base_arr + "[]" for cc in child_cols_spec)

                if not matches_elem:
                    continue

                # Create <elem>_id and optional <elem>_<preserveAs> on the child table
                fk_col_name = styled_name(f"{elem_base}_id", name_style, ident_max)
                if not any(c["name"] == fk_col_name for c in child["columns"]):
                    child["columns"].append({"name": fk_col_name, "path": None, "type": id_type})

                if id_strategy != "use_objectid":
                    legacy_col_name = styled_name(f"{elem_base}_{preserve_as}", name_style, ident_max)
                    if not any(c["name"] == legacy_col_name for c in child["columns"]):
                        child["columns"].append({"name": legacy_col_name, "path": subprefix, "type": "STRING(24)"})

                # Parent columns default to 'id'
                parent_cols = spec.get("parentColumns") or ["id"]
                parent_cols_styled = [styled_name(("id" if (pc == "_id" and id_strategy != "use_objectid") else pc), name_style, ident_max) for pc in parent_cols]

                # Add extra FK from <elem>_id -> parentTable(parentCols)
                child.setdefault("extraForeignKeys", []).append({
                    "parentTable": styled_name(spec.get("parentTable") or elem_base, name_style, ident_max),
                    "parentColumns": parent_cols_styled,
                    "childColumns": [fk_col_name],
                    "onDelete": spec.get("onDelete", "CASCADE")
                })

        if tov.get("columnFamilies"):
            cf_list = []
            for fam in tov["columnFamilies"]:
                cols = resolve_family_columns(fam, child["columns"], name_style, ident_max)
                if cols:
                    cf_list.append({"name": styled_name(fam["name"], name_style, ident_max), "columns": cols})
            if cf_list:
                child["columnFamilies"] = cf_list

        # Index definitions (table-level)
        if "indexDefs" in tov:
            child.setdefault("indexes", []).extend(tov["indexDefs"])

        # Comment
        if "comment" in tov:
            child["comment"] = tov["comment"]

        mapping["childTables"].append(child)

    # Base table indexes/comments
    if "indexDefs" in base_override:
        mapping.setdefault("indexes", []).extend(base_override["indexDefs"])
    if "comment" in base_override:
        mapping["comment"] = base_override["comment"]

    # Primary key explicit override
    if explicit_pk_cols:
        mapping["explicitPrimaryKey"] = [ styled_name(c, name_style, ident_max) for c in explicit_pk_cols ]

    # ---------- De-dup columns defensively ----------
    def _dedupe_columns(cols):
        seen = set()
        out = []
        for c in cols:
            nm = c["name"]
            if nm in seen: continue
            seen.add(nm)
            out.append(c)
        return out

    mapping["columns"] = _dedupe_columns(mapping["columns"])
    for ct in mapping["childTables"]:
        ct["columns"] = _dedupe_columns(ct["columns"])
    
    # Base table column families (if any)
    base_cf = []
    if base_override.get("columnFamilies"):
        for fam in base_override["columnFamilies"]:
            cols = resolve_family_columns(fam, mapping["columns"], name_style, ident_max)
            if cols:
                base_cf.append({"name": styled_name(fam["name"], name_style, ident_max), "columns": cols})
    if base_cf:
        mapping["columnFamilies"] = base_cf

    return mapping

# ---------- DDL generation ----------
def ddl_for_table(table_name, cols, pk_cols=None, fkeys=None, indexes=None, table_comment=None, families=None):
    lines = []
    col_lines = []
    for c in cols:
        gen = c.get("generated", {})
        gen_expr = gen.get("expr")
        gen_suffix = f" AS ({gen_expr}) STORED" if gen_expr else ""
        default_sql = f" DEFAULT {c['default']}" if c.get("default") else ""
        notnull = " NOT NULL" if c.get("nullable") is False or c.get("primaryKey") else ""
        type_sql = "" if gen_expr else f" {c['type']}"
        col_lines.append(f"  {c['name']}{type_sql}{default_sql}{notnull}{gen_suffix}")

    if pk_cols:
        col_lines.append(f"  PRIMARY KEY ({', '.join(pk_cols)})")

    if fkeys:
        for fk in fkeys:
            col_lines.append(
                f"  FOREIGN KEY ({', '.join(fk['childColumns'])}) "
                f"REFERENCES {fk['parentTable']}({', '.join(fk['parentColumns'])}) "
                f"ON DELETE {fk.get('onDelete','CASCADE')}"
            )
    
    # Column families (if any). We place them as table elements in the CREATE block.
    if families:
        for fam in families:
            fam_name = fam.get("name") or "family"
            fam_cols = fam.get("columns") or []
            if fam_cols:
                col_lines.append(f"  FAMILY {fam_name} ({', '.join(fam_cols)})")

    lines.append(f"CREATE TABLE IF NOT EXISTS {table_name} (")
    lines.append(",\n".join(col_lines))
    lines.append(");\n")

    if indexes:
        for idx in indexes:
            name = idx.get("name") or f"idx_{table_name}_{'_'.join(idx['columns'])}"
            unique = "UNIQUE " if idx.get("unique") else ""
            using = ""
            if idx.get("type") == "inverted":
                using = " USING INVERTED"
            elif idx.get("type") == "hash":
                buckets = idx.get("hashShardedBuckets")
                using = f" USING HASH WITH BUCKETS = {buckets}" if buckets else " USING HASH"
            where = f" WHERE {idx['where']}" if idx.get("where") else ""
            storing = f" STORING ({', '.join(idx['storing'])})" if idx.get("storing") else ""
            lines.append(
                f"CREATE {unique}INDEX IF NOT EXISTS {name} ON {table_name}{using} "
                f"({', '.join(idx['columns'])}){storing}{where};"
            )

    if table_comment:
        lines.append(f"COMMENT ON TABLE {table_name} IS {json.dumps(table_comment)};")

    # Column comments (if any)
    for c in cols:
        if c.get("comment"):
            lines.append(f"COMMENT ON COLUMN {table_name}.{c['name']} IS {json.dumps(c['comment'])};")

    return "\n".join(lines)

def generate_ddl(mapping):
    ddl_parts = []
    # Base table columns: PK first
    base_cols_sorted = sorted(mapping["columns"], key=lambda c: 0 if c.get("primaryKey") else 1)
    base_pk = mapping.get("explicitPrimaryKey") or [ next((c["name"] for c in base_cols_sorted if c.get("primaryKey")), "id") ]
    ddl_parts.append(ddl_for_table(mapping["baseTable"], base_cols_sorted, base_pk, mapping.get("baseForeignKeys"), mapping.get("indexes"), mapping.get("comment"), mapping.get("columnFamilies")))

    for ct in mapping["childTables"]:
        cols_sorted = sorted(ct["columns"], key=lambda c: 0 if c.get("primaryKey") else 1)
        # Support extra foreign keys on child tables (junctions)
        fks = []
        if ct.get("foreignKey"):
            fks.append(ct["foreignKey"])
        if ct.get("extraForeignKeys"):
            fks.extend(ct["extraForeignKeys"])
        ddl_parts.append(
            ddl_for_table(ct["table"], cols_sorted, ct.get("primaryKey"), fks or None, ct.get("indexes"), ct.get("comment"), ct.get("columnFamilies"))
        )
    return "\n".join(ddl_parts)

# ---------- Entrypoint ----------
def main():
    bundle = json.load(sys.stdin)
    mapping = build_mapping(bundle)
    ddl = generate_ddl(mapping)

    h = hashlib.sha256()
    h.update(json.dumps(bundle.get("mongoValidator"), sort_keys=True).encode("utf-8"))
    h.update(json.dumps(bundle.get("schemaConversion"), sort_keys=True).encode("utf-8"))
    mapping_key = f"{bundle['meta']['db']}.{bundle['meta']['collection']}#{h.hexdigest()[0:12]}"

    out = {
        "ddl": ddl,
        "mapping": mapping,
        "inference": {
            "fieldCount": len([c for c in mapping["columns"] if not c.get("primaryKey")]) + 1,
            "childTables": [ct["table"] for ct in mapping["childTables"]],
            "baseTable": mapping["baseTable"]
        },
        "meta": {**bundle.get("meta", {}), "mappingKey": mapping_key}
    }
    json.dump(out, sys.stdout, indent=2)

if __name__ == "__main__":
    main()
