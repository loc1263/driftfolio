## Acceso a datos de mercado externos: precios históricos y tasa libre de
## riesgo desde Yahoo Finance, y el listado de holdings mega-cap desde iShares.

import std/[httpclient, json, strutils, times, strformat, parsecsv, streams]
import ./errorlog

# Listado de holdings del ETF iShares S&P 100 (OEF): se descarga en vez de
# mantenerlo hardcodeado porque la composición de las mega-cap cambia seguido.
const MegaCapCsvUrl* =
  "https://www.ishares.com/us/products/239723/ishares-s-p-100-etf/latest-holdings.csv"

# ============================================================
# Enlaces a stockanalysis.com
# ============================================================
#
# EEUU (ETFs Vanguard y mega-cap, ticker sin sufijo): /stocks/{ticker}/
# Chile (sufijo .SN de Yahoo): /quote/snse/{ticker}/, y stockanalysis usa "."
# para las clases de acción en vez del "-" que usa Yahoo (ej. SQM-B -> SQM.B).

proc stockAnalysisUrl*(rawTicker: string): string =
  if rawTicker.endsWith(".SN"):
    let base = rawTicker[0 ..< rawTicker.len - 3].replace("-", ".")
    "https://stockanalysis.com/quote/snse/" & base & "/"
  else:
    "https://stockanalysis.com/stocks/" & rawTicker & "/"

proc fetchMegaCapTickers*(client: HttpClient): seq[string] =
  try:
    let content = client.getContent(MegaCapCsvUrl)
    let lines = content.splitLines()

    var headerIdx = -1
    for idx, line in lines:
      if line.startsWith("Ticker,"):
        headerIdx = idx
        break

    if headerIdx < 0:
      logError("No se encontró la tabla de holdings en el CSV de mega-cap")
      return

    var parser: CsvParser
    parser.open(newStringStream(lines[headerIdx .. ^1].join("\n")), "mega-cap.csv")
    parser.readHeaderRow()

    while parser.readRow():
      let assetClass = parser.rowEntry("Asset Class")
      let location = parser.rowEntry("Location")
      if assetClass == "Equity" and location == "United States":
        # Yahoo Finance usa "-" para clases de acciones (ej. BRK-B), el CSV trae espacio
        result.add(parser.rowEntry("Ticker").replace(" ", "-"))

    parser.close()
  except CatchableError as e:
    logError("Error obteniendo listado de mega-cap: " & e.msg & " (" & $e.name & ")")

proc fetchPrices*(client: HttpClient, ticker: string, lookbackDays: int = 365): seq[float] =
  let
    period2 = epochTime().int
    period1 = period2 - (lookbackDays * 24 * 3600)
    url = fmt"https://query1.finance.yahoo.com/v8/finance/chart/{ticker}?period1={period1}&period2={period2}&interval=1d&events=history"

  try:
    let content = client.getContent(url)
    let data = parseJson(content)

    # Se valida la forma de la respuesta antes de indexar: Yahoo Finance no
    # es una API oficial y puede devolver una estructura distinta a la
    # esperada (ticker inválido, error del lado del servidor, etc.) sin
    # avisar con un código de error HTTP.
    let resultArr = data{"chart", "result"}
    if resultArr.isNil or resultArr.kind != JArray or resultArr.len == 0:
      logError("Respuesta inesperada de Yahoo Finance para " & ticker & ": falta chart.result")
      return

    let adjcloseArr = resultArr[0]{"indicators", "adjclose"}
    if adjcloseArr.isNil or adjcloseArr.kind != JArray or adjcloseArr.len == 0:
      logError("Respuesta inesperada de Yahoo Finance para " & ticker & ": falta indicators.adjclose")
      return

    let adjclose = adjcloseArr[0]{"adjclose"}
    if adjclose.isNil or adjclose.kind != JArray:
      logError("Respuesta inesperada de Yahoo Finance para " & ticker & ": falta adjclose")
      return

    for item in adjclose:
      if item.kind == JFloat and item.getFloat > 0:
        result.add(item.getFloat)
      elif item.kind == JInt and item.getInt > 0:
        result.add(item.getInt.float)
  except CatchableError as e:
    logError("Error obteniendo datos de " & ticker & ": " & e.msg & " (" & $e.name & ")")

proc fetchRiskFreeRate*(client: HttpClient): float =
  # ^IRX = letras del Tesoro de EEUU a 13 semanas, cotiza como % anual (ej. 4.07 = 4.07%)
  try:
    let prices = fetchPrices(client, "^IRX", 30)
    if prices.len == 0:
      logError("No se pudo obtener la tasa libre de riesgo (^IRX), se asume 0%")
      return 0.0
    result = prices[^1] / 100.0
  except CatchableError as e:
    logError("Error obteniendo tasa libre de riesgo: " & e.msg & " (" & $e.name & ")")
    result = 0.0
