from org.apache.nifi.processor.io import OutputStreamCallback
from org.apache.commons.io import IOUtils
from java.nio.charset import StandardCharsets
import json

class PyOutputStreamCallback(OutputStreamCallback):
	def __init__(self, data):
		self.data = data
	
	def process(self, outputStream):
		outputStream.write(json.dumps(data['database']['map']).encode('utf-8'))

flowFile = session.get()
if (flowFile != None):
	try:
		flowFile = session.putAttribute(flowFile, 'testCycle', '-1')
		flowFiles = []
		inputStream = session.read(flowFile)
		text = IOUtils.toString(inputStream, StandardCharsets.UTF_8)
		inputStream.close()
		data = json.loads(text)
		testCycles = data['testCycles']
		for test in testCycles:
			newFlowFile = session.create(flowFile)
			newFlowFile = session.putAttribute(newFlowFile, 'test', json.dumps(test).encode('utf-8'))
			newFlowFile = session.write(newFlowFile, PyOutputStreamCallback(data))
			flowFiles.append(newFlowFile)
		session.remove(flowFile)
		session.transfer(flowFiles, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)