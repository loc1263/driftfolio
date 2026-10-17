import std/[times, httpclient]
import driftfolio/[types, universes, marketdata, ranking, csvexport, htmlreport, markowitz, errorlog]

proc main() =
  echo "Descargando y calculando momentum + filtro de media móvil (Nim)..."
  echo "Fecha: ", now().format("yyyy-MM-dd HH:mm")

  var allResults: seq[tuple[universo: string, q: Quote]]
  var htmlSections: seq[string]

  # Un solo cliente HTTP reutilizado (keep-alive) para todas las descargas:
  # evita repetir el handshake TCP/TLS en cada una de las ~160 peticiones.
  let client = newHttpClient(userAgent = "Mozilla/5.0")
  defer: client.close()

  let chileanResults = processUniverse(client, "ACCIONES CHILENAS (IPSA)", ChileanTickers)
  for q in chileanResults:
    allResults.add((universo: "ACCIONES CHILENAS (IPSA)", q: q))
  htmlSections.add(universeHtmlSection("ACCIONES CHILENAS (IPSA)", chileanResults, "chart-chile"))

  let vanguardResults = processUniverse(client, "ETFs VANGUARD", VanguardETFs)
  for q in vanguardResults:
    allResults.add((universo: "ETFs VANGUARD", q: q))
  htmlSections.add(universeHtmlSection("ETFs VANGUARD", vanguardResults, "chart-vanguard"))

  let megaCapTickers = fetchMegaCapTickers(client)
  if megaCapTickers.len > 0:
    let megaResults = processUniverse(client, "MEGA-CAP EEUU", megaCapTickers)
    for q in megaResults:
      allResults.add((universo: "MEGA-CAP EEUU", q: q))
    htmlSections.add(universeHtmlSection("MEGA-CAP EEUU", megaResults, "chart-megacap"))

    let topN = megaResults[0 ..< min(MarkowitzTopN, megaResults.len)]
    let markowitzHtml = runMarkowitz(client, topN)
    if markowitzHtml.len > 0:
      htmlSections.add(markowitzHtml)
  else:
    logError("No se pudo obtener el listado de mega-cap EEUU; se omite ese universo.")

  echo "\nScore = 20% × Retorno 1M + 40% × Retorno 3M + 40% × Retorno 6M"
  echo ">SMA50: Sí si el precio actual > SMA de 50 días (solo informativo)"

  exportCsv("driftfolio_resultados.csv", allResults)
  writeHtmlReport("driftfolio_resultados.html", now().format("yyyy-MM-dd HH:mm"), htmlSections)

when isMainModule:
  main()
