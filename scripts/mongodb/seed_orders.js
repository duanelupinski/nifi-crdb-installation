// seed_orders.js
// Usage examples:
//   N=5 mongosh "<uri>" seed_orders.js
//   N=2000 DB=shop COLL=orders BATCH=1000 mongosh "<uri>" seed_orders.js
//
// Env vars (all optional):
//   N      = number of docs to insert (default 100)
//   DB     = database name (default "shop")
//   COLL   = collection name (default "orders")
//   BATCH  = insertMany batch size (default 1000)

(function () {
  // ----- Config from env -----
  const DB    = (typeof process !== "undefined" && process.env.DB)    || "shop";
  const COLL  = (typeof process !== "undefined" && process.env.COLL)  || "orders";
  const N     = parseInt((typeof process !== "undefined" && process.env.N) || "100", 10);
  const BATCH = parseInt((typeof process !== "undefined" && process.env.BATCH) || "1000", 10);

  // ----- Helpers -----
  const Int = (n) => NumberInt(n); // Int32 for schema {bsonType:"int"}
  const toCents = (n) => Math.round(n * 100);
  const decFromCents = (c) => NumberDecimal((c / 100).toFixed(2));
  const randInt = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;
  const choose = (arr) => arr[randInt(0, arr.length - 1)];

  // Rough NYC/NJ area bounding box for sample geo coordinates
  const randLng = () => -74.30 + Math.random() * ( -73.70 + 74.30 ); // [-74.30, -73.70]
  const randLat = () =>  40.55 + Math.random() * (  40.95 - 40.55 ); // [ 40.55, 40.95]

  // ----- Sample catalogs -----
  const products = [
    { sku: "SKU-1001", name: "Widget A", price: 19.99 },
    { sku: "SKU-1002", name: "Widget B", price: 29.50 },
    { sku: "SKU-2001", name: "Gadget C", price: 7.25  },
    { sku: "SKU-3001", name: "Thing D",  price: 99.00 },
    { sku: "SKU-3002", name: "Thing E",  price: 149.99},
    { sku: "SKU-4001", name: "Bundle F", price: 59.00 },
    { sku: "SKU-5001", name: "Accessory G", price: 12.49 },
    { sku: "SKU-6001", name: "Service H", price: 5.00 }
  ];
  const tiers = ["BRONZE","SILVER","GOLD","PLATINUM"];
  const statuses = ["NEW","PAID","SHIPPED","DELIVERED","CANCELLED"];
  const currencies = ["USD","EUR","GBP"];
  const payMethods = ["CARD","PAYPAL","WIRE"];

  const dbRef = db.getSiblingDB(DB);
  const coll  = dbRef.getCollection(COLL);

  function makeOrder(i) {
    // Items
    const numItems = randInt(1, 4);
    let subtotalC = 0;

    const items = Array.from({ length: numItems }).map(() => {
      const p = choose(products);
      const qty = randInt(1, 5);
      const unitC = toCents(p.price);
      // Up to 30% line discount, applied 20% of the time
      const maxDisc = Math.floor(unitC * qty * 0.30);
      const discountC = Math.random() < 0.20 ? randInt(0, maxDisc) : null;
      const lineC = unitC * qty - (discountC || 0);
      subtotalC += lineC;

      return {
        sku: p.sku,
        name: p.name,
        qty: Int(qty),                               // int32
        unitPrice: decFromCents(unitC),              // Decimal128
        discount: discountC === null ? null : decFromCents(discountC)
      };
    });

    // Totals
    const taxC = Math.round(subtotalC * 0.08);
    const shippingC = subtotalC > toCents(100) ? 0 : toCents(5.99);
    const totalC = subtotalC + taxC + shippingC;

    // Timestamps
    const now = new Date();
    const createdAt = new Date(now.getTime() - randInt(0, 30) * 24 * 3600 * 1000 - randInt(0, 86400000));
    const updatedAt = new Date(createdAt.getTime() + randInt(0, 5) * 3600 * 1000);

    // IDs & misc
    const custId = `CUST-${randInt(1000,9999)}`;
    const randHex = ObjectId().toString().slice(-6).toUpperCase();
    const orderId = `ORD-${now.getFullYear()}-${randHex}-${i}`;

    // Optionals
    const line2Maybe = Math.random() < 0.2 ? `Apt ${randInt(1,50)}` : null;
    const last4Maybe = Math.random() < 0.7 ? `${randInt(1000,9999)}` : null;

    // Build doc (aligns with JSON Schema used in setup)
    return {
      orderId,
      customer: {
        id: custId,
        email: `${custId.toLowerCase()}@example.com`,
        name: `Customer ${custId.slice(-4)}`,
        loyaltyTier: choose(tiers)
      },
      items,
      currency: choose(currencies),
      amounts: {
        subtotal: decFromCents(subtotalC),
        tax:      decFromCents(taxC),
        shipping: decFromCents(shippingC),
        total:    decFromCents(totalC)
      },
      status: choose(statuses),
      shipping: {
        address: {
          line1: `${randInt(1,9999)} Main St`,
          line2: line2Maybe,
          city:  "Wayne",
          region:"NJ",
          country: "US",
          postalCode: `${randInt(10000,99999)}`
        },
        location: { type: "Point", coordinates: [ randLng(), randLat() ] }
      },
      tags: Math.random() < 0.4 ? ["priority"] : [],
      metadata: { source: "seed", ip: `${randInt(10,250)}.${randInt(0,255)}.${randInt(0,255)}.${randInt(1,254)}` },
      payment: { method: choose(payMethods), last4: last4Maybe },
      createdAt,
      updatedAt,
      version: Int(1) // int32
    };
  }

  // ----- Insert in batches -----
  let inserted = 0;
  const batch = [];
  for (let i = 0; i < N; i++) {
    batch.push(makeOrder(i));
    if (batch.length === BATCH) {
      coll.insertMany(batch);
      inserted += batch.length;
      batch.length = 0;
    }
  }
  if (batch.length) {
    coll.insertMany(batch);
    inserted += batch.length;
  }

  print(`[seed_orders] Inserted ${inserted} docs into ${DB}.${COLL}`);
})();
