import json
import re
from java.io import BufferedReader, InputStreamReader
from java.nio.charset import StandardCharsets
from org.apache.nifi.processor.io import InputStreamCallback, OutputStreamCallback

flowFile = session.get()
if flowFile is None:
    exit()

class ReadJsonCallback(InputStreamCallback):
    def __init__(self):
        self.content = ""

    def process(self, inputStream):
        reader = BufferedReader(InputStreamReader(inputStream, StandardCharsets.UTF_8))
        lines = []
        line = reader.readLine()
        while line is not None:
            lines.append(line)
            line = reader.readLine()
        self.content = "\n".join(lines)

reader = ReadJsonCallback()
session.read(flowFile, reader)

rows = json.loads(reader.content)

def normalize_identifier(name):
    if name is None:
        return "unnamed_column"
    name = name.strip().lower()
    name = re.sub(r"\s+", "_", name)
    name = re.sub(r"[^a-z0-9_]", "_", name)
    name = re.sub(r"_+", "_", name)
    name = name.strip("_")
    if not name:
        name = "unnamed_column"
    return name

def safe_int(value):
    if value is None or value == "":
        return None
    try:
        return int(value)
    except:
        return None

def map_type(row):
    data_type = (row.get("DATA_TYPE") or "").lower()
    precision = safe_int(row.get("NUMERIC_PRECISION"))
    scale = safe_int(row.get("NUMERIC_SCALE"))

    if data_type in ("tinyint", "smallint", "int", "bigint"):
        return "INT8"
    elif data_type == "bit":
        return "BOOL"
    elif data_type in ("decimal", "numeric"):
        if precision is not None and scale is not None:
            return "DECIMAL({},{})".format(precision, scale)
        elif precision is not None:
            return "DECIMAL({})".format(precision)
        else:
            return "DECIMAL"
    elif data_type == "money":
        return "DECIMAL(19,4)"
    elif data_type == "smallmoney":
        return "DECIMAL(10,4)"
    elif data_type in ("float", "real"):
        return "FLOAT8"
    elif data_type in ("char", "nchar", "varchar", "nvarchar", "text", "ntext"):
        return "STRING"
    elif data_type in ("binary", "varbinary", "image", "rowversion", "timestamp"):
        return "BYTES"
    elif data_type == "date":
        return "DATE"
    elif data_type in ("datetime", "datetime2", "smalldatetime"):
        return "TIMESTAMP"
    elif data_type == "datetimeoffset":
        return "TIMESTAMPTZ"
    elif data_type == "time":
        return "TIME"
    elif data_type == "uniqueidentifier":
        return "UUID"
    else:
        return "STRING"

# Improvement 1: preserve source column order explicitly
rows = sorted(rows, key=lambda r: safe_int(r.get("ORDINAL_POSITION")) or 0)

dest_catalog = flowFile.getAttribute("destination_table_catalog") or "northwind"
dest_schema = flowFile.getAttribute("destination_table_schema") or "public"
dest_table = flowFile.getAttribute("destination_table_name") or "unknown_table"

column_lines = []
seen_columns = set()

for row in rows:
    src_col = row.get("COLUMN_NAME")
    col_name = normalize_identifier(src_col)

    # Avoid accidental duplicates after normalization
    original_col_name = col_name
    suffix = 2
    while col_name in seen_columns:
        col_name = "{}_{}".format(original_col_name, suffix)
        suffix += 1
    seen_columns.add(col_name)

    crdb_type = map_type(row)
    nullable = (row.get("IS_NULLABLE") or "").upper() == "YES"

    line = "    {} {}".format(col_name, crdb_type)
    if not nullable:
        line += " NOT NULL"

    column_lines.append(line)

# Improvement 2: use IF NOT EXISTS for safer reruns
ddl = "CREATE TABLE IF NOT EXISTS {}.{}.{} (\n{}\n);".format(
    dest_catalog,
    dest_schema,
    dest_table,
    ",\n".join(column_lines)
)

class WriteCallback(OutputStreamCallback):
    def __init__(self, text):
        self.text = text

    def process(self, outputStream):
        outputStream.write(bytearray(self.text.encode("utf-8")))

flowFile = session.write(flowFile, WriteCallback(ddl))
flowFile = session.putAttribute(flowFile, "mime.type", "text/plain")
session.transfer(flowFile, REL_SUCCESS)
