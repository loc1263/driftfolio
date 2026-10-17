## Markowitz: mejor portafolio sobre el top-N momentum (mega-cap)
##
## mu  = retorno esperado, proxy = score de momentum (ventana corta, régimen reciente)
## cov = covarianza EWMA sobre 5 años de retornos diarios (RiskMetrics, lambda=0.94),
##       da más peso a los datos recientes sin descartar la historia larga

import std/[httpclient, strformat, strutils, sequtils, math, os]
import ./types, ./linalg, ./marketdata, ./display, ./htmlreport, ./errorlog

const
  MarkowitzTopN* = 15
  MarkowitzLookbackYears* = 5
  EwmaLambda = 0.94
  MaxWeightPerAsset = 0.20
  # Portafolio concentrado: re-optimiza sobre los N activos de mayor momentum
  # (no es un recorte de los pesos del portafolio de MarkowitzTopN activos,
  # ver nota en runMarkowitz) con un tope por posición más holgado.
  MarkowitzFinalN = 4
  FinalPortfolioCap = 0.40

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

proc runMarkowitz*(client: HttpClient, topQuotes: seq[Quote]): string =
  echo "\n", "=".repeat(95)
  echo "MARKOWITZ - MEJOR PORTAFOLIO (top ", topQuotes.len, " por momentum, covarianza EWMA ", MarkowitzLookbackYears, " años)"
  echo "=".repeat(95)

  let riskFreeRate = fetchRiskFreeRate(client)
  echo fmt"Tasa libre de riesgo (^IRX, 13 semanas): {riskFreeRate * 100:.2f}%"

  var priceSeries: seq[seq[float]]
  var tickers: seq[string]
  var urls: seq[string]
  var muByTicker: seq[float]

  for q in topQuotes:
    echo "Descargando histórico de ", MarkowitzLookbackYears, " años: ", q.ticker
    let prices = fetchPrices(client, q.ticker, 365 * MarkowitzLookbackYears)
    sleep(200)
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

  let cov = ewmaCovariance(returnsMatrix, EwmaLambda)

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
  printWeights(tickers, weights)

  let (portReturn, portVolAnnual, sharpe) = portfolioStats(weights, muByTicker, cov, riskFreeRate)

  echo "-".repeat(24)
  echo fmt"Retorno esperado (proxy score momentum): {portReturn * 100:.2f}%"
  echo fmt"Volatilidad anualizada (cov. EWMA): {portVolAnnual * 100:.2f}%"
  echo fmt"Sharpe (vs. tasa libre de riesgo): {sharpe:.2f}"
  echo "Nota: pesos negativos implican posición corto, no ejecutable en un bróker normal."

  # --- Long-only con tope por posición (ejecutable en un bróker normal) ---
  let loWeights = optimizeLongOnlyCapped(muExcess, cov, MaxWeightPerAsset)

  echo ""
  echo fmt"--- Long-only, tope {MaxWeightPerAsset * 100:.0f}% por posición (ejecutable en un bróker normal) ---"
  printWeights(tickers, loWeights, 0.0001)

  let (loPortReturn, loPortVolAnnual, loSharpe) = portfolioStats(loWeights, muByTicker, cov, riskFreeRate)

  echo "-".repeat(24)
  echo fmt"Retorno esperado (proxy score momentum): {loPortReturn * 100:.2f}%"
  echo fmt"Volatilidad anualizada (cov. EWMA): {loPortVolAnnual * 100:.2f}%"
  echo fmt"Sharpe (vs. tasa libre de riesgo): {loSharpe:.2f}"

  let fullHtml = markowitzHtmlSection(tickers, urls, weights, loWeights, riskFreeRate, MaxWeightPerAsset,
    MarkowitzLookbackYears,
    (ret: portReturn, vol: portVolAnnual, sharpe: sharpe),
    (ret: loPortReturn, vol: loPortVolAnnual, sharpe: loSharpe))

  # --- Portafolio concentrado: re-optimiza sobre el top-N por momentum en vez
  # de simplemente recortar los pesos del portafolio de numAssets activos
  # (esos pesos asumen la diversificación de los numAssets activos completos;
  # con menos nombres la covarianza relevante es otra). La submatriz de cov
  # para ese subconjunto sigue siendo válida porque la EWMA se calcula por
  # par de activos, así que no hace falta descargar ni recalcular nada.
  var concentratedHtml = ""
  if numAssets >= MarkowitzFinalN:
    let cap = max(FinalPortfolioCap, 1.0 / MarkowitzFinalN.float)
    let subCov = subMatrix(cov, MarkowitzFinalN)
    let subMuExcess = muExcess[0 ..< MarkowitzFinalN]
    let subTickers = tickers[0 ..< MarkowitzFinalN]
    let subUrls = urls[0 ..< MarkowitzFinalN]
    let subMu = muByTicker[0 ..< MarkowitzFinalN]

    let concWeights = optimizeLongOnlyCapped(subMuExcess, subCov, cap)
    let concStats = portfolioStats(concWeights, subMu, subCov, riskFreeRate)

    echo ""
    echo fmt"--- Portafolio concentrado: top {MarkowitzFinalN} por momentum, re-optimizado (tope {cap * 100:.0f}% por posición) ---"
    printWeights(subTickers, concWeights, -1.0)
    echo "-".repeat(24)
    echo fmt"Retorno esperado (proxy score momentum): {concStats.ret * 100:.2f}%"
    echo fmt"Volatilidad anualizada (cov. EWMA): {concStats.vol * 100:.2f}%"
    echo fmt"Sharpe (vs. tasa libre de riesgo): {concStats.sharpe:.2f}"

    concentratedHtml = concentratedHtmlSection(subTickers, subUrls, concWeights, concStats, cap, MaxWeightPerAsset, numAssets)
  else:
    logError(fmt"No hay suficientes activos ({numAssets}) para armar el portafolio concentrado de {MarkowitzFinalN}.")

  fullHtml & concentratedHtml
