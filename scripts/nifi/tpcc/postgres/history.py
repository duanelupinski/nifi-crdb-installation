from datetime import datetime
from org.apache.nifi.processor.io import StreamCallback
import json
import random
import string

class PyStreamCallback(StreamCallback):
	def __init__(self, wid, partition):
		self.wid = wid
		self.partition = partition
	
	def process(self, inputStream, outputStream):
		history = []
		numPartitions = 300
		numDistricts = 10
		districtCustomers = 3000 /  numPartitions
		for d in range(numDistricts):
			did = d + 1
			for c in range(districtCustomers):
				cid = (c + 1) + (districtCustomers * partition)
				record = {
					"h_c_id": str(cid),
					"h_c_d_id": str(did),
					"h_c_w_id": str(wid),
					"h_d_id": str(did),
					"h_w_id": str(wid),
					"h_date": datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f'),
					"h_amount": "10.00",
					"h_data": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(12, 24)))
				}
				history.append(record)
		outputStream.write(json.dumps(history).encode('utf-8'))

flowFile = session.get()
if (flowFile != None):
	try:
		flowFile = session.putAttribute(flowFile, 'schema.name', 'history')
		wid = int(flowFile.getAttribute('newWarehouses'))
		partition = int(flowFile.getAttribute('copy.index'))
		flowFile = session.write(flowFile, PyStreamCallback(wid, partition))
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)