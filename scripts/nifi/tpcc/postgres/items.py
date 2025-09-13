from org.apache.nifi.processor.io import StreamCallback
import json
import random
import string

class PyStreamCallback(StreamCallback):
	def __init__(self, partition):
		self.partition = partition
	
	def process(self, inputStream, outputStream):
		items = []
		numPartitions = 1000
		numItems = int(100000 / numPartitions)
		for m in range(numItems):
			iid = (m + 1) + (numItems * partition)
			data = ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(26, 50)))
			if random.uniform(0.0, 1.0) <= 0.1:
				i = random.randint(0, len(data) - 8)
				data = data[:i] + 'ORIGINAL' + data[i + 8:]
			item = {
				"i_id": str(iid),
				"i_im_id": str(random.randint(1, 10000)),
				"i_name": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(14, 24))),
				"i_price": str(round(random.uniform(1.0, 100.0), 2)),
				"i_data": data
			}
			items.append(item)
		outputStream.write(json.dumps(items).encode('utf-8'))

flowFile = session.get()
if (flowFile != None):
	try:
		flowFile = session.putAttribute(flowFile, 'schema.name', 'item')
		partition = int(flowFile.getAttribute('copy.index'))
		flowFile = session.write(flowFile, PyStreamCallback(partition))
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)