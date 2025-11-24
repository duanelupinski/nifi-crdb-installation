from org.apache.nifi.processor.io import StreamCallback
import json
import random
import string

class PyStreamCallback(StreamCallback):
	def __init__(self, wid, partition):
		self.wid = wid
		self.partition = partition
	
	def process(self, inputStream, outputStream):
		stock = []
		numPartitions = 1000
		numItems = int(100000 / numPartitions)
		for m in range(numItems):
			iid = (m + 1) + (numItems * partition)
			data = ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(26, 50)))
			if random.uniform(0.0, 1.0) <= 0.1:
				i = random.randint(0, len(data) - 8)
				data = data[:i] + 'ORIGINAL' + data[i + 8:]
			item = {
				"s_i_id": str(iid),
				"s_w_id": str(wid),
				"s_quantity": str(random.randint(10, 99)),
				"s_dist_01": ''.join(random.choice(string.ascii_letters) for i in range(24)),
				"s_dist_02": ''.join(random.choice(string.ascii_letters) for i in range(24)),
				"s_dist_03": ''.join(random.choice(string.ascii_letters) for i in range(24)),
				"s_dist_04": ''.join(random.choice(string.ascii_letters) for i in range(24)),
				"s_dist_05": ''.join(random.choice(string.ascii_letters) for i in range(24)),
				"s_dist_06": ''.join(random.choice(string.ascii_letters) for i in range(24)),
				"s_dist_07": ''.join(random.choice(string.ascii_letters) for i in range(24)),
				"s_dist_08": ''.join(random.choice(string.ascii_letters) for i in range(24)),
				"s_dist_09": ''.join(random.choice(string.ascii_letters) for i in range(24)),
				"s_dist_10": ''.join(random.choice(string.ascii_letters) for i in range(24)),
				"s_ytd": "0",
				"s_order_cnt": "0",
				"s_remote_cnt": "0",
				"s_data": data
			}
			stock.append(item)
		outputStream.write(json.dumps(stock).encode('utf-8'))

flowFile = session.get()
if (flowFile != None):
	try:
		flowFile = session.putAttribute(flowFile, 'schema.name', 'stock')
		wid = int(flowFile.getAttribute('newWarehouses'))
		partition = int(flowFile.getAttribute('copy.index'))
		flowFile = session.write(flowFile, PyStreamCallback(wid, partition))
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)