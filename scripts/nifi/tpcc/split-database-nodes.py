import json

flowFile = session.get()
if (flowFile != None):
	try:
		flowFiles = []
		databaseName = flowFile.getAttribute('database.name')
		databaseNodes = json.loads(flowFile.getAttribute('database.nodes'))
		for index, node in enumerate(databaseNodes):
			newFlowFile = session.create(flowFile)
			newFlowFile = session.putAttribute(newFlowFile, 'database.name', databaseName + "-" + str(index))
			newFlowFile = session.putAttribute(newFlowFile, 'database.address', node)
			flowFiles.append(newFlowFile)
		session.remove(flowFile)
		session.transfer(flowFiles, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)