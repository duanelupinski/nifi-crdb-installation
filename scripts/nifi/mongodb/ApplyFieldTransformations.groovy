/*
 * ApplyFieldTransforms.groovy
 * ExecuteScript (Groovy) for Apache NiFi
 *
 * Purpose:
 *   Apply per-collection fieldTransforms to the "samples" array inside a JSON bundle,
 *   prior to inference/DDL generation. Only transforms with phase "both" or "inference_only"
 *   are applied here.
 *
 * IN:
 *   - FlowFile content: JSON bundle with at least:
 *       {
 *         "meta": { "collection": "orders", ... },
 *         "samples": [ { ... }, ... ],
 *         "fieldTransforms": [ ... ]
 *       }
 *     OR a bundle without "collections" where transforms are omitted (no-op).
 *   - Optional attribute: collection.name (used if meta.collection absent)
 *
 * OUT:
 *   - FlowFile content: same bundle, with transformed "samples".
 *   - Attributes: transforms.applied (count), transforms.errors (count)
 */

import org.apache.nifi.processor.io.StreamCallback
import org.apache.nifi.flowfile.FlowFile
import org.apache.nifi.logging.ComponentLog
import java.nio.charset.StandardCharsets

import groovy.json.JsonSlurper
import groovy.json.JsonOutput
import java.security.MessageDigest
import java.time.*
import java.time.format.DateTimeFormatter

class TransformCallback implements StreamCallback {

  def context
  def flowFile
  def log

  int applied = 0
  int errors = 0
  String errorMsg = null
  List<Map> stats = []

  TransformCallback(context, flowFile, log) {
    this.context = context
    this.flowFile = flowFile
    this.log = log
  }

  @Override
  void process(InputStream inStream, OutputStream outStream) throws IOException {
    try {
      def slurper = new JsonSlurper()
      def bundle = slurper.parse(inStream)

      // ---- Settings via attributes (all optional) ----
      boolean DEBUG = (flowFile.getAttribute('transform.debug') ?: 'false').toBoolean()
      boolean INPLACE = (flowFile.getAttribute('transform.inplace') ?: 'true').toBoolean()
      boolean PRETTY = (flowFile.getAttribute('transform.pretty') ?: 'false').toBoolean()
      Integer MAX_MATCHES_PER_DOC = (flowFile.getAttribute('transform.maxMatchesPerDoc') ?: '').isInteger() ? flowFile.getAttribute('transform.maxMatchesPerDoc') as int : null

      def collectionName = (bundle?.meta?.collection ?: flowFile.getAttribute('collection.name'))
      if (!collectionName) {
        if (DEBUG) log.warn("ApplyFieldTransforms: missing meta.collection; no transforms")
        outStream.write(JsonOutput.toJson(bundle).getBytes('UTF-8')); return
      }

      def transforms = (bundle?.fieldTransforms instanceof List) ? bundle.fieldTransforms : []
      transforms = transforms.findAll { (it?.phase ?: 'both') in ['both','inference_only'] }

      if (!(bundle?.samples instanceof List) || bundle.samples.isEmpty() || transforms.isEmpty()) {
        outStream.write(JsonOutput.toJson(bundle).getBytes('UTF-8')); return
      }

      def samples = INPLACE ? bundle.samples : bundle.samples.collect { deepCopy(it) }

      transforms.each { t ->
        long tStart = System.nanoTime()
        try {
          int m = applyTransformToSamples(samples, t, MAX_MATCHES_PER_DOC)
          applied += m
          long ms = (System.nanoTime() - tStart) / 1_000_000L
          stats << [op: (t.op ?: '?'), path: (t.path ?: '?'), matches: m, ms: ms]
          if (DEBUG) log.info("Transform ${t.op} @ ${t.path} -> matches=${m}, ${ms}ms")
        } catch (Throwable ex) {
          errors++
          long ms = (System.nanoTime() - tStart) / 1_000_000L
          stats << [op: (t.op ?: '?'), path: (t.path ?: '?'), matches: -1, ms: ms, error: (ex.message ?: ex.toString())]
          log.error("ApplyFieldTransforms: transform ${t} failed: ${ex.message}", ex)
        }
      }

      if (!INPLACE) bundle.samples = samples
      bundle.stats = [ applied: applied, errors: errors, transforms: stats ]

      def outJson = PRETTY ? JsonOutput.prettyPrint(JsonOutput.toJson(bundle)) : JsonOutput.toJson(bundle)
      outStream.write(outJson.getBytes('UTF-8'))
    } catch (Throwable ex) {
      errorMsg = ex.message ?: ex.toString()
      // Write a minimal body so the callback completes without throwing
      outStream.write(errorMsg.getBytes('UTF-8'))
    }
  }

  // -------- Core dispatcher with fast-paths & caps --------
  static int applyTransformToSamples(List docs, Map t, Integer MAX_MATCHES_PER_DOC) {
    String op = t?.op; String path = t?.path
    Map args = (t?.args instanceof Map) ? t.args : [:]
    if (!op || !path) return 0

    // Pre-compile regex (regex_extract) and timestamp format
    def compiled = [:]
    if (op == 'regex_extract') {
      compiled.pattern = (args?.pattern ?: ".*")
    }
    if (op == 'to_timestamp') {
      compiled.fmt = (args?.format ? DateTimeFormatter.ofPattern(args.format.toString()) : null)
      compiled.fmtRegex = (args?.formatRegex)  // optional: avoid exceptions if not matching
      compiled.tz = (args?.timezone ?: "UTC").toString()
    }

    int count = 0
    docs.each { doc ->
      // Fast check: bail early if the root segment isn't present
      String rootKey = path.split(/\./)[0].replaceAll(/\[\]|\[\*\]/,'')
      if (!(doc instanceof Map) || !((Map)doc).containsKey(rootKey)) {
        if (op == 'default_if_missing') {
          // still need parents enumeration for defaults
        } else {
          return // continue to next doc
        }
      }

      def matches = enumerateConcretePaths(doc, path)
      if (op == 'default_if_missing') {
        matches = expandWithMissingLeaf(doc, path, matches)
      }
      if (MAX_MATCHES_PER_DOC != null && matches.size() > MAX_MATCHES_PER_DOC) {
        matches = matches.take(MAX_MATCHES_PER_DOC)
        // you could expose a counter here if desired
      }

      matches.each { concrete ->
        try {
          switch (op) {
            case 'drop':
              deleteAtConcretePath(doc, concrete); count++; break
            case 'rename':
              String to = (args?.to ?: "").toString(); if (!to) break
              def idxStack = extractIndexStack(concrete)
              def toConcrete = substituteWildcards(to, idxStack)
              if (toConcrete == concrete) break // no-op
              def v = getAtConcretePath(doc, concrete)
              deleteAtConcretePath(doc, concrete)
              setAtConcretePath(doc, toConcrete, v, false); count++
              break
            case 'cast':
              setAtConcretePath(doc, concrete, castTo(getAtConcretePath(doc, concrete), args?.type ?: ""), false); count++; break
            case 'coalesce':
              def vTarget = getAtConcretePath(doc, concrete)
              if (vTarget != null) break
              def vals = (args?.values instanceof List) ? args.values : []
              for (def srcPath : vals) {
                def srcMatches = enumerateConcretePaths(doc, srcPath)
                def found = null
                for (def sp : srcMatches) { found = getAtConcretePath(doc, sp); if (found != null) break }
                if (found != null) { setAtConcretePath(doc, concrete, found, false); count++; break }
              }
              break
            case 'default_if_missing':
              if (!existsConcretePath(doc, concrete)) {
                setAtConcretePath(doc, concrete, args?.value, false); count++
              }
              break
            case 'trim':      setStringOp(doc, concrete){ it?.toString()?.trim() }; count++; break
            case 'lower':     setStringOp(doc, concrete){ it?.toString()?.toLowerCase() }; count++; break
            case 'upper':     setStringOp(doc, concrete){ it?.toString()?.toUpperCase() }; count++; break
            case 'substring':
              int start = (args?.start ?: 0) as int
              Integer len = (args?.length != null) ? (args.length as int) : null
              setStringOp(doc, concrete){ s -> if (s==null) return s; def str=s.toString(); (len==null)? str.substring(Math.min(start,str.length())) : str.substring(Math.min(start,str.length()), Math.min(start+len,str.length())) }
              count++; break
            case 'regex_extract':
              String patt = compiled.pattern
              setStringOp(doc, concrete){ s -> if (s==null) return s; def m=(s.toString() =~ patt); m.find() ? m.group((args?.group ?: 0) as int) : null }
              count++; break
            case 'concat':
              def paths = (args?.paths instanceof List) ? args.paths : []
              String sep = (args?.sep ?: "")
              def parts = []
              paths.each { p2 ->
                def ms = enumerateConcretePaths(doc, p2)
                parts << (ms ? (getAtConcretePath(doc, ms[0])?.toString() ?: "") : "")
              }
              setAtConcretePath(doc, concrete, parts.join(sep), false); count++; break
            case 'to_uuid':
              setAtConcretePath(doc, concrete, toUUID(getAtConcretePath(doc, concrete)), false); count++; break
            case 'to_decimal':
              setAtConcretePath(doc, concrete, toDecimal(getAtConcretePath(doc, concrete), args), false); count++; break
            case 'to_timestamp':
              setAtConcretePath(doc, concrete, toTimestampStringFast(getAtConcretePath(doc, concrete), compiled), false); count++; break
            case 'parse_json':
              setAtConcretePath(doc, concrete, parseJsonMaybe(getAtConcretePath(doc, concrete)), false); count++; break
            case 'mask':
              setAtConcretePath(doc, concrete, maskValue(getAtConcretePath(doc, concrete), args), false); count++; break
            default: break
          }
        } catch (Throwable ignore) { /* swallow per-item errors */ }
      }
    }
    return count
  }

  // -------- Paths (same as before) --------
  static class Seg { String name; enum Ix { NONE, STAR, INDEX }; Ix ix; Integer index }
  static List<Seg> parsePath(String path) {
    def parts=[]; path?.split(/\./)?.each { token ->
      def mStar=(token =~ /^([^\[]+)\[(\*|)\]$/); def mIdx=(token =~ /^([^\[]+)\[(\d+)\]$/)
      if (token.endsWith("[]") || mStar.matches()) { parts << new Seg(name: token.replaceAll(/\[\]|\[\*\]/,''), ix:Seg.Ix.STAR) }
      else if (mIdx.matches()) { parts << new Seg(name:mIdx[0][1], ix:Seg.Ix.INDEX, index: Integer.valueOf(mIdx[0][2])) }
      else { parts << new Seg(name: token, ix:Seg.Ix.NONE) }
    }; return parts
  }
  static List<String> enumerateConcretePaths(Object doc, String path) {
    def segs=parsePath(path); def out=[]; enumerateRec(doc, segs, 0, "", out); return out
  }
  static void enumerateRec(Object cur, List<Seg> segs, int idx, String acc, List out) {
    if (idx >= segs.size()) { if (acc) out << acc; return }
    def s=segs[idx]; if (!(cur instanceof Map)) return
    def next=((Map)cur).get(s.name)
    if (s.ix==Seg.Ix.NONE) { if (next!=null) enumerateRec(next, segs, idx+1, acc ? "${acc}.${s.name}" : s.name, out) }
    else if (s.ix==Seg.Ix.INDEX) {
      if (next instanceof List && s.index < next.size()) {
        def el=((List)next)[s.index]; def head= acc ? "${acc}.${s.name}[${s.index}]" : "${s.name}[${s.index}]"
        enumerateRec(el, segs, idx+1, head, out)
      }
    } else if (next instanceof List) {
      for (int i=0;i<((List)next).size();i++){
        def el=((List)next)[i]; def head= acc ? "${acc}.${s.name}[${i}]" : "${s.name}[${i}]"
        enumerateRec(el, segs, idx+1, head, out)
      }
    }
  }
  static boolean existsConcretePath(Object root, String concrete) { return getAtConcretePath(root, concrete, true) != null }
  static Object getAtConcretePath(Object root, String concrete, boolean nullIfMissingLeaf=false) {
    def cur=root; def tokens=tokenizeConcrete(concrete)
    for (int i=0;i<tokens.size();i++){
      def tk=tokens[i]
      if (tk.containsKey("index")) {
        if (!(cur instanceof Map)) return null
        def arr=((Map)cur).get(tk.name)
        if (!(arr instanceof List) || tk.index >= arr.size()) return null
        cur=((List)arr)[tk.index as int]
      } else {
        if (!(cur instanceof Map)) return null
        if (i==tokens.size()-1 && !((Map)cur).containsKey(tk.name) && nullIfMissingLeaf) return null
        cur=((Map)cur).get(tk.name)
      }
    }
    return cur
  }
  static void setAtConcretePath(Object root, String concrete, Object value, boolean createParents) {
    def cur=root; def tokens=tokenizeConcrete(concrete)
    for (int i=0;i<tokens.size();i++){
      def tk=tokens[i]; boolean last=(i==tokens.size()-1)
      if (tk.containsKey("index")) {
        if (!(cur instanceof Map)) return
        def arr=((Map)cur).get(tk.name)
        if (!(arr instanceof List)) { if (!createParents) return; arr=[]; ((Map)cur)[tk.name]=arr }
        while (arr.size() <= (tk.index as int)) { arr.add([:]) }
        if (last) { arr[tk.index as int]=value } else { if (!(arr[tk.index as int] instanceof Map)) arr[tk.index as int]=[:]; cur=arr[tk.index as int] }
      } else {
        if (!(cur instanceof Map)) return
        if (last) { ((Map)cur)[tk.name]=value } else {
          def nxt=((Map)cur).get(tk.name); if (!(nxt instanceof Map)) nxt=[:]; ((Map)cur)[tk.name]=nxt; cur=nxt
        }
      }
    }
  }
  static void deleteAtConcretePath(Object root, String concrete) {
    def info=parentAndLeaf(root, concrete); if (info==null) return
    def parent=info.parent; def leaf=info.leaf
    if (leaf instanceof Map && leaf.containsKey("index")) {
      def arr=parent.get(leaf.name); if (arr instanceof List && (leaf.index as int) < arr.size()) arr.remove(leaf.index as int)
    } else parent.remove(leaf.name)
  }
  static Map parentAndLeaf(Object root, String concrete) {
    def cur=root; def tokens=tokenizeConcrete(concrete); if (tokens.isEmpty()) return null
    for (int i=0;i<tokens.size()-1;i++){
      def tk=tokens[i]
      if (tk.containsKey("index")) {
        if (!(cur instanceof Map)) return null
        def arr=((Map)cur).get(tk.name); if (!(arr instanceof List) || (tk.index as int) >= arr.size()) return null
        cur=arr[tk.index as int]
      } else { if (!(cur instanceof Map)) return null; cur=((Map)cur).get(tk.name) }
    }
    return [ parent: cur, leaf: tokens.last() ]
  }
  static List<Map> tokenizeConcrete(String concrete) {
    def tokens=[]; concrete?.split(/\./)?.each { token ->
      def m=(token =~ /^([^\[]+)\[(\d+)\]$/)
      if (m.matches()) tokens << [name:m[0][1], index: Integer.valueOf(m[0][2])]
      else tokens << [name: token]
    }; return tokens
  }
  static List<Integer> extractIndexStack(String concrete) { def idxs=[]; (concrete =~ /\[(\d+)\]/).each { m -> idxs << Integer.valueOf(m[1]) }; idxs }
  static String substituteWildcards(String path, List<Integer> idxs) {
    def sb=new StringBuilder(); int pos=0; int k=0; def m=(path =~ /\[(\*|)\]/)
    while (m.find()) { sb.append(path.substring(pos, m.start())); def val=(k<idxs.size()) ? "[${idxs[k]}]" : "[]"; sb.append(val); pos=m.end(); k++ }
    sb.append(path.substring(pos)); return sb.toString()
  }
  static List<String> expandWithMissingLeaf(Object doc, String path, List<String> existing) {
    def segs=parsePath(path); if (segs.isEmpty()) return existing
    def parentSegs=segs[0..-2]; def leaf=segs[-1]; def parents=[]; enumerateRec(doc, parentSegs, 0, "", parents)
    def out=[]+existing
    parents.each { p ->
      if (leaf.ix==Seg.Ix.NONE) out << (p ? "${p}.${leaf.name}" : leaf.name)
      else if (leaf.ix==Seg.Ix.INDEX) out << (p ? "${p}.${leaf.name}[${leaf.index}]" : "${leaf.name}[${leaf.index}]")
      else {
        def parentObj=getAtConcretePath(doc, p); def arr=(parentObj instanceof Map)? parentObj.get(leaf.name) : null
        if (arr instanceof List) for (int i=0;i<arr.size();i++) out << (p ? "${p}.${leaf.name}[${i}]" : "${leaf.name}[${i}]")
      }
    }
    return out.unique()
  }

  // -------- String & type helpers --------
  static void setStringOp(Object doc, String conc, Closure fn) {
    def v=getAtConcretePath(doc, conc); def s=(v==null)? null : v.toString()
    setAtConcretePath(doc, conc, fn(s), false)
  }
  static Object castTo(Object v, String type) {
    if (v == null) return null
    try {
      switch ((type ?: "").toLowerCase()) {
        case "string": return v.toString()
        case "int": case "int64": case "int32": return (v instanceof Number) ? ((Number)v).longValue() : Long.parseLong(v.toString().replaceAll("[^0-9-\\.]", ""))
        case "float": case "float64": case "double": return (v instanceof Number) ? ((Number)v).doubleValue() : Double.parseDouble(v.toString())
        case "bool": case "boolean": return (v instanceof Boolean) ? v : v.toString().equalsIgnoreCase("true")
        case "decimal": return toDecimal(v, [:])
        case "uuid": return toUUID(v)
        case "timestamp": return toTimestampStringFast(v, [tz:"UTC"])
        default: return v
      }
    } catch (Throwable ex) { return v }
  }
  static Object toUUID(Object v) { if (v==null) return null; try { return java.util.UUID.fromString(v.toString()).toString() } catch (Throwable ex) { return null } }
  static Object toDecimal(Object v, Map args) {
    if (v==null) return null
    try {
      def bd=(v instanceof BigDecimal)? v : new BigDecimal(v.toString())
      Integer scale = (args?.scale instanceof Number) ? (args.scale as int) : null
      if (scale != null) bd = bd.setScale(scale, java.math.RoundingMode.HALF_UP)
      return bd
    } catch (Throwable ex) { return null }
  }
  static boolean looksISO(String s){ return s!=null && s.length()>=19 && s.charAt(4)=='-' && s.charAt(7)=='-' && (s.charAt(10)=='T' || s.charAt(10)==' ') }
  static Object toTimestampStringFast(Object v, Map compiled) {
    try {
      if (v == null) return null
      String s = v.toString().trim()

      // Do NOT short-circuit on fmtRegex unless a custom formatter is present
      if (!compiled?.fmt && compiled?.fmtRegex) compiled.remove('fmtRegex')

      // Try custom format only when present (and optional regex matches), otherwise fall through to ISO
      boolean tryCustom = (compiled?.fmt != null) && (!compiled?.fmtRegex || (s ==~ compiled.fmtRegex.toString()))
      boolean hasZone  = (s.endsWith("Z") || (s ==~ /.*[+-]\d{2}:?\d{2}$/))

      if (tryCustom) {
        if (hasZone) return OffsetDateTime.parse(s).toString()
        def zdt = LocalDateTime.parse(s, compiled.fmt).atZone(ZoneId.of(compiled.tz ?: "UTC"))
        return zdt.toOffsetDateTime().toString()
      }

      // normalize RFC-822 style offsets (+HHMM) to ISO (+HH:MM)
      if (s ==~ /.*[+-]\d{4}$/) {
        s = s.replaceFirst(/([+-]\d{2})(\d{2})$/, '$1:$2')
      }

      // heuristics: try OffsetDateTime, then Instant, then LocalDateTime (ISO-like)
      try { return OffsetDateTime.parse(s).toString() } catch (Throwable e1) {
        try { return Instant.parse(s).atZone(ZoneId.of(compiled.tz ?: "UTC")).toOffsetDateTime().toString() } catch (Throwable e2) {
          if (looksISO(s)) return LocalDateTime.parse(s.replace("Z","").replace("+00:00","")).atZone(ZoneId.of(compiled.tz ?: "UTC")).toOffsetDateTime().toString()
          return null
        }
      }
    } catch (Throwable ex) { return null }
  }
  static Object parseJsonMaybe(Object v) { if (v==null) return null; if (!(v instanceof String)) return v; try { return new JsonSlurper().parseText((String)v) } catch (Throwable ex) { return v } }
  static Object maskValue(Object v, Map args) {
    String strategy=(args?.strategy ?: "redact").toString()
    switch (strategy) {
      case "null": return null
      case "hash": def s=v?.toString() ?: ""; def salt=(args?.salt ?: ""); return sha256Hex(s + salt)
      default: return "*****"
    }
  }
  static String sha256Hex(String s){ MessageDigest md=MessageDigest.getInstance("SHA-256"); md.update(s.getBytes("UTF-8")); byte[] d=md.digest(); def sb=new StringBuilder(); for (b in d){ sb.append(String.format("%02x", b)) }; return sb.toString() }
  static Object deepCopy(Object o){ return new JsonSlurper().parseText(JsonOutput.toJson(o)) }
}

def ff = session.get()
if (ff == null) return

def log = log as ComponentLog
try {
  long t0 = System.nanoTime()
  def cb = new TransformCallback(context, ff, log)
  ff = session.write(ff, cb)

  ff = session.putAttribute(ff, "transforms.applied", String.valueOf(cb.applied))
  ff = session.putAttribute(ff, "transforms.errors", String.valueOf(cb.errors))
  if (cb.errorMsg != null) {
    ff = session.putAttribute(ff, "transforms.exception", cb.errorMsg)
    session.transfer(ff, REL_FAILURE)  // make sure FAILURE is connected or auto-terminated
  } else {
    long ms = (System.nanoTime() - t0) / 1_000_000L
    ff = session.putAttribute(ff, "transforms.time.total_ms", String.valueOf(ms))
    session.transfer(ff, REL_SUCCESS)
  }
} catch (Exception e) {
  ff = session.putAttribute(ff, "transforms.exception", e.message ?: e.toString())
  session.transfer(ff, REL_FAILURE)
}
