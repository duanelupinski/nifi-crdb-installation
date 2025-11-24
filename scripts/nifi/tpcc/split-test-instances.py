
flowFile = session.get()
if (flowFile != None):
	try:
		flowFiles = []
		testInstances = flowFile.getAttribute('testInstances').split(",")
		for instance in testInstances:
			newFlowFile = session.create(flowFile)
			newFlowFile = session.putAttribute(newFlowFile, 'testInstances', instance)
			flowFiles.append(newFlowFile)
		session.remove(flowFile)
		session.transfer(flowFiles, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)