// ExecuteScript (Groovy) — Rewrite a single DDL stmt based on ddl.mode.
// - Supports: CREATE TABLE (incl. FAMILY clauses), CREATE INDEX, ALTER TABLE ADD CONSTRAINT, ALTER TABLE ADD COLUMN, ALTER TABLE ADD FAMILY.
// - Modes:
//   * generate_only         -> pass original ddl statement through (applied=false)
//   * drop_and_apply        -> pass-through (with minor fixes like STORING-before-WHERE)
//   * apply_new_only        -> additive: IF NOT EXISTS / ADD COLUMN IF NOT EXISTS / create missing index/constraint; add missing FAMILY; no type changes
//   * apply_and_update_existing -> same as additive + safe type widens + moving columns between families
// - Never skips: when there’s nothing to do, emits NOOP_SQL so PutSQL still consumes one stmt.
// Requires Controller Service property "DBCPService" (DBCPConnectionPool or Lookup target).

import org.apache.commons.io.IOUtils
import java.nio.charset.StandardCharsets
import java.sql.*
import org.apache.nifi.dbcp.DBCPService

def ff = session.get(); if (!ff) return

def NOOP_SQL = "SET application_name = current_setting('application_name')"
def readContent = { flowFile ->
  def s = ''
  session.read(flowFile, { is -> s = IOUtils.toString(is, StandardCharsets.UTF_8) } as org.apache.nifi.processor.io.InputStreamCallback)
  s
}
def writeContent = { flowFile, text ->
  session.write(flowFile, { os -> os.write(text.getBytes(StandardCharsets.UTF_8)) } as org.apache.nifi.processor.io.OutputStreamCallback)
}
def dbcp = context.getProperty(ff.getAttribute('database.name')).asControllerService(DBCPService)

def mode = (ff.getAttribute('ddl.mode') ?: 'apply_new_only').toLowerCase(Locale.ROOT)
def targetSchema = ff.getAttribute('target.crdb.schema.staging') ?: ff.getAttribute('target.crdb.schema.default') ?: 'public'
def runId = ff.getAttribute('migration.runId')
def ordinal = (ff.getAttribute('fragment.index') ?: '0') as Integer

String orig = readContent(ff).trim()
String up = orig.toUpperCase(Locale.ROOT)

// --------- helpers

def parseQIdent = { String ident ->
  // return [schema (nullable), name] ; strip quotes around parts
  def s = ident.trim()
  int depth = 0; int lastDot = -1
  boolean inQuote = false
  for (int i=0;i<s.length();i++){
    char c = s.charAt(i)
    if (c=='"'){ inQuote = !inQuote; continue }
    if (!inQuote && c=='.') lastDot = i
  }
  if (lastDot>0) {
    return [s.substring(0,lastDot).replaceAll('^"|"$',''),
            s.substring(lastDot+1).replaceAll('^"|"$','')]
  } else {
    return [null, s.replaceAll('^"|"$','')]
  }
}

// Reorder CREATE INDEX ... STORING before WHERE (Cockroach requires)
def fixIndexOrder = { String sql ->
  def m = (sql =~ /(?is)^(.*?\bON\b.*?\))(?:\s+WHERE\s+(.*?))?(?:\s+STORING\s*\((.*?)\))?\s*;?\s*$/)
  if (!m.matches()) return sql
  def head = m.group(1)
  def where = m.group(2)
  def storing = m.group(3)
  def sb = new StringBuilder(head)
  if (storing!=null) sb.append(" STORING (").append(storing).append(")")
  if (where!=null) sb.append(" WHERE ").append(where)
  sb.toString()
}

// Parse column list in CREATE TABLE (...). Returns [ [name,type], ... ]
def parseCreateTableColumns = { String sql ->
  int start = sql.indexOf('('); if (start<0) return []
  int i=start+1, depth=1
  boolean inS=false,inD=false
  def buf=new StringBuilder(); def parts=[]
  while (i<sql.length() && depth>0){
    char c = sql.charAt(i)
    if (inS){ if (c=='\'' && i+1<sql.length() && sql.charAt(i+1)=='\''){ buf.append("''"); i+=2; continue }
              if (c=='\'') inS=false; buf.append(c); i++; continue }
    if (inD){ if (c=='"') inD=false; buf.append(c); i++; continue }
    if (c=='\''){ inS=true; buf.append(c); i++; continue }
    if (c=='"'){ inD=true; buf.append(c); i++; continue }
    if (c=='('){ depth++; buf.append(c); i++; continue }
    if (c==')'){ depth--; if (depth==0){ i++; break } buf.append(c); i++; continue }
    if (c==',' && depth==1){ parts<<buf.toString().trim(); buf.setLength(0); i++; continue }
    buf.append(c); i++
  }
  if (buf.length()>0) parts<<buf.toString().trim()
  def cols=[]
  parts.each{ p->
    def upP = p.toUpperCase(Locale.ROOT).trim()
    if (upP.startsWith('PRIMARY ')||upP.startsWith('CONSTRAINT ')||upP.startsWith('UNIQUE ')||
        upP.startsWith('FOREIGN ')||upP.startsWith('CHECK ')||upP.startsWith('FAMILY ')||
        upP.startsWith('INDEX ')) {
      // skip table-level items here
    } else {
      def m = (p =~ /(?is)^\s*("?[^"]+"|[A-Za-z_]\w*)\s+(.+?)\s*(?:DEFAULT|NOT\s+NULL|NULL|PRIMARY|REFERENCES|CONSTRAINT|CHECK|UNIQUE|FAMILY|\Z)/)
      if (m.find()){
        def col = m.group(1).replaceAll('^"|"$','')
        def typ = m.group(2).trim()
        cols << [col, typ]
      }
    }
  }
  cols
}

// Parse FAMILY clauses from a CREATE TABLE string (or SHOW CREATE TABLE output)
def parseFamilies = { String sql ->
  def fams = [:].withDefault{ new LinkedHashSet<String>() }
  def re = /(?is)\bFAMILY\s+("?[^"]+"|[A-Za-z_]\w*)\s*\(([^)]*)\)/
  def m = (sql =~ re)
  while (m.find()){
    def fam = m.group(1).replaceAll('^"|"$','')
    def cols = m.group(2).split(',')
                .collect{ it.trim().replaceAll('^"|"$','') }
                .findAll{ it.length()>0 }
    cols.each{ fams[fam].add(it) }
  }
  fams
}

// type helpers (for widening)
def strLen = { t -> def m=(t.toUpperCase()=~/STRING\s*\((\d+)\)/); m.find()? Integer.valueOf(m.group(1)) : null }
def decPS = { t -> def m=(t.toUpperCase()=~/DECIMAL\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)/); m.find()? [m.group(1) as Integer, m.group(2) as Integer] : null }

// DB helpers
Connection conn = null
try {
  conn = dbcp.getConnection(); conn.setAutoCommit(true)

  def q = { String sqlQ, List params = [] ->
    def out=[]; def ps=conn.prepareStatement(sqlQ)
    for (int i=0;i<params.size();i++) ps.setObject(i+1, params[i])
    def rs=ps.executeQuery(); def md=rs.metaData
    while (rs.next()){
      def row=[:]; for (int c=1;c<=md.columnCount;c++) row[md.getColumnLabel(c).toLowerCase(Locale.ROOT)] = rs.getObject(c)
      out<<row
    }
    rs.close(); ps.close(); out
  }
  def tableExists = { sch,tbl -> q("SELECT 1 FROM information_schema.tables WHERE table_schema=? AND table_name=?", [sch,tbl]).size()>0 }
  def loadCols = { sch,tbl ->
    def rows = q("""SELECT column_name, data_type, character_maximum_length, numeric_precision, numeric_scale
                    FROM information_schema.columns WHERE table_schema=? AND table_name=?""",[sch,tbl])
    def m=[:]; rows.each{ r-> m[r['column_name']] = [ (r['data_type']?:'').toString().toUpperCase(Locale.ROOT),
                                                      r['character_maximum_length'] as Integer,
                                                      r['numeric_precision'] as Integer,
                                                      r['numeric_scale'] as Integer ] }
    m
  }
  def indexExists = { sch,tbl,idx -> q("SELECT 1 FROM pg_catalog.pg_indexes WHERE schemaname=? AND tablename=? AND indexname=?", [sch,tbl,idx]).size()>0 }
  def constraintExists = { sch,tbl,con ->
    q("""SELECT 1
         FROM pg_catalog.pg_constraint c
         JOIN pg_catalog.pg_class r ON c.conrelid=r.oid
         JOIN pg_catalog.pg_namespace n ON r.relnamespace=n.oid
         WHERE n.nspname=? AND r.relname=? AND c.conname=?""",[sch,tbl,con]).size()>0
  }
  def showCreate = { sch,tbl ->
    def rows = q("SHOW CREATE TABLE \""+sch+"\".\""+tbl+"\"")
    rows.isEmpty() ? "" : (rows[0]['create_statement'] as String)
  }

  // detection
  String objType='other', objSchema=targetSchema, objTable=null
  String outSql = orig
  String phase='other'

  def mCT = (up =~ /(?is)^\s*CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?((?:"[^"]+"|[A-Za-z_]\w*)(?:\.(?:"[^"]+"|[A-Za-z_]\w*))?)/)
  def mCI = (up =~ /(?is)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:"[^"]+"|[A-Za-z_]\w*)\s+ON\s+((?:"[^"]+"|[A-Za-z_]\w*)(?:\.(?:"[^"]+"|[A-Za-z_]\w*))?)/)
  def mAC = (up =~ /(?is)^\s*ALTER\s+TABLE\s+((?:"[^"]+"|[A-Za-z_]\w*)(?:\.(?:"[^"]+"|[A-Za-z_]\w*))?)\s+ADD\s+CONSTRAINT\s+(?:"[^"]+"|[A-Za-z_]\w*)\b/)
  def mADDC = (up =~ /(?is)^\s*ALTER\s+TABLE\s+((?:"[^"]+"|[A-Za-z_]\w*)(?:\.(?:"[^"]+"|[A-Za-z_]\w*))?)\s+ADD\s+COLUMN\b/)
  def mADDFAM = (up =~ /(?is)^\s*ALTER\s+TABLE\s+((?:"[^"]+"|[A-Za-z_]\w*)(?:\.(?:"[^"]+"|[A-Za-z_]\w*))?)\s+ADD\s+FAMILY\s+(?:"[^"]+"|[A-Za-z_]\w*)\b/)

  if (mCT.find()){
    objType='create_table'; phase='create_table'
    def pair = parseQIdent(mCT.group(1)); if (pair[0]!=null) objSchema=pair[0]; objTable=pair[1]

    if (mode=='drop_and_apply') {
      // Strip IF NOT EXISTS from CREATE and drop first
      def createClean = orig.replaceFirst(/(?is)\bIF\s+NOT\s+EXISTS\b/, '')
      outSql = "BEGIN; DROP TABLE IF EXISTS \"${objSchema}\".\"${objTable}\" CASCADE; ${createClean.trim().replaceAll(';+$','')}; COMMIT"
    } else {
      boolean exists = tableExists(objSchema,objTable)
      if (!exists){
        // ensure IF NOT EXISTS
        outSql = orig.replaceFirst(/(?is)CREATE\s+TABLE\s+/, 'CREATE TABLE IF NOT EXISTS ')
      } else {
        // table exists -> additive updates
        def targetCols = parseCreateTableColumns(orig)
        def targetFams = parseFamilies(orig)
        def currentCols = loadCols(objSchema,objTable)
        def currentFams = parseFamilies(showCreate(objSchema,objTable))

        def adds = []
        def alters = []
        def addFamilies = []

        // Add missing columns (and attach to target family when known)
        targetCols.each{ c ->
          def name = c[0]; def typ = c[1]
          if (!currentCols.containsKey(name)){
            def fam = targetFams.find{ k,v -> v.contains(name) }?.key
            def clause = "ADD COLUMN IF NOT EXISTS \"${name}\" ${typ}"
            if (fam!=null) clause += " FAMILY \"${fam}\""
            adds << clause
          } else if (mode=='apply_and_update_existing'){
            // safe widen
            def cur = currentCols[name]
            def curType=cur[0]; def curLen=cur[1]; def curPrec=cur[2]; def curScale=cur[3]
            def tLen = strLen(typ); def tPS = decPS(typ)
            if (tLen!=null && curType.startsWith('STRING') && (curLen==null || tLen>curLen))
              alters << "ALTER COLUMN \"${name}\" TYPE STRING(${tLen})"
            if (tPS!=null && curType.startsWith('DECIMAL')){
              if (curPrec==null || curScale==null || tPS[0]>curPrec || tPS[1]>curScale)
                alters << "ALTER COLUMN \"${name}\" TYPE DECIMAL(${tPS[0]},${tPS[1]})"
            }
          }
        }

        // Families: add missing families; move columns (apply_and_update_existing only)
        targetFams.each{ famName, cols ->
          if (!currentFams.containsKey(famName)){
            // create family with columns that already exist (new cols were handled in adds with FAMILY)
            def existingCols = cols.findAll{ currentCols.containsKey(it) }
            if (!existingCols.isEmpty()){
              addFamilies << "ADD FAMILY \"${famName}\" (" + existingCols.collect{ "\"${it}\"" }.join(", ") + ")"
            } else {
              // nothing existing yet -> emit an empty family creation by attaching after adds via ALTER COLUMN SET FAMILY as columns appear
              // No separate action needed here.
            }
          } else if (mode=='apply_and_update_existing'){
            def curCols = currentFams[famName]
            cols.each{ cName ->
              if (currentCols.containsKey(cName) && !curCols.contains(cName)){
                alters << "ALTER COLUMN \"${cName}\" SET FAMILY \"${famName}\""
              }
            }
          }
        }

        if (adds.isEmpty() && alters.isEmpty() && addFamilies.isEmpty()){
          outSql = NOOP_SQL
        } else {
          def parts = []
          parts.addAll(adds)
          parts.addAll(addFamilies)   // create families after adds
          parts.addAll(alters)        // then alters (type/family moves)
          outSql = "ALTER TABLE \"${objSchema}\".\"${objTable}\" " + parts.join(', ')
        }
      }
    }
  }
  else if (mCI.find()){
    objType='create_index'; phase='index'
    def idxNameM = (orig =~ /(?is)^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?("?[^"]+"|[A-Za-z_]\w*)/)
    String idxName = idxNameM.find() ? idxNameM.group(1).replaceAll('^"|"$','') : null
    def pair = parseQIdent(mCI.group(1)); if (pair[0]!=null) objSchema=pair[0]; objTable=pair[1]

    if (mode=='drop_and_apply') {
      def createClean = fixIndexOrder(orig.replaceFirst(/(?is)\bIF\s+NOT\s+EXISTS\b/, ''))
      outSql = "BEGIN; DROP INDEX IF EXISTS \"${objSchema}\".\"${objTable}\"@\"${idxName}\"; ${createClean.trim().replaceAll(';+$','')}; COMMIT"
    } else {
      boolean exists = (idxName!=null) ? indexExists(objSchema,objTable,idxName) : false
      if (exists){
        outSql = NOOP_SQL
      } else {
        outSql = fixIndexOrder(orig.replaceFirst(/(?is)CREATE\s+(UNIQUE\s+)?INDEX\s+/, { m -> "CREATE " + (m[0].toUpperCase().contains('UNIQUE')?'UNIQUE ':'') + "INDEX IF NOT EXISTS " }))
      }
    }
  }
  else if (mAC.find()){
    objType='add_constraint'; phase='constraint'
    def pair = parseQIdent(mAC.group(1)); if (pair[0]!=null) objSchema=pair[0]; objTable=pair[1]
    def conM = (orig =~ /(?is)\bADD\s+CONSTRAINT\s+(("?[^"]+"|[A-Za-z_]\w*))/)
    String conName = conM.find()? conM.group(1).replaceAll('^"|"$','') : null

    if (mode=='drop_and_apply') {
      def addClean = orig // keep as-is (no IF NOT EXISTS needed here)
      outSql = "BEGIN; ALTER TABLE \"${objSchema}\".\"${objTable}\" DROP CONSTRAINT IF EXISTS \"${conName}\"; ${addClean.trim().replaceAll(';+$','')}; COMMIT"
    } else {
      boolean exists = (conName!=null) ? constraintExists(objSchema,objTable,conName) : false
      outSql = exists ? NOOP_SQL : orig.replaceFirst(/(?is)\bADD\s+CONSTRAINT\s+/, 'ADD CONSTRAINT IF NOT EXISTS ')
    }
  }
  else if (mADDC.find()){
    objType='alter_add_column'; phase='alter_table'
    def pair = parseQIdent(mADDC.group(1)); if (pair[0]!=null) objSchema=pair[0]; objTable=pair[1]
    outSql = orig.replaceFirst(/(?is)\bADD\s+COLUMN\s+/, 'ADD COLUMN IF NOT EXISTS ')
  }
  else if (mADDFAM.find()){
    objType='family'; phase='family'
    def pair = parseQIdent(mADDFAM.group(1)); if (pair[0]!=null) objSchema=pair[0]; objTable=pair[1]
    def famM = (orig =~ /(?is)\bADD\s+FAMILY\s+(("?[^"]+"|[A-Za-z_]\w*))/)
    String famName = famM.find()? famM.group(1).replaceAll('^"|"$','') : null

    if (mode=='drop_and_apply') {
      outSql = "BEGIN; ALTER TABLE \"${objSchema}\".\"${objTable}\" DROP FAMILY IF EXISTS \"${famName}\"; ${orig.trim().replaceAll(';+$','')}; COMMIT"
    } else {
      // Check if the family already exists to avoid error (no IF NOT EXISTS for family)
      def famM = (orig =~ /(?is)\bADD\s+FAMILY\s+(("?[^"]+"|[A-Za-z_]\w*))/)
      String famName = famM.find()? famM.group(1).replaceAll('^"|"$','') : null
      def currentFams = parseFamilies(showCreate(objSchema,objTable))
      outSql = (famName!=null && currentFams.containsKey(famName)) ? NOOP_SQL : orig
    }
  }
  else {
    objType='other'; phase='other'
    outSql = (mode=='drop_and_apply') ? orig : orig // typically safe
  }

  outSql = outSql.trim()
  if (outSql.isEmpty()) outSql = NOOP_SQL   // never skip

  // write + attrs
  writeContent(ff, outSql)
  ff = session.putAttribute(ff, 'obj.type', objType)
  ff = session.putAttribute(ff, 'obj.schema', objSchema)
  if (objTable!=null) ff = session.putAttribute(ff, 'obj.table', objTable)
  ff = session.putAttribute(ff, 'ddl.phase', phase)
  session.transfer(ff, REL_SUCCESS)

} catch (Throwable t){
  ff = session.putAttribute(ff, 'ddl.error', t.class.name + ': ' + t.message)
  session.transfer(ff, REL_FAILURE)
} finally {
  try { if (conn!=null) conn.close() } catch (ignored){}
}
