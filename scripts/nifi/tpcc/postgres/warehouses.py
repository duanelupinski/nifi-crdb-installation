from org.apache.nifi.processor.io import StreamCallback
import json
import random
import string

class PyStreamCallback(StreamCallback):
	def __init__(self, wid):
		self.wid = wid
	
	def process(self, inputStream, outputStream):
		warehouse = {
			"w_id": str(wid),
			"w_name": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(6, 10))),
			"w_street_1": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(10, 20))),
			"w_street_2": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(10, 20))),
			"w_city": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(10, 20))),
			"w_state": ''.join(random.choice(string.ascii_letters) for i in range(2)),
			"w_zip": ''.join(random.choice(string.digits) for i in range(4)) + '11111',
			"w_tax": str(round(random.uniform(0.0, 0.2), 4)),
			"w_ytd": "300000.00"
		}
		outputStream.write(json.dumps(warehouse).encode('utf-8'))

flowFile = session.get()
if (flowFile != None):
	try:
		wid = int(flowFile.getAttribute('newWarehouses'))
		flowFile = session.putAttribute(flowFile, 'schema.name', 'warehouse')
		flowFile = session.write(flowFile, PyStreamCallback(wid))
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)