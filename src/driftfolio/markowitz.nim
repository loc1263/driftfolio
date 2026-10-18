## Markowitz: mejor portafolio sobre el top-N momentum (mega-cap)
##
## mu  = retorno esperado, proxy = score de momentum (ventana corta, régimen reciente)
## cov = covarianza EWMA sobre 5 años de retornos diarios (RiskMetrics, lambda=0.94),
##       da más peso a los datos recientes sin descartar la historia larga

import std/[asyncdispatch, strformat, strutils, sequtils, math]
import ./types, ./linalg, ./marketdata, ./display, ./htmlreport, ./errorlog, ./config

const DispatchIntervalMs = 200
# Los parámetros del portafolio (topN, histórico, EWMA lambda, tope por
# posición, portafolio concentrado) son configurables (M-006): ver
# config.Config y config.DefaultConfig para los valores de fábrica.

proc dispatchHistoryDownload(ticker: string, lookbackDays: int): Future[seq[float]] =
  ## proc de nivel superior a propósito (no una closure armada inline dentro
  ## del `for` de runMarkowitz): si el callback se arma ahí, Nim reusa la
  ## misma variable de loop entre iteraciones y TODOS los callbacks terminan
  ## imprimiendo el último ticker dispatchado en vez del que realmente
  ## completaron cada uno — es justo el bug que reportó el usuario (el mismo
  ## ticker repetido N veces seguidas en "Descargado: X"). Al recibir
  ## `ticker` como parámetro, cada llamada tiene su propio stack frame y el
  ## closure de abajo captura ESE valor, no una referencia compartida.
  result = fetchPrices(ticker, lookbackDays)
  result.addCallback proc() =
    echo "  Descargado: ", ticker

proc calcLogReturns(prices: seq[float]): seq[float] =
  result = newSeq[float](prices.len - 1)
  for i in 1 ..< prices.len:
    result[i - 1] = ln(prices[i] / prices[i - 1])

proc ewmaCovariance(returns: seq[seq[float]], lambda: float): seq[seq[float]] =
  # returns: T días x N activos. Recursión RiskMetrics: Sigma_t = lambda*Sigma_{t-1} + (1-lambda)*r_t*r_t^T
  let n = returns[0].len
  result = zeroMatrix(n)
  for day in returns:
    for i in 0 ..< n:
      for j in 0 ..< n:
        result[i][j] = lambda * result[i][j] + (1 - lambda) * day[i] * day[j]

proc optimizeLongOnlyCapped(mu: seq[float], cov: seq[seq[float]], cap: float,
                             iterations: int = 2000): seq[float] =
  # Maximiza el Sharpe ratio w^T mu / sqrt(w^T Sigma w) con proyección por
  # gradiente ascendente sobre el simplex capado (long-only, tope por posición).
  let n = mu.len
  var w = newSeq[float](n)
  for i in 0 ..< n:
    w[i] = 1.0 / n.float
  w = projectCappedSimplex(w, cap)

  const baseStep = 0.05

  for iter in 0 ..< iterations:
    var sigmaW = newSeq[float](n)
    for i in 0 ..< n:
      var s = 0.0
      for j in 0 ..< n:
        s += cov[i][j] * w[j]
      sigmaW[i] = s

    var wSigmaW = 0.0
    for i in 0 ..< n:
      wSigmaW += w[i] * sigmaW[i]
    if wSigmaW <= 0:
      break

    var muW = 0.0
    for i in 0 ..< n:
      muW += mu[i] * w[i]

    let denom = pow(wSigmaW, 1.5)
    var grad = newSeq[float](n)
    for i in 0 ..< n:
      grad[i] = mu[i] / sqrt(wSigmaW) - muW * sigmaW[i] / denom

    let lr = baseStep / sqrt((iter + 1).float)
    var wNew = newSeq[float](n)
    for i in 0 ..< n:
      wNew[i] = w[i] + lr * grad[i]

    w = projectCappedSimplex(wNew, cap)

  result = w

proc portfolioStats*(weights, mu: seq[float], cov: seq[seq[float]],
                      riskFreeRate: float): tuple[ret, vol, sharpe: float] =
  let n = weights.len
  var ret = 0.0
  for i in 0 ..< n:
    ret += weights[i] * mu[i]

  var varianceDaily = 0.0
  for i in 0 ..< n:
    for j in 0 ..< n:
      varianceDaily += weights[i] * weights[j] * cov[i][j]
  let vol = sqrt(abs(varianceDaily) * 252.0)
  let sharpe = if vol > 0: (ret - riskFreeRate) / vol else: 0.0
  (ret, vol, sharpe)

proc runMarkowitz*(topQuotes: seq[Quote],
                    lookbackYears = DefaultConfig.markowitzLookbackYears,
                    ewmaLambda = DefaultConfig.ewmaLambda,
                    maxWeightPerAsset = DefaultConfig.maxWeightPerAsset,
                    finalN = DefaultConfig.markowitzFinalN,
                    finalPortfolioCap = DefaultConfig.finalPortfolioCap): Future[string] {.async.} =
  echo "\n", "=".repeat(95)
  echo "MARKOWITZ - MEJOR PORTAFOLIO (top ", topQuotes.len, " por momentum, covarianza EWMA ", lookbackYears, " años)"
  echo "=".repeat(95)

  let riskFreeRate = await fetchRiskFreeRate()
  echo fmt"Tasa libre de riesgo (^IRX, 13 semanas): {riskFreeRate * 100:.2f}%"

  let lookbackDays = 365 * lookbackYears

  # Pipeline de descargas (M-009): se despacha una petición nueva cada
  # DispatchIntervalMs sin esperar la respuesta anterior, igual que en
  # ranking.processUniverse. El mensaje se imprime cuando cada descarga
  # realmente termina (callback), no al despacharla, para que refleje el
  # avance real en vez de aparecer todo junto apenas se lanzan las peticiones.
  echo "Descargando histórico de ", lookbackYears, " años para ", topQuotes.len, " activos..."
  var futs = newSeq[Future[seq[float]]](topQuotes.len)
  for idx, q in topQuotes:
    let ticker = q.ticker
    let wasAlreadyCached = isPriceCached(ticker, lookbackDays)
    futs[idx] = dispatchHistoryDownload(ticker, lookbackDays)
    if idx < topQuotes.len - 1 and not wasAlreadyCached:
      await sleepAsync(DispatchIntervalMs)

  var priceSeries: seq[seq[float]]
  var tickers: seq[string]
  var urls: seq[string]
  var muByTicker: seq[float]

  for idx, q in topQuotes:
    let prices = await futs[idx]
    if prices.len < 500:
      logError("  omitido (histórico insuficiente): " & q.ticker)
      continue
    priceSeries.add(prices)
    tickers.add(q.ticker)
    urls.add(q.url)
    muByTicker.add(q.score / 100.0)  # score venía en %, lo pasamos a fracción

  if tickers.len < 2:
    logError("No hay suficientes activos con histórico para optimizar.")
    return ""

  let minLen = priceSeries.mapIt(it.len).min
  var alignedReturns: seq[seq[float]]  # por ticker
  for prices in priceSeries:
    let trimmed = prices[(prices.len - minLen) .. ^1]
    alignedReturns.add(calcLogReturns(trimmed))

  let numDays = alignedReturns[0].len
  let numAssets = tickers.len

  var returnsMatrix: seq[seq[float]]  # días x activos
  for day in 0 ..< numDays:
    var row = newSeq[float](numAssets)
    for i in 0 ..< numAssets:
      row[i] = alignedReturns[i][day]
    returnsMatrix.add(row)

  let cov = ewmaCovariance(returnsMatrix, ewmaLambda)

  # Portafolio de máximo Sharpe: w ∝ Σ⁻¹ (μ - rf), no Σ⁻¹ μ
  var muExcess = newSeq[float](numAssets)
  for i in 0 ..< numAssets:
    muExcess[i] = muByTicker[i] - riskFreeRate

  let x = solveLinearSystem(cov, muExcess)
  let sumX = x.sum()

  if sumX == 0:
    logError("No se pudo normalizar el portafolio (suma de pesos = 0).")
    return ""

  var weights = newSeq[float](numAssets)
  for i in 0 ..< numAssets:
    weights[i] = x[i] / sumX

  echo "\n--- Sin restricciones (teórico, permite posiciones en corto) ---"
  printWeights(tickers, weights, useAbs = true)

  let (portReturn, portVolAnnual, sharpe) = portfolioStats(weights, muByTicker, cov, riskFreeRate)

  echo "-".repeat(24)
  echo fmt"Retorno esperado (proxy score momentum): {portReturn * 100:.2f}%"
  echo fmt"Volatilidad anualizada (cov. EWMA): {portVolAnnual * 100:.2f}%"
  echo fmt"Sharpe (vs. tasa libre de riesgo): {sharpe:.2f}"
  echo "Nota: pesos negativos implican posición corto, no ejecutable en un bróker normal."

  # --- Long-only con tope por posición (ejecutable en un bróker normal) ---
  # M-015: con el tope fijo (20%), si quedan pocos activos la restricción
  # Σw_i=1 puede ser infactible (numAssets * cap < 1) y la proyección
  # convergía en silencio a pesos que no suman 100%. Se sube el tope al
  # mínimo que la hace factible, igual que ya hacía el portafolio
  # concentrado más abajo, y se deja registrado si tuvo que subir.
  let loCap = max(maxWeightPerAsset, 1.0 / numAssets.float)
  if loCap > maxWeightPerAsset:
    logError(fmt"Tope por posición subido de {maxWeightPerAsset * 100:.0f}% a {loCap * 100:.0f}% " &
      fmt"porque solo hay {numAssets} activos (con el tope original los pesos no podrían sumar 100%).")

  let loWeights = optimizeLongOnlyCapped(muExcess, cov, loCap)

  echo ""
  echo fmt"--- Long-only, tope {loCap * 100:.0f}% por posición (ejecutable en un bróker normal) ---"
  printWeights(tickers, loWeights, 0.0001)

  let (loPortReturn, loPortVolAnnual, loSharpe) = portfolioStats(loWeights, muByTicker, cov, riskFreeRate)

  echo "-".repeat(24)
  echo fmt"Retorno esperado (proxy score momentum): {loPortReturn * 100:.2f}%"
  echo fmt"Volatilidad anualizada (cov. EWMA): {loPortVolAnnual * 100:.2f}%"
  echo fmt"Sharpe (vs. tasa libre de riesgo): {loSharpe:.2f}"

  let fullHtml = markowitzHtmlSection(tickers, urls, weights, loWeights, riskFreeRate, loCap,
    lookbackYears,
    (ret: portReturn, vol: portVolAnnual, sharpe: sharpe),
    (ret: loPortReturn, vol: loPortVolAnnual, sharpe: loSharpe))

  # --- Portafolio concentrado: re-optimiza sobre el top-N por momentum en vez
  # de simplemente recortar los pesos del portafolio de numAssets activos
  # (esos pesos asumen la diversificación de los numAssets activos completos;
  # con menos nombres la covarianza relevante es otra). La submatriz de cov
  # para ese subconjunto sigue siendo válida porque la EWMA se calcula por
  # par de activos, así que no hace falta descargar ni recalcular nada.
  var concentratedHtml = ""
  if numAssets >= finalN:
    let cap = max(finalPortfolioCap, 1.0 / finalN.float)
    let subCov = subMatrix(cov, finalN)
    let subMuExcess = muExcess[0 ..< finalN]
    let subTickers = tickers[0 ..< finalN]
    let subUrls = urls[0 ..< finalN]
    let subMu = muByTicker[0 ..< finalN]

    let concWeights = optimizeLongOnlyCapped(subMuExcess, subCov, cap)
    let concStats = portfolioStats(concWeights, subMu, subCov, riskFreeRate)

    echo ""
    echo fmt"--- Portafolio concentrado: top {finalN} por momentum, re-optimizado (tope {cap * 100:.0f}% por posición) ---"
    printWeights(subTickers, concWeights, -1.0)
    echo "-".repeat(24)
    echo fmt"Retorno esperado (proxy score momentum): {concStats.ret * 100:.2f}%"
    echo fmt"Volatilidad anualizada (cov. EWMA): {concStats.vol * 100:.2f}%"
    echo fmt"Sharpe (vs. tasa libre de riesgo): {concStats.sharpe:.2f}"

    concentratedHtml = concentratedHtmlSection(subTickers, subUrls, concWeights, concStats, cap, loCap, numAssets)
  else:
    logError(fmt"No hay suficientes activos ({numAssets}) para armar el portafolio concentrado de {finalN}.")

  fullHtml & concentratedHtml
