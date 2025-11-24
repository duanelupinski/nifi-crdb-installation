
from org.apache.nifi.processor.io import StreamCallback
from org.apache.commons.io import IOUtils
from java.nio.charset import StandardCharsets
import json

class PyStreamCallback(StreamCallback):
    def __init__(self, catalog, schema, table):
        self.catalog = catalog
        self.schema = schema
        self.table = table

    def process(self, inputStream, outputStream):
        payload = IOUtils.toString(inputStream, StandardCharsets.UTF_8)
        columns = json.loads(payload)

        ddl = 'CREATE TABLE IF NOT EXISTS ' + schema + '.' + table + '( '
        for col in columns:
            name = col['COLUMN_NAME']
            type = col['DATA_TYPE']
            length = col['CHARACTER_MAXIMUM_LENGTH']
            precision = col['NUMERIC_PRECISION']
            scale = col['NUMERIC_SCALE']
            datetime_precision = col['DATETIME_PRECISION']
            nullable = col['IS_NULLABLE']
            default = col['COLUMN_DEFAULT']

            ddl += name + ' ' + type
            if (type == 'decimal' or type == 'numeric'):
                if (precision is not None and scale is not None and int(scale) > 0):
                    ddl += '(' + precision + ', ' + scale + ') '
                elif (precision is not None):
                    ddl += '(' + precision + ') '
                else:
                    ddl += ' '
			elif (datetime_precision is not None):
                ddl += '(' + datetime_precision + ') '
			elif (length is not None):
                ddl += '(' + length + ') '
            else:
                ddl += ' '

            if (nullable == 'NO'):
                ddl += 'NOT NULL '
            else:
                ddl += 'NULL '

            if (default is not None):
                ddl += 'DEFAULT ' + default + ', '
            else:
                ddl += ', '

        ddl = ddl[:-2]
        ddl += ")"

        outputStream.write(ddl.encode('utf-8'))

flowFile = session.get()
if (flowFile != None):
    try:
        catalog = flowFile.getAttribute('db.table.catalog')
        schema = flowFile.getAttribute('db.table.schema')
        table = flowFile.getAttribute('db.table.name')
        flowFile = session.write(flowFile, PyStreamCallback(catalog, schema, table))
        session.transfer(flowFile, REL_SUCCESS)
    except Exception as e:
        log.error(str(e))
        session.transfer(flowFile, REL_FAILURE)