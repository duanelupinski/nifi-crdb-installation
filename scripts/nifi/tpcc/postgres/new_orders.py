from org.apache.nifi.processor.io import StreamCallback
import json

class PyStreamCallback(StreamCallback):
	def __init__(self, wid, partition):
		self.wid = wid
		self.partition = partition
	
	def process(self, inputStream, outputStream):
		orders = []
		numPartitions = 90
		numDistricts = 10
		districtOrders = int(900 / numPartitions)
		for d in range(numDistricts):
			did = d + 1
			for o in range(districtOrders):
				oid = (o + 2101) + (districtOrders * partition)
				order = {
					"no_o_id": str(oid),
					"no_d_id": str(did),
					"no_w_id": str(wid)
				}
				orders.append(order)
		outputStream.write(json.dumps(orders).encode('utf-8'))

flowFile = session.get()
if (flowFile != None):
	try:
		flowFile = session.putAttribute(flowFile, 'schema.name', 'new_order')
		wid = int(flowFile.getAttribute('newWarehouses'))
		partition = int(flowFile.getAttribute('copy.index'))
		flowFile = session.write(flowFile, PyStreamCallback(wid, partition))
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)