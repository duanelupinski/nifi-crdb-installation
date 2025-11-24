// setup_articles.js
// Creates db "shop", collection "articles" with validation + indexes.
// Mirrors style of setup_orders.js, but allows heterogeneous 'elements' array and an ObjectId FK to orders.
//
// Env (optional):
//   DB           default "shop"
//   COLL         default "articles"
//   ORDERS_COLL  default "orders" (for documentation; validator does not enforce cross-collection FK)

const DB = process.env.DB || "shop";
const COLL = process.env.COLL || "articles";
const ORDERS_COLL = process.env.ORDERS_COLL || "orders";

const dbRef = db.getSiblingDB(DB);

// JSON Schema (MongoDB dialect).
// Intentionally permissive for `elements` so we can insert mixed shapes.
const validator = {
  $jsonSchema: {
    bsonType: "object",
    additionalProperties: true,
    required: ["title", "elements", "published", "lastEditedAt"],
    properties: {
      _id: { bsonType: "objectId" },
      title: { bsonType: "string" },
      // Reference to orders._id
      orderRef: { bsonType: "objectId" },
      team: { bsonType: ["objectId", "null"] },
      faqCollection: { bsonType: ["objectId", "null"] },
      published: { bsonType: "bool" },
      lastEditedAt: { bsonType: "date" },
      html: { bsonType: ["string", "null"] },
      // Heterogeneous array: allow objects with differing fields.
      elements: {
        bsonType: "array",
        minItems: 1,
        items: {
          bsonType: "object",
          additionalProperties: true,
          properties: {
            type: { bsonType: "string" },
            // Either an 'id' that's a numeric-looking string, or an '_id' that's an ObjectId, but neither required.
            id: { bsonType: ["int", "long", "double", "string"], pattern: "^[0-9]+$" },
            _id: { bsonType: "objectId" },
            html: { bsonType: "string" },
            url: { bsonType: "string" },
            width: { bsonType: ["int", "long", "double"] },
            justify: { bsonType: "string" },
            title: { bsonType: "string" },
            child: { bsonType: "string" },
            fontFamily: { bsonType: "string" },
            fontWeight: { bsonType: "string" },
            fontSizePx: { bsonType: ["int","long","double"] },
            textColor: { bsonType: "string" },
            linkColor: { bsonType: "string" }
          }
        }
      }
    }
  }
};

if (!dbRef.getCollectionNames().includes(COLL)) {
  dbRef.createCollection(COLL, {
    validator,
    validationLevel: "moderate",
    validationAction: "error"
  });
} else {
  dbRef.runCommand({
    collMod: COLL,
    validator,
    validationLevel: "moderate",
    validationAction: "error"
  });
}

// Helpful indexes
dbRef.runCommand({
  createIndexes: COLL,
  indexes: [
    { key: { orderRef: 1 }, name: "ix_orderRef" },
    { key: { lastEditedAt: -1 }, name: "ix_lastEditedAt" },
    { key: { published: 1, lastEditedAt: -1 }, name: "ix_published_lastEditedAt" }
  ]
});

// Optional: richer Change Streams (pre/post images) – MongoDB 6.0+
try {
  dbRef.runCommand({
    collMod: COLL,
    changeStreamPreAndPostImages: { enabled: true }
  });
} catch (e) {
  // ignore if not supported
}

print(`Collection ${DB}.${COLL} is ready (FK-style orderRef -> ${ORDERS_COLL}._id).`);
