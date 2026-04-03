import groovy.json.JsonSlurper
import org.apache.nifi.processor.io.InputStreamCallback
import org.apache.nifi.processor.io.OutputStreamCallback
import java.nio.charset.StandardCharsets

def flowFile = session.get()
if (flowFile == null) {
    return
}

def content = new StringBuilder()

session.read(flowFile, { inputStream ->
    content.append(inputStream.getText(StandardCharsets.UTF_8.name()))
} as InputStreamCallback)

def rows = new JsonSlurper().parseText(content.toString())

String normalizeIdentifier(String name) {
    if (name == null) {
        return "unnamed_column"
    }

    String s = name.trim().toLowerCase()
    StringBuilder out = new StringBuilder()
    boolean lastUnderscore = false

    for (int i = 0; i < s.length(); i++) {
        char c = s.charAt(i)

        boolean isAlphaNum =
            (c >= 'a' && c <= 'z') ||
            (c >= '0' && c <= '9')

        if (isAlphaNum) {
            out.append(c)
            lastUnderscore = false
        } else {
            if (!lastUnderscore) {
                out.append('_')
                lastUnderscore = true
            }
        }
    }

    String result = out.toString()

    while (result.startsWith("_")) {
        result = result.substring(1)
    }
    while (result.endsWith("_")) {
        result = result.substring(0, result.length() - 1)
    }

    if (result == null || result.length() == 0) {
        result = "unnamed_column"
    }

    return result
}

Integer safeInt(def value) {
    if (value == null) {
        return null
    }
    String s = value.toString().trim()
    if (s.length() == 0) {
        return null
    }
    try {
        return Integer.parseInt(s)
    } catch (Exception e) {
        return null
    }
}

String mapType(def row) {
    def dataType = (row.DATA_TYPE ?: "").toString().toLowerCase()
    def precision = safeInt(row.NUMERIC_PRECISION)
    def scale = safeInt(row.NUMERIC_SCALE)

    switch (dataType) {
        case ["tinyint", "smallint", "int", "bigint"]:
            return "INT8"
        case "bit":
            return "BOOL"
        case ["decimal", "numeric"]:
            if (precision != null && scale != null) {
                return "DECIMAL(${precision},${scale})"
            } else if (precision != null) {
                return "DECIMAL(${precision})"
            } else {
                return "DECIMAL"
            }
        case "money":
            return "DECIMAL(19,4)"
        case "smallmoney":
            return "DECIMAL(10,4)"
        case ["float", "real"]:
            return "FLOAT8"
        case ["char", "nchar", "varchar", "nvarchar", "text", "ntext"]:
            return "STRING"
        case ["binary", "varbinary", "image", "rowversion", "timestamp"]:
            return "BYTES"
        case "date":
            return "DATE"
        case ["datetime", "datetime2", "smalldatetime"]:
            return "TIMESTAMP"
        case "datetimeoffset":
            return "TIMESTAMPTZ"
        case "time":
            return "TIME"
        case "uniqueidentifier":
            return "UUID"
        default:
            return "STRING"
    }
}

if (!(rows instanceof List)) {
    rows = [rows]
}

rows = rows.sort { row ->
    safeInt(row.ORDINAL_POSITION) ?: 0
}

def destCatalog = flowFile.getAttribute("destination_table_catalog") ?: "northwind"
def destSchema = flowFile.getAttribute("destination_table_schema") ?: "public"
def destTable = flowFile.getAttribute("destination_table_name") ?: "unknown_table"

if (destTable.contains("=")) {
    destTable = destTable.split("=", 2)[1].trim()
}

destCatalog = normalizeIdentifier(destCatalog)
destSchema = normalizeIdentifier(destSchema)
destTable = normalizeIdentifier(destTable)

def columnLines = []
def seenColumns = [] as Set

rows.each { row ->
    def srcCol = row.COLUMN_NAME?.toString()
    def colName = normalizeIdentifier(srcCol)

    def baseColName = colName
    def suffix = 2
    while (seenColumns.contains(colName)) {
        colName = baseColName + "_" + suffix
        suffix++
    }
    seenColumns.add(colName)

    def crdbType = mapType(row)
    def nullable = ((row.IS_NULLABLE ?: "").toString().toUpperCase() == "YES")

    def line = "    " + colName + " " + crdbType
    if (!nullable) {
        line += " NOT NULL"
    }

    columnLines << line
}

if (columnLines.isEmpty()) {
    flowFile = session.putAttribute(flowFile, "ddl.error", "No columns found in input JSON")
    session.transfer(flowFile, REL_FAILURE)
    return
}

def ddl = "CREATE TABLE IF NOT EXISTS " +
    destCatalog + "." + destSchema + "." + destTable + " (\n" +
    columnLines.join(",\n") + "\n);"

flowFile = session.write(flowFile, { outputStream ->
    outputStream.write(ddl.getBytes(StandardCharsets.UTF_8))
} as OutputStreamCallback)

flowFile = session.putAttribute(flowFile, "mime.type", "text/plain")
session.transfer(flowFile, REL_SUCCESS)