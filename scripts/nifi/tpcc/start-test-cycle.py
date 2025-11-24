import json
import string

flowFile = session.get()
if (flowFile != None):
	try:
		test = None
		cycle = int(flowFile.getAttribute('testCycle'))
		if cycle == -1:
			test = json.loads(flowFile.getAttribute('test'))
		else:
			cycles = json.loads(flowFile.getAttribute('testCycles'))
			if 0 <= cycle < len(cycles):
				test = cycles[cycle]
		
		if test is None:
			flowFile = session.removeAttribute(flowFile, 'numWarehouses')
			flowFile = session.removeAttribute(flowFile, 'testClient')
			flowFile = session.removeAttribute(flowFile, 'testProvider')
			flowFile = session.removeAttribute(flowFile, 'terraformResource')
			flowFile = session.removeAttribute(flowFile, 'terraformResourceName')
			flowFile = session.removeAttribute(flowFile, 'terraformComponent')
			flowFile = session.removeAttribute(flowFile, 'terraformComponentName')
			flowFile = session.removeAttribute(flowFile, 'terraformKeyName')
			flowFile = session.removeAttribute(flowFile, 'terraformKeyUser')
			flowFile = session.removeAttribute(flowFile, 'testWorkload')
			flowFile = session.removeAttribute(flowFile, 'testTarget')
			flowFile = session.removeAttribute(flowFile, 'testScenario')
			flowFile = session.removeAttribute(flowFile, 'testScale')
			flowFile = session.removeAttribute(flowFile, 'testThroughput')
			flowFile = session.removeAttribute(flowFile, 'testIteration')
			flowFile = session.removeAttribute(flowFile, 'testDuration')
			flowFile = session.removeAttribute(flowFile, 'testConcurrency')
			flowFile = session.removeAttribute(flowFile, 'testInstances')
		else:
			attrMap = {}
			if 'warehouses' in test:
				attrMap['numWarehouses'] = str(test['warehouses'])
			else:
				flowFile = session.removeAttribute(flowFile, 'numWarehouses')
			attrMap['testClient'] = str(test['client'])
			attrMap['testProvider'] = str(test['provider'])
			attrMap['terraformResource'] = str(test['resource'])
			attrMap['terraformResourceName'] = str(test['resourceName'])
			attrMap['terraformComponent'] = str(test['component'])
			attrMap['terraformComponentName'] = str(test['componentName'])
			if 'keyname' in test:
				attrMap['terraformKeyName'] = str(test['keyname'])
			else:
				flowFile = session.removeAttribute(flowFile, 'terraformKeyName')
			if 'keyuser' in test:
				attrMap['terraformKeyUser'] = str(test['keyuser'])
			else:
				flowFile = session.removeAttribute(flowFile, 'terraformKeyUser')
			attrMap['testWorkload'] = str(test['workload'])
			attrMap['testTarget'] = str(test['target'])
			attrMap['testScenario'] = str(test['scenario'])
			attrMap['testScale'] = str(test['scale'])
			attrMap['testThroughput'] = str(test['throughput'])
			attrMap['testIteration'] = str(test['iteration'])
			attrMap['testDuration'] = str(test['duration'])
			if 'concurrency' in test:
				attrMap['testConcurrency'] = str(test['concurrency'])
			else:
				flowFile = session.removeAttribute(flowFile, 'testConcurrency')
			attrMap['testInstances'] = str(','.join(test['instances']))
			attrMap['testCycle'] = str(cycle + 1)
			
			#update paths using client, provider, workload and target attributes
			attrMap['terraformPath'] = '/'.join([
				flowFile.getAttribute('terraformBase'),
				attrMap['testClient'],
				attrMap['testProvider'],
				attrMap['testWorkload'],
				attrMap['testTarget']
			])
			attrMap['dataPath'] = '/'.join([
				flowFile.getAttribute('hostData'),
				'export',
				attrMap['testWorkload'],
				attrMap['testTarget']
			])
			attrMap['metricsPath'] = '/'.join([
				flowFile.getAttribute('hostData'),
				attrMap['testClient'],
				attrMap['testProvider'],
				attrMap['testWorkload'],
				attrMap['testTarget']
			])
			
			flowFile = session.putAllAttributes(flowFile, attrMap)
		session.transfer(flowFile, REL_SUCCESS)
	except Exception as e:
		log.error(str(e))
		session.transfer(flowFile, REL_FAILURE)