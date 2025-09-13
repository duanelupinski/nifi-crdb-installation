// setup_orders.js
// Creates db "shop", collection "orders" with validation + indexes.
// Also enables pre/post images for richer Change Streams (MongoDB 6.0+).

const DB = process.env.DB || "shop";
const COLL = process.env.COLL || "orders";

const dbRef = db.getSiblingDB(DB);

// JSON Schema (MongoDB dialect)
const validator = {
  $jsonSchema: {
    bsonType: "object",
    additionalProperties: false,
    required: [
      "orderId","customer","items","currency","amounts",
      "status","shipping","createdAt","updatedAt","version"
    ],
    properties: {
      _id: { bsonType: "objectId" }, 
      orderId: { bsonType: "string", pattern: "^ORD-[A-Z0-9-]{8,}$" },
      customer: {
        bsonType: "object",
        additionalProperties: false,
        required: ["id","email"],
        properties: {
          id: { bsonType: "string" },
          email: { bsonType: "string", pattern: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$" },
          name: { bsonType: "string" },
          loyaltyTier: { bsonType: "string", enum: ["BRONZE","SILVER","GOLD","PLATINUM"] }
        }
      },
      items: {
        bsonType: "array",
        minItems: 1,
        items: {
          bsonType: "object",
          additionalProperties: false,
          required: ["sku","qty","unitPrice"],
          properties: {
            sku: { bsonType: "string" },
            name: { bsonType: "string" },
            qty: { bsonType: "int", minimum: 1 },
            unitPrice: { bsonType: "decimal", minimum: 0 },
            discount: { bsonType: ["decimal","null"], minimum: 0 }
          }
        }
      },
      currency: { bsonType: "string", enum: ["USD","EUR","GBP"] },
      amounts: {
        bsonType: "object",
        additionalProperties: false,
        required: ["subtotal","tax","shipping","total"],
        properties: {
          subtotal: { bsonType: "decimal", minimum: 0 },
          tax:      { bsonType: "decimal", minimum: 0 },
          shipping: { bsonType: "decimal", minimum: 0 },
          total:    { bsonType: "decimal", minimum: 0 }
        }
      },
      status: { bsonType: "string", enum: ["NEW","PAID","SHIPPED","DELIVERED","CANCELLED"] },
      shipping: {
        bsonType: "object",
        additionalProperties: false,
        required: ["address","location"],
        properties: {
          address: {
            bsonType: "object",
            additionalProperties: false,
            required: ["line1","city","country","postalCode"],
            properties: {
              line1: { bsonType: "string" },
              line2: { bsonType: ["string","null"] },
              city:  { bsonType: "string" },
              region:{ bsonType: ["string","null"] },
              country:{ bsonType: "string", pattern: "^[A-Z]{2}$" },
              postalCode: { bsonType: "string" }
            }
          },
          location: {
            bsonType: "object",
            additionalProperties: false,
            required: ["type","coordinates"],
            properties: {
              type: { bsonType: "string", enum: ["Point"] },
              coordinates: {
                bsonType: "array", minItems: 2, maxItems: 2,
                items: { bsonType: "double" }
              }
            }
          }
        }
      },
      tags: { bsonType: "array", items: { bsonType: "string" } },
      metadata: { bsonType: "object" },
      payment: {
        bsonType: "object",
        additionalProperties: false,
        properties: {
          method: { bsonType: "string", enum: ["CARD","PAYPAL","WIRE"] },
          last4:  { bsonType: ["string","null"], pattern: "^[0-9]{4}$" }
        }
      },
      createdAt: { bsonType: "date" },
      updatedAt: { bsonType: "date" },
      version:   { bsonType: "int", minimum: 1 }
    }
  }
};

// Create or update validator
if (!dbRef.getCollectionNames().includes(COLL)) {
  dbRef.createCollection(COLL, {
    validator,
    validationLevel: "strict",
    validationAction: "error"
  });
} else {
  dbRef.runCommand({
    collMod: COLL,
    validator,
    validationLevel: "strict",
    validationAction: "error"
  });
}

// Indexes
dbRef.runCommand({
  createIndexes: COLL,
  indexes: [
    { key: { orderId: 1 }, name: "ux_orderId", unique: true },
    { key: { "customer.id": 1, createdAt: -1 }, name: "ix_customer_createdAt" },
    { key: { status: 1, createdAt: -1 }, name: "ix_status_createdAt" },
    { key: { "shipping.location": "2dsphere" }, name: "ix_geo" }
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
print(`Collection ${DB}.${COLL} is ready.`);
