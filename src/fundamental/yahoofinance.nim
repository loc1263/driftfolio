## Cliente minimo para la API no oficial "quoteSummary" de Yahoo Finance.
##
## Yahoo exige una cookie de sesion + un "crumb" (token anti-CSRF) para los
## endpoints query1/query2.finance.yahoo.com. El flujo es:
##   1. GET https://fc.yahoo.com            -> entrega una cookie de sesion
##   2. GET https://query2.finance.yahoo.com/v1/test/getcrumb (con la cookie)
##      -> entrega el crumb como texto plano
##   3. GET quoteSummary/{ticker}?modules=...&crumb=<crumb> (con la cookie)
##
## Las descargas de empresas se hacen en paralelo (async, con un tope de
## conexiones simultaneas) en vez de una por una: con ~60 tickers, eso es la
## diferencia entre ~25s y ~3s de pared.

import std/[httpclient, asyncdispatch, json, options, strutils, tables]

const UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chile_Fundamental/0.2"

type
  YahooSession* = object
    cookie*: string
    crumb*: string

  CompanyRaw* = object
    ticker*: string
    name*: string
    currency*: string
    marketCap*: Option[float]
    price*: Option[float]
    trailingPE*: Option[float]
    forwardPE*: Option[float]
    priceToBook*: Option[float]
    dividendYield*: Option[float]
    returnOnEquity*: Option[float]
    returnOnAssets*: Option[float]
    profitMargins*: Option[float]
    operatingMargins*: Option[float]
    debtToEquity*: Option[float]
    currentRatio*: Option[float]
    revenueGrowth*: Option[float]
    earningsGrowth*: Option[float]
    sector*: string
    industry*: string
    enterpriseValue*: Option[float]
    ebitda*: Option[float]
    evToEbitda*: Option[float]
    freeCashflow*: Option[float]
    fcfYield*: Option[float]
    pegRatio*: Option[float]
    targetMeanPrice*: Option[float]
    targetUpside*: Option[float]
    recommendationMean*: Option[float]
    recommendationKey*: string
    numberOfAnalystOpinions*: Option[float]
    fetchError*: string

proc extractCookie(setCookieHeaders: seq[string]): string =
  ## Nos quedamos solo con el par nombre=valor de cada Set-Cookie, unidos con "; ".
  var parts: seq[string] = @[]
  for h in setCookieHeaders:
    let firstPair = h.split(';')[0].strip()
    if firstPair.len > 0:
      parts.add(firstPair)
  result = parts.join("; ")

proc collectSetCookies(headers: HttpHeaders): seq[string] =
  result = @[]
  if headers.isNil:
    return
  if headers.hasKey("set-cookie"):
    # Nim junta varios Set-Cookie repetidos con ", " en el mismo valor; eso
    # rompe el parseo porque las fechas de expiracion tambien llevan comas.
    # Por eso solo usamos el primer par nombre=valor de todo el bloque, que
    # alcanza para identificar la cookie de sesion principal (A3/A1/B).
    for raw in headers.table.getOrDefault("set-cookie"):
      result.add(raw)

proc fetchCookieFrom(client: HttpClient, url: string): string =
  try:
    let resp = client.request(url)
    return extractCookie(collectSetCookies(resp.headers))
  except CatchableError:
    return ""

proc newYahooSession*(): YahooSession =
  ## Obtiene la cookie de sesion y el crumb necesarios para consultar quoteSummary.
  ## Esto se hace una sola vez por ejecucion (no por ticker).
  var client = newHttpClient(userAgent = UserAgent, timeout = 15000)
  defer: client.close()

  var cookie = fetchCookieFrom(client, "https://fc.yahoo.com")
  if cookie.len == 0:
    cookie = fetchCookieFrom(client, "https://finance.yahoo.com")
  if cookie.len > 0:
    client.headers["Cookie"] = cookie
  let crumb = client.getContent("https://query2.finance.yahoo.com/v1/test/getcrumb").strip()

  result = YahooSession(cookie: cookie, crumb: crumb)

proc getF(n: JsonNode, key: string): Option[float] =
  if n.isNil or n.kind != JObject:
    return none(float)
  if not n.hasKey(key):
    return none(float)
  let field = n[key]
  if field.kind == JObject and field.hasKey("raw"):
    let raw = field["raw"]
    if raw.kind == JFloat or raw.kind == JInt:
      return some(raw.getFloat())
  elif field.kind == JFloat or field.kind == JInt:
    return some(field.getFloat())
  return none(float)

proc getS(n: JsonNode, key: string): string =
  if n.isNil or n.kind != JObject or not n.hasKey(key):
    return ""
  let field = n[key]
  if field.kind == JString:
    return field.getStr()
  return ""

const Modules = "financialData,summaryDetail,defaultKeyStatistics,price,assetProfile"

proc parseCompany(ticker, body: string): CompanyRaw =
  result = CompanyRaw(ticker: ticker)

  var root: JsonNode
  try:
    root = parseJson(body)
  except CatchableError as e:
    result.fetchError = "JSON parse error: " & e.msg
    return

  let qs = root{"quoteSummary"}
  if qs.isNil:
    result.fetchError = "respuesta sin quoteSummary"
    return
  let results = qs{"result"}
  if results.isNil or results.kind != JArray or results.len == 0:
    let err = qs{"error"}
    if not err.isNil and err.kind == JObject:
      result.fetchError = "Yahoo error: " & getS(err, "description")
    else:
      result.fetchError = "sin resultados para " & ticker
    return

  let r = results[0]
  let price = r{"price"}
  let summaryDetail = r{"summaryDetail"}
  let dks = r{"defaultKeyStatistics"}
  let fin = r{"financialData"}
  let profile = r{"assetProfile"}

  if not price.isNil:
    let nm = getS(price, "longName")
    result.name = if nm.len > 0: nm else: getS(price, "shortName")
    result.currency = getS(price, "currency")
    result.marketCap = getF(price, "marketCap")
    result.price = getF(price, "regularMarketPrice")

  if not summaryDetail.isNil:
    result.trailingPE = getF(summaryDetail, "trailingPE")
    result.forwardPE = getF(summaryDetail, "forwardPE")
    result.dividendYield = getF(summaryDetail, "dividendYield")

  if not dks.isNil:
    result.priceToBook = getF(dks, "priceToBook")
    result.enterpriseValue = getF(dks, "enterpriseValue")
    result.evToEbitda = getF(dks, "enterpriseToEbitda")
    if result.forwardPE.isNone:
      result.forwardPE = getF(dks, "forwardPE")

  if not fin.isNil:
    result.returnOnEquity = getF(fin, "returnOnEquity")
    result.returnOnAssets = getF(fin, "returnOnAssets")
    result.profitMargins = getF(fin, "profitMargins")
    result.operatingMargins = getF(fin, "operatingMargins")
    result.debtToEquity = getF(fin, "debtToEquity")
    result.currentRatio = getF(fin, "currentRatio")
    result.revenueGrowth = getF(fin, "revenueGrowth")
    result.earningsGrowth = getF(fin, "earningsGrowth")
    result.ebitda = getF(fin, "ebitda")
    result.freeCashflow = getF(fin, "freeCashflow")
    result.targetMeanPrice = getF(fin, "targetMeanPrice")
    result.recommendationMean = getF(fin, "recommendationMean")
    result.recommendationKey = getS(fin, "recommendationKey")
    result.numberOfAnalystOpinions = getF(fin, "numberOfAnalystOpinions")
    if result.price.isNone:
      result.price = getF(fin, "currentPrice")

  if not profile.isNil:
    result.sector = getS(profile, "sector")
    result.industry = getS(profile, "industry")

  # FCF yield = flujo de caja libre / capitalizacion bursatil. Se calcula
  # aca (no viene directo de Yahoo) porque ambos insumos ya estan disponibles.
  if result.freeCashflow.isSome and result.marketCap.isSome and result.marketCap.get() != 0.0:
    result.fcfYield = some(result.freeCashflow.get() / result.marketCap.get())

  # Upside del precio objetivo promedio de analistas vs. el precio actual.
  # Dato informativo (consenso de mercado), no es parte del score fundamental.
  if result.targetMeanPrice.isSome and result.price.isSome and result.price.get() != 0.0:
    result.targetUpside = some((result.targetMeanPrice.get() - result.price.get()) / result.price.get())

  # PEG = P/E ajustado por crecimiento de utilidades. Solo tiene sentido con
  # crecimiento positivo y no trivial; con crecimiento <= 1% o negativo el
  # ratio se vuelve absurdo o invierte de signo, asi que se deja sin dato.
  if result.trailingPE.isSome and result.earningsGrowth.isSome and result.earningsGrowth.get() > 0.01:
    result.pegRatio = some(result.trailingPE.get() / (result.earningsGrowth.get() * 100.0))

proc fetchCompanyAsync(session: YahooSession, ticker: string): Future[CompanyRaw] {.async.} =
  var client = newAsyncHttpClient(userAgent = UserAgent)
  defer: client.close()
  if session.cookie.len > 0:
    client.headers["Cookie"] = session.cookie
  client.headers["Accept"] = "application/json"

  let url = "https://query1.finance.yahoo.com/v10/finance/quoteSummary/" & ticker &
            "?modules=" & Modules & "&crumb=" & session.crumb
  try:
    let bodyFut = client.getContent(url)
    if not await bodyFut.withTimeout(20_000):
      result = CompanyRaw(ticker: ticker, fetchError: "timeout (20s)")
      return
    result = parseCompany(ticker, bodyFut.read())
  except CatchableError as e:
    result = CompanyRaw(ticker: ticker, fetchError: "HTTP error: " & e.msg)

proc fetchAll*(session: YahooSession, tickers: seq[string], maxConcurrent: int = 8): seq[CompanyRaw] =
  ## Descarga todos los tickers en paralelo, en lotes de hasta `maxConcurrent`
  ## conexiones simultaneas, para no saturar a Yahoo con cientos de requests
  ## de golpe pero sin pagar el costo de hacerlas una por una.
  result = newSeq[CompanyRaw](tickers.len)
  var i = 0
  while i < tickers.len:
    let batchEnd = min(i + maxConcurrent, tickers.len)
    stderr.writeLine("  descargando [" & $(i+1) & "-" & $batchEnd & "/" & $tickers.len & "]: " &
                      tickers[i ..< batchEnd].join(", "))
    var futs: seq[Future[CompanyRaw]] = @[]
    for j in i ..< batchEnd:
      futs.add(fetchCompanyAsync(session, tickers[j]))
    let batchResults = waitFor all(futs)
    for k in 0 ..< batchResults.len:
      result[i + k] = batchResults[k]
    i = batchEnd
