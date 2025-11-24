from datetime import datetime
from org.apache.nifi.processor.io import StreamCallback
import json
import random
import string

names = ['BAR', 'OUGHT', 'ABLE', 'PRI', 'PRES', 'ESE', 'ANTI', 'CALLY', 'ATION', 'EING']

class PyStreamCallback(StreamCallback):
	def __init__(self, wid, partition):
		self.wid = wid
		self.partition = partition
	
	def process(self, inputStream, outputStream):
		customers = []
		numPartitions = 300
		numDistricts = 10
		districtCustomers = int(3000 / numPartitions)
		for d in range(numDistricts):
			did = d + 1
			for c in range(districtCustomers):
				cid = (c + 1) + (districtCustomers * partition)
				credit = 'GC'
				if random.uniform(0.0, 1.0) <= 0.1:
					credit = 'BC'
				customer = {
					"c_id": str(cid),
					"c_d_id": str(did),
					"c_w_id": str(wid),
					"c_first": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(8, 16))),
					"c_middle": 'OE',
					"c_last": names[random.randint(0, 9)] + names[random.randint(0, 9)] + names[random.randint(0, 9)],
					"c_street_1": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(10, 20))),
					"c_street_2": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(10, 20))),
					"c_city": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(10, 20))),
					"c_state": ''.join(random.choice(string.ascii_letters) for i in range(2)),
					"c_zip": ''.join(random.choice(string.digits) for i in range(4)) + '11111',
					"c_phone": ''.join(random.choice(string.digits) for i in range(16)),
					"c_since": datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f'),
					"c_credit": credit,
					"c_credit_lim": "50000.00",
					"c_discount": str(round(random.uniform(0.0, 0.5), 4)),
					"c_balance": "-10.00",
					"c_ytd_payment": "10.00",
					"c_payment_cnt": "1",
					"c_delivery_cnt": "0",
					"c_data": ''.join(random.choice(string.ascii_letters + string.digits) for i in range(random.randint(300, 500)))
				}
				customers.append(customer)
		outputStream.write(json.dumps(customers).encode('utf-8'))

flowFile = session.get()
if (flowFile != None):
	try:
		flowFile = session.putAttribute(flowFile, 'schema.name', 'customer')
		wid = int(flowFile.getAttribute('newWarehouses'))
		partition = int(flowFile.getAttribute('copy.index'))
		flowFile = session.write(flowFile, PyStreamCallback(wid, partition))
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)