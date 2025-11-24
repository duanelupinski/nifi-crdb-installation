import json

flowFile = session.get()
if (flowFile != None):
	try:
		databaseNodes = json.loads(flowFile.getAttribute('database.nodes'))
		flowFile = session.putAttribute(flowFile, 'nodeAddresses', str(','.join(databaseNodes)))
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)