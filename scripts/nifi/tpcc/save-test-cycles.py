from org.apache.nifi.processor.io import StreamCallback
from org.apache.commons.io import IOUtils
from java.nio.charset import StandardCharsets
import json
from datetime import datetime
import random

testCycles = None

class PyStreamCallback(StreamCallback):
	def process(self, inputStream, outputStream):
		global testCycles
		text = IOUtils.toString(inputStream, StandardCharsets.UTF_8)
		test = json.loads(text)
		outputStream.write(json.dumps(test['database']['map']).encode('utf-8'))
		testCycles = json.dumps(test['testCycles']).encode('utf-8')

flowFile = session.get()
if (flowFile != None):
	try:
		flowFile = session.putAttribute(flowFile, 'testCycle', '0')
		flowFile = session.write(flowFile, PyStreamCallback())
		while testCycles == None:
			pass
		flowFile = session.putAttribute(flowFile, 'testCycles', testCycles)
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)