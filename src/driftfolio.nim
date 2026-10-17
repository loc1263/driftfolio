import std/[times, asyncdispatch]
import driftfolio/[types, universes, marketdata, ranking, csvexport, htmlreport, markowitz, errorlog]

proc asyncMain() {.async.} =
  echo "Descargando y calculando momentum + filtro de media móvil (Nim)..."
  echo "Fecha: ", now().format("yyyy-MM-dd HH:mm")

  try:
    var allResults: seq[tuple[universo: string, q: Quote]]
    var htmlSections: seq[string]

    let (chileTickers, vanguardTickers) = loadUniverses()

    let chileanResults = await processUniverse("ACCIONES CHILENAS (IPSA)", chileTickers)
    for q in chileanResults:
      allResults.add((universo: "ACCIONES CHILENAS (IPSA)", q: q))
    htmlSections.add(universeHtmlSection("ACCIONES CHILENAS (IPSA)", chileanResults, "chart-chile"))

    let vanguardResults = await processUniverse("ETFs VANGUARD", vanguardTickers)
    for q in vanguardResults:
      allResults.add((universo: "ETFs VANGUARD", q: q))
    htmlSections.add(universeHtmlSection("ETFs VANGUARD", vanguardResults, "chart-vanguard"))

    let megaCapTickers = await fetchMegaCapTickers()
    if megaCapTickers.len > 0:
      let megaResults = await processUniverse("MEGA-CAP EEUU", megaCapTickers)
      for q in megaResults:
        allResults.add((universo: "MEGA-CAP EEUU", q: q))
      htmlSections.add(universeHtmlSection("MEGA-CAP EEUU", megaResults, "chart-megacap"))

      let topN = megaResults[0 ..< min(MarkowitzTopN, megaResults.len)]
      let markowitzHtml = await runMarkowitz(topN)
      if markowitzHtml.len > 0:
        htmlSections.add(markowitzHtml)
    else:
      logError("No se pudo obtener el listado de mega-cap EEUU; se omite ese universo.")

    echo "\nScore = 20% × Retorno 1M + 40% × Retorno 3M + 40% × Retorno 6M"
    echo ">SMA50: Sí si el precio actual > SMA de 50 días (solo informativo)"

    exportCsv("driftfolio_resultados.csv", allResults)
    writeHtmlReport("driftfolio_resultados.html", now().format("yyyy-MM-dd HH:mm"), htmlSections)
  finally:
    flushErrorLog()

when isMainModule:
  waitFor asyncMain()
