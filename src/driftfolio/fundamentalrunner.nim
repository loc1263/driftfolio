## Orquesta el análisis fundamental del IPSA (Chile) y de las mega-caps de
## EE.UU. con datos de Yahoo Finance, como parte de la misma corrida de
## driftfolio (ver src/driftfolio.nim).
##
## Para cada empresa calcula PE, PB, EV/EBITDA, PEG, ROE, ROA, margenes,
## deuda, liquidez, crecimiento, dividend yield, FCF yield y upside de precio
## objetivo de analistas (este ultimo solo informativo); el score pondera
## z-scores comparados primero contra el propio sector de la empresa (con
## respaldo global si el sector tiene pocos datos) y winsorizados,
## reescalados a 0-100.
##
## Es un flujo independiente del ranking de momentum (fuente de datos y
## métricas distintas): genera su propio reporte HTML
## (analisis_fundamental_resultados.html) y sus propios CSV, separados de
## los de driftfolio. index.html enlaza ambos reportes desde una sola
## página.

import std/[strutils, strformat, algorithm, sequtils, options, times, os]
import ../fundamental/[tickers, yahoofinance, scoring, htmlreport]

proc fmtPct(v: Option[float]): string =
  if v.isNone: return "  n/d"
  &"{v.get() * 100.0:6.2f}%"

proc fmtNum(v: Option[float]): string =
  if v.isNone: return "  n/d"
  &"{v.get():6.2f}"

proc fmtInt(v: Option[float]): string =
  if v.isNone: return "n/d"
  $(v.get().int)

proc fmtRecommendation(key: string): string =
  case key
  of "strong_buy": "Strong Buy"
  of "buy": "Buy"
  of "hold": "Hold"
  of "underperform": "Underperform"
  of "sell": "Sell"
  else: "n/d"

proc writeCsv(path: string, scored: seq[ScoredCompany]) =
  var lines: seq[string] = @[]
  lines.add("rank,ticker,nombre,sector,industria,score,metricas_usadas,metricas_sector,pe,pb,ev_ebitda,peg,roe,roa,margen_neto,margen_oper,deuda_patrimonio,razon_corriente,crec_ingresos,crec_utilidades,div_yield,fcf_yield,target_mean_price,target_upside,recomendacion_mean,recomendacion,num_analistas,market_cap,moneda,error")
  var rank = 0
  for sc in scored:
    if sc.raw.fetchError.len == 0:
      inc rank
    let r = sc.raw
    proc f(v: Option[float]): string = (if v.isSome: formatFloat(v.get(), ffDecimal, 6) else: "")
    let line = [
      (if sc.raw.fetchError.len == 0: $rank else: ""),
      r.ticker,
      "\"" & r.name.replace("\"", "'") & "\"",
      "\"" & r.sector.replace("\"", "'") & "\"",
      "\"" & r.industry.replace("\"", "'") & "\"",
      (if sc.raw.fetchError.len == 0: formatFloat(sc.score, ffDecimal, 2) else: ""),
      (if sc.raw.fetchError.len == 0: $sc.metricsUsed else: ""),
      (if sc.raw.fetchError.len == 0: $sc.sectorMetricsUsed else: ""),
      f(r.trailingPE), f(r.priceToBook), f(r.evToEbitda), f(r.pegRatio), f(r.returnOnEquity), f(r.returnOnAssets),
      f(r.profitMargins), f(r.operatingMargins), f(r.debtToEquity), f(r.currentRatio),
      f(r.revenueGrowth), f(r.earningsGrowth), f(r.dividendYield), f(r.fcfYield),
      f(r.targetMeanPrice), f(r.targetUpside), f(r.recommendationMean),
      "\"" & r.recommendationKey.replace("\"", "'") & "\"", f(r.numberOfAnalystOpinions),
      f(r.marketCap), r.currency,
      "\"" & r.fetchError.replace("\"", "'") & "\""
    ].join(",")
    lines.add(line)
  writeFile(path, lines.join("\n") & "\n")

type UniverseResult = object
  label: string
  slug: string
  tickerCount: int
  ok, noData, failed: seq[ScoredCompany]

proc runUniverse(label, slug: string, tickerList: seq[string], session: YahooSession,
                  maxConcurrent: int): UniverseResult =
  echo &"Descargando datos fundamentales de {tickerList.len} empresas ({label}) desde Yahoo Finance...\n"

  let raw = fetchAll(session, tickerList, maxConcurrent)
  let scored = computeScores(raw)

  var ok = scored.filterIt(it.raw.fetchError.len == 0 and it.metricsUsed > 0)
  let noData = scored.filterIt(it.raw.fetchError.len == 0 and it.metricsUsed == 0)
  let failed = scored.filterIt(it.raw.fetchError.len > 0)
  ok.sort(proc(a, b: ScoredCompany): int = cmp(b.score, a.score))

  echo ""
  echo "=".repeat(148)
  echo &"RANKING FUNDAMENTAL - {label}  ({ok.len} empresas con datos validos de {tickerList.len} consultadas)"
  echo "=".repeat(148)
  echo &"{\"#\":>3} {\"Ticker\":<12} {\"Sector\":<16} {\"Score\":>6} {\"P/E\":>7} {\"PEG\":>6} {\"EV/EBITDA\":>10} {\"ROE\":>8} {\"FCF.Yield\":>10} {\"Div.Yield\":>10} {\"An.Upside\":>10} {\"Recom.\":>11} {\"N.Analist\":>9} {\"Metricas\":>9}"
  echo "-".repeat(148)

  for i, sc in ok:
    let r = sc.raw
    let sectorShown = if r.sector.len == 0: "(sin sector)"
                       elif r.sector.len > 16: r.sector[0..15]
                       else: r.sector
    let metricasShown = &"{sc.sectorMetricsUsed}/{sc.metricsUsed}"
    echo &"{i+1:>3} {r.ticker:<12} {sectorShown:<16} {sc.score:>6.1f} {fmtNum(r.trailingPE):>7} {fmtNum(r.pegRatio):>6} {fmtNum(r.evToEbitda):>10} {fmtPct(r.returnOnEquity):>8} {fmtPct(r.fcfYield):>10} {fmtPct(r.dividendYield):>10} {fmtPct(r.targetUpside):>10} {fmtRecommendation(r.recommendationKey):>11} {fmtInt(r.numberOfAnalystOpinions):>9} {metricasShown:>9}"

  if noData.len > 0:
    echo ""
    echo "Empresas descargadas pero sin metricas utilizables (Yahoo no entrega esos modulos para este ticker):"
    for sc in noData:
      echo &"  - {sc.raw.ticker}"

  if failed.len > 0:
    echo ""
    echo "Empresas sin datos (error de descarga o ticker invalido):"
    for sc in failed:
      echo &"  - {sc.raw.ticker}: {sc.raw.fetchError}"

  UniverseResult(label: label, slug: slug, tickerCount: tickerList.len, ok: ok, noData: noData, failed: failed)

proc printNote() =
  echo ""
  echo "Nota: el score pondera z-scores de PE, PB, EV/EBITDA, PEG, ROE, ROA,"
  echo "margenes, deuda/patrimonio, razon corriente, crecimiento de ingresos/"
  echo "utilidades, dividend yield y FCF yield. Cada metrica se compara primero"
  echo "contra el propio sector de la empresa (columna 'Metricas' = usadas con"
  echo "stats de sector / total usadas); si el sector tiene pocos datos, se usa"
  echo "como respaldo el universo completo descargado. Los z-scores se acotan a"
  echo "+-3 para que un dato de Yahoo mal escalado (ocurre con EV/EBITDA y P/B"
  echo "en algunos tickers, sobre todo chilenos) no domine el resultado. El PEG"
  echo "solo se calcula con crecimiento de utilidades positivo (si no, 'n/d')."
  echo "La columna 'An.Upside' (precio objetivo promedio de analistas vs precio"
  echo "actual) es solo informativa y NO entra al score: el consenso sell-side"
  echo "tiende a sesgo alcista estructural, asi que no se trata como fundamento."
  echo "El score de un universo NO es comparable con el de otro universo:"
  echo "cada ranking es relativo solo a las empresas de su propia lista."
  echo "No es una recomendacion de inversion."

proc runFundamentalAnalysis*(outDir: string, maxConcurrent: int = 8) =
  echo ""
  echo "Descargando y calculando analisis fundamental (IPSA + mega-caps EE.UU.)..."

  let session = newYahooSession()
  if session.crumb.len == 0:
    stderr.writeLine("ADVERTENCIA: no se obtuvo 'crumb' de Yahoo; las consultas fundamentales probablemente fallaran.")

  var results: seq[UniverseResult] = @[]
  results.add(runUniverse("IPSA (Chile)", "ipsa", DefaultIpsaTickers, session, maxConcurrent))
  results.add(runUniverse("mega-caps EE.UU.", "us", DefaultUsMegaCapTickers, session, maxConcurrent))

  printNote()

  var sections: seq[tuple[label: string, html: string]] = @[]
  for r in results:
    writeCsv(outDir / ("analisis_fundamental_" & r.slug & ".csv"), r.ok & r.noData & r.failed)
    sections.add((r.label, buildUniverseSection(r.label, r.ok, r.noData, r.failed, r.tickerCount)))

  let reportPath = outDir / "analisis_fundamental_resultados.html"
  writeReport(reportPath, "IPSA + Mega-caps EE.UU.", now().format("yyyy-MM-dd HH:mm"), sections)

  echo ""
  echo &"Reporte HTML: {reportPath}"
  for r in results:
    echo &"CSV {r.label}: ", outDir / ("analisis_fundamental_" & r.slug & ".csv")
