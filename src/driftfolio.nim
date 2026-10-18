import std/[times, asyncdispatch, os, strformat]
import driftfolio/[types, universes, marketdata, ranking, csvexport, htmlreport, markowitz, errorlog, config, fundamentalrunner, indexreport]

proc asyncMain(cfg: Config, outDir: string) {.async.} =
  echo "Descargando y calculando momentum + filtro de media móvil (Nim)..."
  echo "Fecha: ", now().format("yyyy-MM-dd HH:mm")

  try:
    var allResults: seq[tuple[universo: string, q: Quote]]
    var htmlSections: seq[tuple[label: string, html: string]]

    let (chileTickers, vanguardTickers) = loadUniverses()

    if cfg.runChile:
      let chileanResults = await processUniverse("ACCIONES CHILENAS (IPSA)", chileTickers, cfg)
      for q in chileanResults:
        allResults.add((universo: "ACCIONES CHILENAS (IPSA)", q: q))
      htmlSections.add((label: "ACCIONES CHILENAS (IPSA)",
        html: universeHtmlSection("ACCIONES CHILENAS (IPSA)", chileanResults, "chart-chile")))

    if cfg.runVanguard:
      let vanguardResults = await processUniverse("ETFs VANGUARD", vanguardTickers, cfg)
      for q in vanguardResults:
        allResults.add((universo: "ETFs VANGUARD", q: q))
      htmlSections.add((label: "ETFs VANGUARD",
        html: universeHtmlSection("ETFs VANGUARD", vanguardResults, "chart-vanguard")))

    if cfg.runMegaCap:
      let megaCapTickers = await fetchMegaCapTickers()
      if megaCapTickers.len > 0:
        let megaResults = await processUniverse("MEGA-CAP EEUU", megaCapTickers, cfg)
        for q in megaResults:
          allResults.add((universo: "MEGA-CAP EEUU", q: q))
        htmlSections.add((label: "MEGA-CAP EEUU",
          html: universeHtmlSection("MEGA-CAP EEUU", megaResults, "chart-megacap")))

        let topN = megaResults[0 ..< min(cfg.markowitzTopN, megaResults.len)]
        let markowitzHtml = await runMarkowitz(topN, cfg.markowitzLookbackYears, cfg.ewmaLambda,
          cfg.maxWeightPerAsset, cfg.markowitzFinalN, cfg.finalPortfolioCap)
        if markowitzHtml.len > 0:
          htmlSections.add((label: "Markowitz", html: markowitzHtml))
      else:
        logError("No se pudo obtener el listado de mega-cap EEUU; se omite ese universo.")

    # fmt"\n..." no interpreta el \n como salto de línea (a diferencia de un
    # string normal): se imprime aparte.
    echo ""
    echo fmt"Score = {(cfg.ret1mWeight * 100).int}% × Retorno 1M + {(cfg.ret3mWeight * 100).int}% × Retorno 3M + {(cfg.ret6mWeight * 100).int}% × Retorno 6M"
    echo fmt">SMA{cfg.smaPeriod}: Sí si el precio actual > SMA de {cfg.smaPeriod} días (solo informativo)"

    exportCsv(outDir / "driftfolio_resultados.csv", allResults)
    writeHtmlReport(outDir / "driftfolio_resultados.html", now().format("yyyy-MM-dd HH:mm"), htmlSections)
  finally:
    flushErrorLog()

proc printUsage() =
  echo "Uso: driftfolio [opción]"
  echo ""
  echo "  (sin opciones)   Corre el ranking de momentum + portafolio Markowitz."
  echo "  --no-cache       Ignora el caché de precios del día (.driftfolio_cache/) y"
  echo "                   vuelve a descargar todo desde Yahoo Finance. El análisis"
  echo "                   fundamental siempre descarga de nuevo: no tiene caché."
  echo "  --reset-config   Escribe/sobrescribe ", ConfigFile, " con los parámetros de fábrica y termina."
  echo "  --help, -h       Muestra esta ayuda y termina."
  echo ""
  echo "Los parámetros del modelo (pesos del score, ventanas de retorno, SMA,"
  echo "topN de Markowitz, etc.) se leen de ", ConfigFile, " si existe; si no,"
  echo "se usan los valores de fábrica embebidos en el binario."

when isMainModule:
  var noCache = false
  for i in 1 .. paramCount():
    case paramStr(i)
    of "--reset-config":
      writeDefaultConfig()
      echo "Se escribió ", ConfigFile, " con los parámetros de fábrica."
      quit(0)
    of "--help", "-h":
      printUsage()
      quit(0)
    of "--no-cache":
      noCache = true
    else:
      echo "Opción desconocida: ", paramStr(i)
      printUsage()
      quit(1)

  if noCache:
    marketdata.skipCache = true
    echo "--no-cache: ignorando el caché de precios de hoy, se vuelve a descargar todo."

  let stamp = now().format("yyyy-MM-dd'_'HH-mm-ss")
  let outDir = "output" / stamp
  createDir(outDir)

  waitFor asyncMain(loadConfig(), outDir)
  runFundamentalAnalysis(outDir)
  writeIndexHtml(outDir / "index.html", now().format("yyyy-MM-dd HH:mm"))

  echo ""
  echo "Salida guardada en: ", outDir
