from datetime import datetime
import math
from multiprocessing import Process
import psycopg2
from random import *
import random
import string
import sys
import time

if len(sys.argv) < 7:
	print('Usage: {0} instance_address (i.e. 192.168.1.32) warehouses (i.e. 10) start (i.e. 2023-10-07T19:05:26.895Z) duration (in minutes i.e. 60) concurrency (i.e. 16) cpus (i.e. 32) [throughput = 16]'.format(sys.argv[0]))
	print('received {0} arguments:'.format(str(len(sys.argv))))
	for i in range(len(sys.argv)):
		print('{0}: {1}'.format(str(i), sys.argv[i]))
	sys.exit(1)

# read input arguments
addr = sys.argv[1]
num_wh = int(sys.argv[2])
start = sys.argv[3]
duration = int(sys.argv[4])
concurrency = int(sys.argv[5])
cpus = int(sys.argv[6])
throughput = 1

# throughput min (1) / low (4) / moderate (8) / high (12) / max (16) / extreme (32)
if len(sys.argv) > 7:
	throughput = int(sys.argv[7])

def new_order_transaction(cursor, num_wh):
	w_id = randint(1, num_wh)
	d_id = randint(1, 10)
	c_id = randint(1, 3000)
	ol_cnt = randint(5, 16)
	rbk = randint(1, 100)

	# initialize values for order line items
	o_entry_d = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')
	o_all_local = 1

	itemIds = [ randint(1, 100000) for i in range(ol_cnt) ]
	if rbk <= 1:
		itemIds[-1] = randint(100001, 200000)

	supIds = [ w_id for i in range(ol_cnt) ]
	# since our foreign keys are partitioned we have to keep the supplier within range
	if num_wh > 1:
		for i in range(ol_cnt):
			if randint(1, 100) == 1:
				max_id = int(math.ceil(w_id / 100.0)) * 100 + 1
				min_id = max_id - 100
				if max_id > num_wh:
					max_id = num_wh + 1
				supIds[i] = choice([w for w in range(min_id, max_id) if w not in [w_id]])
				o_all_local = 0

	qty = [ randint(1, 10) for i in range(ol_cnt) ]

	# querying for warehouse tax
	query = """
		SELECT w_tax \
		FROM warehouse \
		WHERE w_id = {0};
	""".format(w_id)
	cursor.execute(query)
	record = cursor.fetchone()
	w_tax = record[0]

	# querying for district tax and next order id
	query = """
		SELECT d_next_o_id, d_tax \
		FROM district \
		WHERE d_id = {0} AND d_w_id = {1} \
		FOR UPDATE;
	""".format(d_id, w_id)
	cursor.execute(query)
	record = cursor.fetchone()
	o_id = record[0]
	d_tax = record[1]

	# updating the next order id for the district
	query = """
		UPDATE district \
		SET d_next_o_id = {0} + 1 \
		WHERE d_id = {1} AND d_w_id = {2};
	""".format(o_id, d_id, w_id)
	cursor.execute(query)

	# querying discount rate, last name and credit status for the customer
	query = """
		SELECT c_discount, c_last, c_credit \
		FROM customer \
		WHERE c_w_id = {0} \
		  AND c_d_id = {1} \
		  AND c_id = {2};
	""".format(w_id, d_id, c_id)
	cursor.execute(query)
	record = cursor.fetchone()
	c_discount = record[0]
	c_last = record[1]
	c_credit = record[2]

	# adding details to the order and new order tables
	query = """
		INSERT INTO "order" (o_id, o_d_id, o_w_id, o_c_id, \
					 o_entry_d, o_ol_cnt, o_all_local) \
		VALUES ({0}, {1}, {2}, {3}, \
			'{4}', {5}, {6});
	""".format(o_id, d_id, w_id, c_id, o_entry_d, ol_cnt, o_all_local)
	cursor.execute(query)

	query = """
		INSERT INTO new_order (no_o_id, no_d_id, no_w_id) \
		VALUES ({0}, {1}, {2});
	""".format(o_id, d_id, w_id)
	cursor.execute(query)

	# adidng details to the order line table
	for i in range(ol_cnt):
		ol_num = i + 1

		# querying price, name and data for the item
		query = """
			SELECT i_price, i_name , i_data \
			FROM item \
			WHERE i_id = {0};
		""".format(itemIds[i])
		cursor.execute(query)
		record = cursor.fetchone()
		if not record:
			raise IndexError("The item you are looking for is not here")
		i_price = record[0]
		i_name = record[1]
		i_data = record[2]

		# querying quantity, data and district info for the current inventory item
		query = """
			SELECT s_quantity, s_data, s_dist_{0} \
			FROM stock \
			WHERE s_i_id = {1} \
			  AND s_w_id = {2} \
			FOR UPDATE;
		""".format(str(d_id).zfill(2), itemIds[i], supIds[i])
		cursor.execute(query)
		record = cursor.fetchone()
		s_qty = record[0]
		s_data = record[1]
		d_info = record[2]

		# updating inventory for the item
		s_qty -= qty[i]
		if s_qty < 10:
			s_qty += 90
		query = """
			UPDATE stock \
			SET s_quantity = {0}, \
				s_ytd = s_ytd + {1}, \
				s_order_cnt = s_order_cnt + 1, \
				s_remote_cnt = s_remote_cnt + \
				CASE WHEN {2} = 0 THEN 1 ELSE 0 END \
			WHERE s_i_id = {3} \
			  AND s_w_id = {4};
		""".format(s_qty, qty[i], o_all_local, itemIds[i], supIds[i])
		cursor.execute(query)

		# adding details for the order line item
		ol_amt = qty[i] * i_price * (1 + w_tax + d_tax) * (1 - c_discount);
		query = """
			INSERT INTO order_line (ol_o_id, ol_d_id, ol_w_id, ol_number, \
						ol_i_id, ol_supply_w_id, \
						ol_quantity, ol_amount, ol_dist_info) \
			VALUES ({0}, {1}, {2}, {3}, \
				{4}, {5}, \
				{6}, {7}, '{8}');
		""".format(o_id, d_id, w_id, ol_num, itemIds[i], supIds[i], qty[i], ol_amt, d_info)
		cursor.execute(query)

def payment_transaction(cursor, num_wh):
	w_id = randint(1, num_wh)
	d_id = randint(1, 10)
	c_id = randint(1, 3000)
	h_amount = round(random.uniform(1, 5000), 2)
	sbn = randint(1, 100)
	rwh = randint(1, 100)

	# initialize values for customer payment
	h_date = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')
	h_w_id = w_id
	h_d_id = d_id
	if num_wh > 1 and rwh > 85:
		h_w_id = choice([w for w in range(1, num_wh + 1) if w not in [w_id]])
		h_d_id = choice([d for d in range(1, 11) if d not in [d_id]])

	# querying for warehouse information
	query = """
		SELECT w_street_1, w_street_2, w_city, w_state, w_zip, w_name \
		FROM warehouse \
		WHERE w_id = {0} \
		FOR UPDATE;
	""".format(h_w_id)
	cursor.execute(query)
	record = cursor.fetchone()
	w_street_1 = record[0]
	w_street_2 = record[1]
	w_city = record[2]
	w_state = record[3]
	w_zip = record[4]
	w_name = record[5]

	# updating the balance for the warehouse
	query = """
		UPDATE warehouse \
		SET w_ytd = w_ytd + {0} \
		WHERE w_id = {1};
	""".format(h_amount, h_w_id)
	cursor.execute(query)

	# querying for district information
	query = """
		SELECT d_street_1, d_street_2, d_city, d_state, d_zip, d_name \
		FROM district \
		WHERE d_w_id = {0} AND d_id = {1} \
		FOR UPDATE;
	""".format(h_w_id, h_d_id)
	cursor.execute(query)
	record = cursor.fetchone()
	d_street_1 = record[0]
	d_street_2 = record[1]
	d_city = record[2]
	d_state = record[3]
	d_zip = record[4]
	d_name = record[5]

	# updating the balance for the district
	query = """
		UPDATE district \
		SET d_ytd = d_ytd + {0} \
		WHERE d_w_id = {1} AND d_id = {2};
	""".format(h_amount, h_w_id, h_d_id)
	cursor.execute(query)

	if sbn <= 60:
		# querying for random customer last name
		query = """
			SELECT c_last \
			FROM customer \
			WHERE c_w_id = {0} AND c_d_id = {1} \
			ORDER BY random() \
			LIMIT 1;
		""".format(w_id, d_id)
		cursor.execute(query)
		record = cursor.fetchone()
		c_last = record[0]

		# querying for customer id based on last name
		query = """
			SELECT c_id \
			FROM customer \
			WHERE c_w_id = {0} \
			  AND c_d_id = {1} \
			  AND c_last = '{2}' \
			ORDER BY random() \
			LIMIT 1;
		""".format(w_id, d_id, c_last)
		cursor.execute(query)
		record = cursor.fetchone()
		c_id = record[0]

	# querying for customer information
	query = """
		SELECT c_first, c_middle, c_last, \
			   c_street_1, c_street_2, c_city, c_state, c_zip, \
			   c_phone, c_credit, c_credit_lim, \
			   c_discount, c_balance, c_since, c_data \
		FROM customer \
		WHERE c_w_id = {0} \
		  AND c_d_id = {1} \
		  AND c_id = {2};
	""".format(w_id, d_id, c_id)
	cursor.execute(query)
	record = cursor.fetchone()
	c_first = record[0]
	c_middle = record[1]
	c_last = record[2]
	c_street_1 = record[3]
	c_street_2 = record[4]
	c_city = record[5]
	c_state = record[6]
	c_zip = record[7]
	c_phone = record[8]
	c_credit = record[9]
	c_credit_lim = record[10]
	c_discount = record[11]
	c_balance = record[12]
	c_since = record[13]
	c_data = record[14]

	if c_credit == 'BC':
		c_data = "{0} {1} {2} {3} {4} {5:.2f} {6} | {7}".format(c_id, d_id, w_id, h_d_id, h_w_id, h_amount, h_date, c_data)
		c_data = c_data[:500] if len(c_data) > 500 else c_data

	# updating the balance for the customer
	query = """
		UPDATE customer \
		SET c_balance = c_balance - {0}, \
			c_ytd_payment = c_ytd_payment + {0}, \
			c_payment_cnt = c_payment_cnt + 1, \
			c_data = '{1}' \
		WHERE c_w_id = {2} \
		  AND c_d_id = {3} \
		  AND c_id = {4};
	""".format(h_amount, c_data, w_id, d_id, c_id)
	cursor.execute(query)

	# adding payment details to the history table
	h_data = "{0}    {1}".format(w_name, d_name)
	query = """
		INSERT INTO history (h_c_d_id, h_c_w_id, h_c_id, h_d_id, \
					 h_w_id, h_date, h_amount, h_data) \
		VALUES ({0}, {1}, {2}, {3}, \
			{4}, '{5}', {6}, '{7}');
	""".format(d_id, w_id, c_id, h_d_id, h_w_id, h_date, h_amount, h_data)
	cursor.execute(query)

def status_transaction(cursor, num_wh):
	w_id = randint(1, num_wh)
	d_id = randint(1, 10)
	c_id = randint(1, 3000)
	sbn = randint(1, 100)

	if sbn <= 60:
		# querying for random customer last name
		query = """
			SELECT c_last \
			FROM customer \
			WHERE c_w_id = {0} AND c_d_id = {1} \
			ORDER BY random() \
			LIMIT 1;
		""".format(w_id, d_id)
		cursor.execute(query)
		record = cursor.fetchone()
		c_last = record[0]

		# querying for customer id based on last name
		query = """
			SELECT c_id \
			FROM customer \
			WHERE c_w_id = {0} \
			  AND c_d_id = {1} \
			  AND c_last = '{2}' \
			ORDER BY random() \
			LIMIT 1;
		""".format(w_id, d_id, c_last)
		cursor.execute(query)
		record = cursor.fetchone()
		c_id = record[0]

	# querying for customer information
	query = """
		SELECT c_balance, c_first, c_middle, c_last \
		FROM customer \
		WHERE c_w_id = {0} \
		  AND c_d_id = {1} \
		  AND c_id = {2};
	""".format(w_id, d_id, c_id)
	cursor.execute(query)
	record = cursor.fetchone()
	c_balance = record[0]
	c_first = record[1]
	c_middle = record[2]
	c_last = record[3]

	# querying for order information
	query = """
		SELECT o_id, o_carrier_id, o_entry_d \
		FROM "order" \
		WHERE o_w_id = {0} \
		  AND o_d_id = {1} \
		  AND o_c_id = {2} \
		ORDER BY o_id DESC;
	""".format(w_id, d_id, c_id)
	cursor.execute(query)
	record = cursor.fetchone()
	o_id = record[0]
	o_carrier_id = record[1]
	o_entry_d = record[2]

	# querying for line item information
	query = """
		SELECT ol_i_id, ol_supply_w_id, ol_quantity, \
			   ol_amount, ol_delivery_d \
		FROM order_line \
		WHERE ol_o_id = {0} \
		  AND ol_d_id = {1} \
		  AND ol_w_id = {2};
	""".format(o_id, d_id, w_id)
	cursor.execute(query)
	line_items = cursor.fetchall()

def delivery_transaction(cursor, num_wh):
	w_id = randint(1, num_wh)
	r_id = randint(1, 10)

	# initialize values for carrier delivery
	ol_delivery_d = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')

	# querying for districts in the warehouse
	query = """
		SELECT d_id \
		FROM district \
		WHERE d_w_id = {0} \
		ORDER BY d_id;
	""".format(w_id)
	cursor.execute(query)
	districts = cursor.fetchall()

	for d in districts:
		d_id = d[0]

		# querying for the next order to be delivered in the district
		query = """
			SELECT no_o_id  \
			FROM new_order \
			WHERE no_d_id = {0} \
			  AND no_w_id = {1} \
			ORDER BY no_o_id ASC \
			LIMIT 1 \
			FOR UPDATE;
		""".format(d_id, w_id)
		cursor.execute(query)
		record = cursor.fetchone()
		if not record:
			continue
		o_id = record[0]

		# removing order from new order table
		query = """
			DELETE FROM new_order \
			WHERE no_o_id = {0} \
			  AND no_d_id = {1} \
			  AND no_w_id = {2};
		""".format(o_id, d_id, w_id)
		cursor.execute(query)

		# querying order for the customer id
		query = """
			SELECT o_c_id \
			FROM "order" \
			WHERE o_id = {0} \
			  AND o_d_id = {1} \
			  AND o_w_id = {2} \
			FOR UPDATE;
		""".format(o_id, d_id, w_id)
		cursor.execute(query)
		record = cursor.fetchone()
		c_id = record[0]

		# updating carrier for the order
		query = """
			UPDATE "order" \
			SET o_carrier_id = {0} \
			WHERE o_id = {1} \
			  AND o_d_id = {2} \
			  AND o_w_id = {3};
		""".format(r_id, o_id, d_id, w_id)
		cursor.execute(query)

		# querying for the order amount
		query = """
			SELECT SUM(ol_amount) \
			FROM order_line \
			WHERE ol_o_id = {0} \
			  AND ol_d_id = {1} \
			  AND ol_w_id = {2};
		""".format(o_id, d_id, w_id)
		cursor.execute(query)
		record = cursor.fetchone()
		o_total = record[0]

		# updating delivery date for the order
		query = """
			UPDATE order_line \
			SET ol_delivery_d = '{0}' \
			WHERE ol_o_id = {1} \
			  AND ol_d_id = {2} \
			  AND ol_w_id = {3};
		""".format(ol_delivery_d, o_id, d_id, w_id)
		cursor.execute(query)

		# updating customer balance for the order
		query = """
			UPDATE customer \
			SET c_balance = c_balance + {0} \
			WHERE c_id = {1} \
			  AND c_d_id = {2} \
			  AND c_w_id = {3};
		""".format(o_total, c_id, d_id, w_id)
		cursor.execute(query)

def inventory_transaction(cursor, num_wh):
	w_id = randint(1, num_wh)
	d_id = randint(1, 10)
	qty = randint(10, 20)

	# querying for next order id
	query = """
		SELECT d_next_o_id \
		FROM district \
		WHERE d_w_id = {0} \
		  AND d_id = {1};
	""".format(w_id, d_id)
	cursor.execute(query)
	record = cursor.fetchone()
	next_o_id = record[0]

	# querying for items with low inventory
	query = """
		SELECT COUNT(DISTINCT (s_i_id)) \
		FROM order_line, stock \
		WHERE ol_w_id = {0} \
		  AND ol_d_id = {1} \
		  AND ol_o_id < {2} \
		  AND ol_o_id >= {2} - 20 \
		  AND s_w_id = {0} \
		  AND s_i_id = ol_i_id \
		  AND s_quantity < {3};
	""".format(w_id, d_id, next_o_id, qty)
	cursor.execute(query)
	record = cursor.fetchone()
	low_cnt = record[0]

def run_transactions(addr: string, end: int, num_wh: int):
	# establish a single connection to execute database transactions
	try:
		# establish a connection to the database
		connection = psycopg2.connect(
			database='postgres',
			user='postgres',
			host=addr,
			port='4432',
			connect_timeout=5
		)

		# disable autocommit mode
		connection.autocommit = False

		# creating a cursor object
		cursor = connection.cursor()
		cursor.execute("SET lock_timeout TO '5s'")

		# use the connection as long as possible
		while int(time.time() * 1000) < end:
			new_order_transaction(cursor, num_wh)
			connection.commit()
			payment_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			new_order_transaction(cursor, num_wh)
			connection.commit()
			payment_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			new_order_transaction(cursor, num_wh)
			connection.commit()
			payment_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			new_order_transaction(cursor, num_wh)
			connection.commit()
			payment_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			new_order_transaction(cursor, num_wh)
			connection.commit()
			payment_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			new_order_transaction(cursor, num_wh)
			connection.commit()
			payment_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			new_order_transaction(cursor, num_wh)
			connection.commit()
			payment_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			new_order_transaction(cursor, num_wh)
			connection.commit()
			payment_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			new_order_transaction(cursor, num_wh)
			connection.commit()
			payment_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			new_order_transaction(cursor, num_wh)
			connection.commit()
			payment_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			payment_transaction(cursor, num_wh)
			connection.commit()
			status_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			payment_transaction(cursor, num_wh)
			connection.commit()
			status_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			payment_transaction(cursor, num_wh)
			connection.commit()
			status_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			payment_transaction(cursor, num_wh)
			connection.commit()
			status_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			payment_transaction(cursor, num_wh)
			connection.commit()
			status_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			payment_transaction(cursor, num_wh)
			connection.commit()
			status_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			payment_transaction(cursor, num_wh)
			connection.commit()
			status_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			payment_transaction(cursor, num_wh)
			connection.commit()
			status_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			payment_transaction(cursor, num_wh)
			connection.commit()
			delivery_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)
			payment_transaction(cursor, num_wh)
			connection.commit()
			inventory_transaction(cursor, num_wh)
			connection.commit()
			sleep(0.05)

	except (IndexError) as missing:
		#print("This is not going to work: {0}".format(missing))
		if connection:
			connection.rollback()

	except (Exception, psycopg2.DatabaseError) as error:
		print("There's a slight problem: {0}".format(error))
		if connection:
			connection.rollback()

	finally:
		# closing database connection
		if cursor:
			cursor.close()
		if connection:
			connection.close()

def run_process(addr: string, end: int, num_wh: int):
	# continue until time runs out
	while int(time.time() * 1000) < end:
		run_transactions(addr, end, num_wh)

if __name__ == "__main__":

	# determine when execution should stop
	date = datetime.strptime(start, '%Y-%m-%dT%H:%M:%S.%fZ')
	timestamp = str((date - datetime(1970, 1, 1)).total_seconds()*1000)
	end = int(timestamp[:-2]) + duration * 60000

	# determine number of connections to use and start subprocesses
	connections = math.ceil((cpus * 3 / 4) * throughput / concurrency)
	proc = []
	for i in range(connections):
		p = Process(target=run_process, kwargs={"addr": addr, "end": end, "num_wh": num_wh})
		p.start()
		proc.append(p)
	for p in proc:
		p.join()

	# if we need to return a value
	#sys.stdout.write('true')
