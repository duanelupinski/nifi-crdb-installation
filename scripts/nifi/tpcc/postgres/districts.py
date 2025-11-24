from org.apache.nifi.processor.io import StreamCallback
import json
import random
import string

class PyStreamCallback(StreamCallback):
	def __init__(self, wid):
		self.wid = wid
	
	def process(self, inputStream, outputStream):
		districts = []
		numDistricts = 10
		for d in range(numDistricts):
			did = d + 1
			district = {
				"d_id": str(did),
				"d_w_id": str(wid),
				"d_name": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(6, 10))),
				"d_street_1": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(10, 20))),
				"d_street_2": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(10, 20))),
				"d_city": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(10, 20))),
				"d_state": ''.join(random.choice(string.ascii_letters) for i in range(2)),
				"d_zip": ''.join(random.choice(string.digits) for i in range(4)) + '11111',
				"d_tax": str(round(random.uniform(0.0, 0.2), 4)),
				"d_ytd": "30000.00",
				"d_next_o_id": "3001"
			}
			districts.append(district)
		outputStream.write(json.dumps(districts).encode('utf-8'))

flowFile = session.get()
if (flowFile != None):
	try:
		flowFile = session.putAttribute(flowFile, 'schema.name', 'district')
		wid = int(flowFile.getAttribute('newWarehouses'))
		flowFile = session.write(flowFile, PyStreamCallback(wid))
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)