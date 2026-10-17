## Exportación de resultados a CSV (M-005).

import std/[times, strformat, strutils]
import ./types, ./errorlog

proc csvField(s: string): string =
  ## Escapa un campo según RFC 4180: si contiene coma, comilla o salto de
  ## línea, lo envuelve en comillas y duplica las comillas internas. Hoy
  ## ningún valor real los necesita (fecha de formato fijo, 3 nombres de
  ## universo sin comas, tickers alfanuméricos), pero evita que el CSV se
  ## corra en silencio si eso cambia (M-021).
  if s.contains({',', '"', '\n', '\r'}):
    "\"" & s.replace("\"", "\"\"") & "\""
  else:
    s

proc exportCsv*(filename: string, rows: seq[tuple[universo: string, q: Quote]]) =
  var f: File
  if not open(f, filename, fmWrite):
    logError("No se pudo escribir el archivo CSV: " & filename)
    return
  defer: f.close()

  let fecha = now().format("yyyy-MM-dd")

  f.writeLine("fecha,universo,ticker,ret1m,ret3m,ret6m,score,precio,sma50,sobre_sma50")
  for r in rows:
    let sobreSma50 = if r.q.aboveSma50: 1 else: 0
    let universo = csvField(r.universo)
    let ticker = csvField(r.q.ticker)
    f.writeLine(fmt"{fecha},{universo},{ticker},{r.q.ret1m:.2f},{r.q.ret3m:.2f},{r.q.ret6m:.2f},{r.q.score:.2f},{r.q.price:.2f},{r.q.sma50:.2f},{sobreSma50}")

  echo "\nResultados exportados a ", filename
