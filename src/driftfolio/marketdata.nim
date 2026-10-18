## Acceso a datos de mercado externos: precios históricos y tasa libre de
## riesgo desde Yahoo Finance, y el listado de holdings mega-cap desde iShares.
##
## Las descargas son asíncronas (M-009): cada petición corre sobre su propio
## AsyncHttpClient de corta vida. Un mismo AsyncHttpClient no admite más de
## una petición en vuelo a la vez (guarda el socket y la URL actual como
## estado de instancia), así que no se puede compartir un solo cliente entre
## descargas concurrentes como hacía la versión secuencial.

import std/[asyncdispatch, httpclient, json, strutils, times, strformat,
            parsecsv, streams, os, net, uri]
import ./errorlog

const
  MegaCapCsvUrl* =
    "https://www.ishares.com/us/products/239723/ishares-s-p-100-etf/latest-holdings.csv"

  RequestTimeoutMs* = 15_000  ## M-016: ninguna petición espera más que esto.
  MaxFetchAttempts* = 3       ## M-003: reintentos sobre errores transitorios.
  RetryBaseDelayMs* = 500     ## backoff lineal: 500ms, 1000ms, ...

  CacheDir* = ".driftfolio_cache"  ## M-010: precios cacheados por ticker/día.

var skipCache* = false
  ## M-022: con --no-cache, ignora los precios ya cacheados hoy y vuelve a
  ## descargar todo desde Yahoo Finance. No borra `.driftfolio_cache/`: los
  ## archivos frescos que se descarguen igual se escriben ahí (writePriceCache
  ## no mira este flag), así que una corrida normal posterior el mismo día
  ## vuelve a aprovechar el caché ya actualizado.

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

# ============================================================
# Reintentos (M-003)
# ============================================================

proc isTransientStatus(statusMsg: string): bool =
  ## `HttpRequestError.msg` trae el status line crudo de la respuesta
  ## ("429 Too Many Requests", "503 Service Unavailable", ...). Solo vale la
  ## pena reintentar sobre errores transitorios (rate-limit y errores del
  ## servidor); un 4xx normal (ticker inválido, endpoint movido) es permanente
  ## y reintentarlo solo demora el fallo.
  statusMsg.startsWith("429") or statusMsg.startsWith("5")

proc isTransientError(e: ref Exception): bool =
  (e of HttpRequestError and isTransientStatus(e.msg)) or e of TimeoutError

# ============================================================
# Timeout (M-016)
# ============================================================

proc requestWithTimeout(client: AsyncHttpClient, url: string): Future[string] {.async.} =
  ## `AsyncHttpClient` no tiene parámetro `timeout` (a diferencia de la
  ## versión sync): se implementa carreando la petición contra un timer.
  let fut = client.getContent(url)
  if not await fut.withTimeout(RequestTimeoutMs):
    raise newException(TimeoutError, "Timeout tras " & $RequestTimeoutMs & "ms: " & url)
  result = fut.read()

# ============================================================
# Cache de precios por día (M-010)
# ============================================================

proc cacheFilePath(ticker: string, lookbackDays: int): string =
  var safe = ticker
  for i in 0 ..< safe.len:
    if not (safe[i] in {'a'..'z', 'A'..'Z', '0'..'9', '-', '.'}):
      safe[i] = '_'
  CacheDir / (safe & "_" & $lookbackDays & "_" & now().format("yyyy-MM-dd") & ".json")

proc isPriceCached*(ticker: string, lookbackDays: int): bool =
  ## Chequeo barato (solo existencia de archivo) para que el orquestador
  ## (`ranking`/`markowitz`) pueda saltarse la pausa de ritmo de despacho
  ## cuando sabe que esa descarga en particular no va a pegarle a la red.
  ## Con --no-cache devuelve siempre false: esa descarga sí va a pegarle a
  ## la red, así que el ritmo de despacho (pacing) debe respetarse igual
  ## que en una corrida sin caché.
  not skipCache and fileExists(cacheFilePath(ticker, lookbackDays))

proc readPriceCache(path: string): seq[float] =
  try:
    let data = parseJson(readFile(path))
    if data.kind == JArray:
      for item in data:
        if item.kind in {JFloat, JInt}:
          result.add(item.getFloat)
  except CatchableError:
    result = @[]  # cache corrupto: se ignora y se vuelve a descargar

proc writePriceCache(path: string, prices: seq[float]) =
  try:
    createDir(CacheDir)
    writeFile(path, $(%prices))
  except CatchableError as e:
    logError("No se pudo escribir la caché de precios (" & path & "): " & e.msg)

# ============================================================
# Parseo del JSON de Yahoo Finance (M-018: separado del I/O de red para
# poder testearlo con JSON sintético, ver tests/test_marketdata_parsing.nim)
# ============================================================

proc parseAdjClosePrices*(data: JsonNode): tuple[prices: seq[float], error: string] =
  ## Extrae la lista de precios de cierre ajustado, validando cada nivel
  ## antes de indexar (M-012). `error` queda vacío si todo salió bien.
  let resultArr = data{"chart", "result"}
  if resultArr.isNil or resultArr.kind != JArray or resultArr.len == 0:
    return (newSeq[float](), "falta chart.result")

  let adjcloseArr = resultArr[0]{"indicators", "adjclose"}
  if adjcloseArr.isNil or adjcloseArr.kind != JArray or adjcloseArr.len == 0:
    return (newSeq[float](), "falta indicators.adjclose")

  let adjclose = adjcloseArr[0]{"adjclose"}
  if adjclose.isNil or adjclose.kind != JArray:
    return (newSeq[float](), "falta adjclose")

  var prices: seq[float]
  for item in adjclose:
    if item.kind == JFloat and item.getFloat > 0:
      prices.add(item.getFloat)
    elif item.kind == JInt and item.getInt > 0:
      prices.add(item.getInt.float)
  (prices, "")

# ============================================================
# Descargas
# ============================================================

proc fetchMegaCapTickers*(): Future[seq[string]] {.async.} =
  let client = newAsyncHttpClient(userAgent = "Mozilla/5.0")
  try:
    let content = await requestWithTimeout(client, MegaCapCsvUrl)
    client.close()
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
    client.close()
    logError("Error obteniendo listado de mega-cap: " & e.msg & " (" & $e.name & ")")

proc fetchPrices*(ticker: string, lookbackDays: int = 365): Future[seq[float]] {.async.} =
  let cachePath = cacheFilePath(ticker, lookbackDays)
  if not skipCache and fileExists(cachePath):
    let cached = readPriceCache(cachePath)
    if cached.len > 0:
      return cached

  let
    period2 = epochTime().int
    period1 = period2 - (lookbackDays * 24 * 3600)
    url = fmt"https://query1.finance.yahoo.com/v8/finance/chart/{encodeUrl(ticker)}?period1={period1}&period2={period2}&interval=1d&events=history"

  for attempt in 1 .. MaxFetchAttempts:
    let client = newAsyncHttpClient(userAgent = "Mozilla/5.0")
    try:
      let content = await requestWithTimeout(client, url)
      client.close()

      let parsed = parseAdjClosePrices(parseJson(content))
      if parsed.error.len > 0:
        logError("Respuesta inesperada de Yahoo Finance para " & ticker & ": " & parsed.error)
        return

      result = parsed.prices
      if result.len > 0:
        writePriceCache(cachePath, result)
      return
    except CatchableError as e:
      client.close()
      if isTransientError(e) and attempt < MaxFetchAttempts:
        await sleepAsync(RetryBaseDelayMs * attempt)
      else:
        logError("Error obteniendo datos de " & ticker & ": " & e.msg & " (" & $e.name & ")")
        return

proc fetchRiskFreeRate*(): Future[float] {.async.} =
  # ^IRX = letras del Tesoro de EEUU a 13 semanas, cotiza como % anual (ej. 4.07 = 4.07%)
  try:
    let prices = await fetchPrices("^IRX", 30)
    if prices.len == 0:
      logError("No se pudo obtener la tasa libre de riesgo (^IRX), se asume 0%")
      return 0.0
    result = prices[^1] / 100.0
  except CatchableError as e:
    logError("Error obteniendo tasa libre de riesgo: " & e.msg & " (" & $e.name & ")")
    result = 0.0
