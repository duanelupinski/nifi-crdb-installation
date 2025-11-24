from datetime import datetime
from org.apache.nifi.processor.io import StreamCallback
import json
import random

class PyStreamCallback(StreamCallback):
	def __init__(self, wid, partition):
		self.wid = wid
		self.partition = partition
	
	def process(self, inputStream, outputStream):
		orders = []
		numPartitions = 300
		numDistricts = 10
		districtOrders = 3000 / numPartitions
		for d in range(numDistricts):
			did = d + 1
			for o in range(districtOrders):
				oid = (o + 1) + (districtOrders * partition)
				order = {
					"o_id": str(oid),
					"o_d_id": str(did),
					"o_w_id": str(wid),
					"o_c_id": str((oid + 4321) % 3000 + 1),
					"o_entry_d": datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f'),
					"o_ol_cnt": str(random.randint(5, 15)),
					"o_all_local": "1"
				}
				if oid < 2101:
					order['o_carrier_id'] = str(random.randint(1, 10))
				orders.append(order)
		outputStream.write(json.dumps(orders).encode('utf-8'))

flowFile = session.get()
if (flowFile != None):
	try:
		flowFile = session.putAttribute(flowFile, 'schema.name', 'order')
		wid = int(flowFile.getAttribute('newWarehouses'))
		partition = int(flowFile.getAttribute('copy.index'))
		flowFile = session.write(flowFile, PyStreamCallback(wid, partition))
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)