## Orquesta el ranking de momentum para un universo de tickers: descarga,
## cálculo, orden por score y tabla por consola.

import std/[httpclient, algorithm, strformat, strutils, sequtils, os]
import ./types, ./analytics, ./marketdata, ./display

proc processUniverse*(client: HttpClient, name: string, tickers: openArray[string]): seq[Quote] =
  echo "\n", "=".repeat(95)
  echo "RANKING DE MOMENTUM - ", name
  echo "Columna >SMA50 es informativa (no excluye activos)"
  echo "=".repeat(95)

  var results: seq[Quote]

  for idx, ticker in tickers:
    printProgress(idx + 1, tickers.len, ticker)
    let prices = fetchPrices(client, ticker)
    sleep(200)  # evita rate-limiting de Yahoo Finance al consultar muchos tickers seguidos
    if prices.len < MinHistoryDays:
      continue

    let cleanTicker = ticker.replace(".SN", "")
    results.add(buildQuote(cleanTicker, stockAnalysisUrl(ticker), prices))

  clearProgress()

  # Ordenar por score descendente
  results.sort(proc (a, b: Quote): int =
    cmp(b.score, a.score)
  )

  # Imprimir tabla
  echo fmt"""{"#":<4} {"Ticker":<12} {"1M %":>8} {"3M %":>8} {"6M %":>8} {"Score":>9} {"Precio":>9} {"SMA50":>9} {">SMA50":>8}"""
  echo "-".repeat(95)

  for i, q in results:
    stdout.write fmt"{i+1:<4} {q.ticker:<12} "
    writeColored(q.ret1m, 8)
    stdout.write " "
    writeColored(q.ret3m, 8)
    stdout.write " "
    writeColored(q.ret6m, 8)
    stdout.write " "
    writeColored(q.score, 9)
    stdout.write fmt" {q.price:>9.2f} {q.sma50:>9.2f} "
    writeAboveStr(q.aboveSma50, 8)
    echo ""

  echo "=".repeat(95)
  echo "Total de activos: ", results.len, " | Sobre SMA50: ", results.countIt(it.aboveSma50)

  result = results
