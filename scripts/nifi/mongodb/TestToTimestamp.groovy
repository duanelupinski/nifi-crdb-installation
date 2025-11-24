#!/usr/bin/env groovy
import java.time.*
import java.time.format.DateTimeFormatter

// --- paste YOUR latest toTimestampStringFast here, OR use the robust one below ---
String toTimestampStringFast(Object v, Map compiled = [:]) {
  if (v == null) return null
  String s = v.toString().trim()
  String tz = (compiled?.tz ?: compiled?.timezone ?: "UTC").toString()

  // try custom format if provided AND allowed by optional regex
  DateTimeFormatter fmt = (compiled?.fmt instanceof DateTimeFormatter) ? compiled.fmt :
                          (compiled?.format ? DateTimeFormatter.ofPattern(compiled.format.toString()) : null)
  String fmtRegex = compiled?.fmtRegex?.toString()
  boolean tryCustom = (fmt != null) && (!fmtRegex || (s ==~ fmtRegex))

  // If custom format requested:
  if (tryCustom) {
    // If value carries an explicit zone/offset, prefer OffsetDateTime
    if (s.endsWith("Z") || (s ==~ /.*[+-]\d{2}:?\d{2}$/)) {
      println "[BRANCH] custom: uses OffsetDateTime.parse"
      return OffsetDateTime.parse(s).toOffsetDateTime().toString()
    }
    println "[BRANCH] custom: LocalDateTime.parse with formatter"
    return LocalDateTime.parse(s, fmt).atZone(ZoneId.of(tz)).toOffsetDateTime().toString()
  }

  // Standard ISO attempts:
  try {
    println "[BRANCH] ISO OffsetDateTime.parse"
    return OffsetDateTime.parse(s).toOffsetDateTime().toString()
  } catch (Throwable ignore) {}

  try {
    println "[BRANCH] ISO Instant.parse + zone"
    return Instant.parse(s).atZone(ZoneId.of(tz)).toOffsetDateTime().toString()
  } catch (Throwable ignore) {}

  // Last-resort: a few common naive layouts
  def patterns = [
    "yyyy-MM-dd'T'HH:mm:ss.SSS",
    "yyyy-MM-dd'T'HH:mm:ss",
    "yyyy-MM-dd HH:mm:ss.SSS",
    "yyyy-MM-dd HH:mm:ss"
  ]
  for (p in patterns) {
    try {
      println "[BRANCH] fallback LocalDateTime with pattern ${p}"
      return LocalDateTime.parse(s, DateTimeFormatter.ofPattern(p)).atZone(ZoneId.of(tz)).toOffsetDateTime().toString()
    } catch (Throwable ignore) {}
  }
  println "[BRANCH] FAILED to parse"
  return null
}

// ----- try a few inputs -----
def samples = [
  "2025-08-14T18:45:07+0000",
  "2025-08-28T20:03:10.604-04:00",
  "2025-08-28T20:03:10.604+00:00",
  "2025-08-28T20:03:10.604+07:00",
  "2025-08-28T20:03:10Z",
  "2025-08-28T20:03:10",
  "2025-08-28 20:03:10",
  null,
  "not-a-date"
]

samples.each { s ->
  def out = toTimestampStringFast(s, [tz:"UTC"])
  println "${String.valueOf(s)}  =>  ${String.valueOf(out)}"
}
