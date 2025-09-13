from datetime import datetime
from java.nio.charset import StandardCharsets
from org.apache.commons.io import IOUtils
from org.apache.nifi.processor.io import StreamCallback
import json
import random
import string

class PyStreamCallback(StreamCallback):
	def process(self, inputStream, outputStream):
		payload = IOUtils.toString(inputStream, StandardCharsets.UTF_8)
		orders = json.loads(payload)
		lines = []
		for order in orders:
			for id in range(int(order['o_ol_cnt'])):
				oid = int(order['o_id'])
				line = {
					"ol_o_id": str(order['o_id']),
					"ol_d_id": str(order['o_d_id']),
					"ol_w_id": str(order['o_w_id']),
					"ol_number": str(id + 1),
					"ol_i_id": str(random.randint(1, 100000)),
					"ol_supply_w_id": str(order['o_w_id']),
					"ol_quantity": "5",
					"ol_dist_info": ''.join(random.choice(string.ascii_letters) for i in range(24))
				}
				if oid >= 2101:
					line['ol_amount'] = str(round(random.uniform(0.01, 9999.99), 2))
				else:
					line['ol_amount'] = "0.0"
					line['ol_delivery_d'] = order['o_entry_d']
				lines.append(line)
		outputStream.write(json.dumps(lines).encode('utf-8'))

flowFile = session.get()
if (flowFile != None):
	try:
		flowFile = session.putAttribute(flowFile, 'schema.name', 'order_line')
		flowFile = session.write(flowFile, PyStreamCallback())
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)