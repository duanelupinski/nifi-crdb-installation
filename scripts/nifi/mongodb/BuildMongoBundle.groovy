/*
 * BuildMongoBundle.groovy
 * ExecuteScript (Groovy) for Apache NiFi
 *
 * IN:
 *   FlowFile content: JSON containing at least {"schemaConversion": {...}}.
 *   Optionally also: {"collections":[ { name, filters?, sampling?, fieldTransforms? }, ... ]}
 *
 *   FlowFile attributes:
 *     source.mongo.connection.uri       (required)
 *     source.mongo.database             (required)
 *     collection.name                   (required) -> selects which collections[i] applies
 *
 * OUT (unchanged core shape):
 *   {
 *     "schemaConversion": {...},
 *     "mongoValidator": {...} | null,
 *     "samples": [ {...}, ... ],
 *     "meta": {
 *        "db": "...",
 *        "collection": "...",
 *        "filters": {...} | null,
 *        "sampling": {
 *          "size": N, "strategy": "random|prefix|time_window", "hint": "..."
 *        }
 *     },
 *     "fieldTransforms": [ ... ]
 *   }
 */

import org.apache.nifi.flowfile.FlowFile
import org.apache.nifi.logging.ComponentLog
import org.apache.nifi.processor.io.StreamCallback

import groovy.json.JsonSlurper
import groovy.json.JsonOutput
import java.nio.charset.StandardCharsets

// Mongo Driver
import com.mongodb.ConnectionString
import com.mongodb.MongoClientSettings
import com.mongodb.MongoCredential
import com.mongodb.client.MongoClients
import com.mongodb.client.MongoCollection
import com.mongodb.client.MongoDatabase
import com.mongodb.client.model.Sorts
import org.bson.Document

class BundleCallback implements StreamCallback {

    def context
    def flowFile
    def log

    BundleCallback(context, flowFile, log) {
        this.context = context
        this.flowFile = flowFile
        this.log = log
    }

    @Override
    void process(InputStream inStream, OutputStream outStream) throws IOException {
        def slurper = new JsonSlurper()
        def root = slurper.parse(inStream) ?: [:]
        def payload = (root?.collection instanceof Map) ? root.collection : root
        def schemaConversion = payload?.schemaConversion ?: [:]

        // ---- required connection selectors
        String uri      = flowFile.getAttribute("source.mongo.connection.uri")
        String dbName   = flowFile.getAttribute("source.mongo.database")
        String collName = flowFile.getAttribute("collection.name")
        if (!uri || !dbName || !collName) {
            throw new RuntimeException("Missing one or more required attributes: source.mongo.connection.uri, source.mongo.database, collection.name")
        }


        // filters
        Document filterDoc = new Document()
        def filters = payload.containsKey("filters") ? (payload.filters ?: [:]) : null

        if (filters != null) {
            // payload provided filters (as Map)
            try {
                filterDoc = new Document(filters as Map)
            } catch (Exception e) {
                log.warn("collections[].filters not a Map; defaulting to {}. Error: ${e.message}")
                filterDoc = new Document()
            }
        }

        // sampling controls
        def sampling = (payload.sampling instanceof Map) ? payload.sampling : [:]
        int sampleSize = (sampling.size ?: "1000") as int
        String sampleStrategy = (sampling.strategy ?: "random") as String   // random | prefix | time_window
        String sampleHint = (sampling.hint ?: "") as String                 // index name or JSON string; used on find()

        def connStr = new ConnectionString(uri)
        def builder = MongoClientSettings.builder().applyConnectionString(connStr)

        String username = flowFile.getAttribute("source.mongo.username")
        String authDb   = flowFile.getAttribute("source.mongo.authDb") ?: "admin"
        String password = flowFile.getAttribute("source.mongo.password")

        if (username && password) {
            builder = builder.credential(
                MongoCredential.createScramSha256Credential(
                    username, authDb, password.toCharArray()
                )
            )
        }

        def settings = builder.build()
        def mongoValidator = null
        def samples = []
        def client = MongoClients.create(settings)
        try {
            MongoDatabase db = client.getDatabase(dbName)

            // 1) Try to fetch $jsonSchema validator
            try {
                def cmd = new Document("listCollections", 1).append("filter", new Document("name", collName))
                def result = db.runCommand(cmd)
                def cursor = result.get("cursor", Document.class)
                def firstBatch = cursor.get("firstBatch", ArrayList.class)
                if (firstBatch && !firstBatch.isEmpty()) {
                    def collDoc = (Document) firstBatch.get(0)
                    def options = collDoc.get("options", Document.class)
                    if (options != null && options.containsKey("validator")) {
                        def vdoc = options.get("validator", Document.class)
                        if (vdoc != null && vdoc.containsKey("\$jsonSchema")) {
                            mongoValidator = vdoc.get("\$jsonSchema", Document.class)
                        } else {
                            mongoValidator = vdoc
                        }
                    }
                }
            } catch (Exception e) {
                log.warn("Unable to read collection validator: ${e.message}")
                mongoValidator = null
            }

            // 2) Sample documents according to strategy
            MongoCollection<Document> coll = db.getCollection(collName)
            try {
                if ("random".equalsIgnoreCase(sampleStrategy)) {
                    def pipeline = [
                        new Document("\$match", filterDoc),
                        new Document("\$sample", new Document("size", sampleSize))
                    ]
                    // (AggregateIterable doesn't support hintString directly in older drivers; fine for sampling)
                    def iterable = coll.aggregate(pipeline)
                    for (doc in iterable) {
                        samples.add(Document.parse(doc.toJson()))
                    }
                } else {
                    // prefix | time_window -> straight find with limit (filters should already constrain time_window)
                    def findIt = coll.find(filterDoc).limit(sampleSize)
                    if (sampleHint) {
                        try {
                            findIt = findIt.hintString(sampleHint)
                        } catch (Exception eh) {
                            log.warn("hintString('${sampleHint}') failed: ${eh.message} (continuing without hint)")
                        }
                    }
                    // Optional: deterministic order for 'prefix'
                    if ("prefix".equalsIgnoreCase(sampleStrategy)) {
                        findIt = findIt.sort(Sorts.ascending("_id"))
                    }
                    def it = findIt.iterator()
                    while (it.hasNext()) {
                        def doc = it.next()
                        samples.add(Document.parse(doc.toJson()))
                    }
                }
            } catch (Exception eAgg) {
                log.warn("Sampling failed (${eAgg.message}); falling back to find(limit) without hint.")
                def it = coll.find(filterDoc).limit(sampleSize).iterator()
                while (it.hasNext()) {
                    def doc = it.next()
                    samples.add(Document.parse(doc.toJson()))
                }
            }
        } finally {
            client?.close()
        }

        def outJson = [
            schemaConversion: schemaConversion,
            mongoValidator: mongoValidator,
            samples: samples,
            meta: [
                db: dbName,
                collection: collName,
                sampleCount: samples.size(),
                filters: filterDoc ?: [:],
                sampling: [ size: sampleSize, strategy: sampleStrategy, hint: sampleHint ?: null ]
            ],
            // pass-through so a downstream extractor can apply them
            fieldTransforms: (payload.fieldTransforms instanceof List ? payload.fieldTransforms : [])
        ]

        String outStr = JsonOutput.prettyPrint(JsonOutput.toJson(outJson))
        outStream.write(outStr.getBytes(StandardCharsets.UTF_8))
    }
}

def ff = session.get()
if (ff == null) return

def log = log as ComponentLog
try {
    ff = session.write(ff, new BundleCallback(context, ff, log))
    ff = session.putAttribute(ff, "bundle.ready", "true")
    session.transfer(ff, REL_SUCCESS)
} catch (Exception e) {
    ff = session.putAttribute(ff, "bundle.error", e.message ?: e.toString())
    session.transfer(ff, REL_FAILURE)
}
