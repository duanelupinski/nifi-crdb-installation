from org.apache.nifi.processor.io import StreamCallback
from org.apache.commons.io import IOUtils
from java.nio.charset import StandardCharsets
import json

databaseAddresses = None

class PyStreamCallback(StreamCallback):
	def process(self, inputStream, outputStream):
		global databaseAddresses
		text = IOUtils.toString(inputStream, StandardCharsets.UTF_8)
		databases = json.loads(text)
		outputStream.write(json.dumps(databases).encode('utf-8'))
		addressArray=[]
		for database in databases:
			addressArray.extend(database['nodes'])
		databaseAddresses = str(','.join(addressArray))

flowFile = session.get()
if (flowFile != None):
	try:
		flowFile = session.write(flowFile, PyStreamCallback())
		while databaseAddresses == None:
			pass
		flowFile = session.putAttribute(flowFile, 'databaseAddresses', databaseAddresses)
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)