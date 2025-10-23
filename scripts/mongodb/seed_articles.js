// seed_articles.js
// Seeds "articles" with heterogeneous `elements` and an ObjectId FK (orderRef) pointing to an order in the same DB.
//
// Usage examples:
/**
  mongosh "<uri>" seed_articles.js
  N=25 DB=shop COLL=articles ORDERS_COLL=orders mongosh "<uri>" seed_articles.js
*/
// Env vars (all optional):
//   N           = number of docs to insert (default 10)
//   DB          = database name (default "shop")
//   COLL        = collection name (default "articles")
//   ORDERS_COLL = orders collection name (default "orders")
//   BATCH       = insertMany batch size (default 1000)

(function () {
  const DB     = (typeof process !== "undefined" && process.env.DB)     || "shop";
  const COLL   = (typeof process !== "undefined" && process.env.COLL)   || "articles";
  const ORDERS = (typeof process !== "undefined" && process.env.ORDERS_COLL) || "orders";
  const N      = parseInt((typeof process !== "undefined" && process.env.N) || "10", 10);
  const BATCH  = parseInt((typeof process !== "undefined" && process.env.BATCH) || "1000", 10);

  const dbRef = db.getSiblingDB(DB);
  const coll  = dbRef.getCollection(COLL);
  const orders = dbRef.getCollection(ORDERS);

  // Helper to fetch a random order _id (falls back to a new ObjectId if none exist)
  function randomOrderId() {
    const it = orders.aggregate([{ $sample: { size: 1 } }, { $project: { _id: 1 } }]);
    if (it.hasNext()) {
      const doc = it.next();
      return doc._id;
    }
    return new ObjectId();
  }

  function sampleArticle(i) {
    const orderRef = randomOrderId();
    const teamMaybe = Math.random() < 0.5 ? new ObjectId() : null;
    const faqMaybe  = Math.random() < 0.4 ? new ObjectId() : null;
    const now = new Date();
    const lastEditedAt = new Date(now.getTime() - Math.floor(Math.random() * 7 * 24 * 3600 * 1000));

    // Build heterogeneous elements array mirroring the example variety
    const elements = [
      {
        type: "rich-text",
        id: i,
        html: "<p>Parmesan is an Italian hard, granular cheese produced from cow's milk and aged at least 12 months.</p>",
        fontFamily: "Times New Roman",
        fontWeight: "bold",
        fontSizePx: 24,
        textColor: "#3b1d1d",
        linkColor: "#0000ff"
      },
      {
        type: "toggle",
        title: "This is a toggle title!",
        child: "This is a toggle body.",
        _id: new ObjectId() // element-scoped ObjectId
      },
      { type: "image", url: "https://redoapi-dev.s3.amazonaws.com/desert_535949e17f48.jpeg", width: 350, justify: "left" },
      { type: "video", url: "https://redoapi-dev.s3.amazonaws.com/sample_5s_c8b18b81d9a4.mp4", width: 500, justify: "right" },
      { type: "video", url: "", width: 501, justify: "center" },
      { type: "video", url: "https://redoapi-dev.s3.amazonaws.com/death_captain_ducky_3_de8a2fda8ae7.webp", width: 501, justify: "center" },
      { type: "rich-text", id: i + Math.floor(Math.random()*1000), html: "<p></p>", fontFamily: "Arial", fontWeight: "regular", fontSizePx: 16, textColor: "#000000", linkColor: "#0000ff" },
      { type: "divider" },
      { type: "rich-text", id: i + 100, html: "<p>Changed?</p>", fontFamily: "Arial", fontWeight: "regular", fontSizePx: 16, textColor: "#000000", linkColor: "#0000ff" }
    ];

    return {
      title: `Sample Article ${i}`,
      elements,
      team: teamMaybe,
      faqCollection: faqMaybe,
      orderRef,                  // <-- external reference to orders._id
      published: Math.random() < 0.8,
      lastEditedAt,
      html: '<p class="EditorTheme__paragraph"><span style="color: rgb(59, 29, 29); font-size: 24px; white-space: pre-wrap;">Parmesan sample text.</span></p>'
    };
  }

  // Insert in batches
  let inserted = 0;
  const batch = [];
  for (let i = 0; i < N; i++) {
    batch.push(sampleArticle(i));
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

  print(`[seed_articles] Inserted ${inserted} docs into ${DB}.${COLL} (orderRef -> ${ORDERS}._id).`);
})();
