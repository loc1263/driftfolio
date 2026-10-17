## Orquesta el ranking de momentum para un universo de tickers: descarga,
## cálculo, orden por score y tabla por consola.
##
## Las descargas se despachan en pipeline (M-009): se lanza una petición
## nueva cada `DispatchIntervalMs` (el mismo ritmo que antes tenía el
## `sleep(200)` secuencial, para no cambiarle el comportamiento a Yahoo
## Finance) pero sin esperar a que cada una termine antes de lanzar la
## siguiente, así las respuestas se superponen en vez de sumarse en serie.
## Los aciertos de caché (M-010) no consumen ese ritmo de despacho.

import std/[asyncdispatch, algorithm, strformat, strutils, sequtils]
import ./types, ./analytics, ./marketdata, ./display

const DispatchIntervalMs = 200

proc processUniverse*(name: string, tickers: seq[string]): Future[seq[Quote]] {.async.} =
  ## `tickers` es `seq[string]` (no `openArray`) porque esta proc es async:
  ## el cuerpo se compila como una closure que puede sobrevivir a un `await`,
  ## y un `openArray` (puntero + largo, sin dueño) no es seguro de capturar ahí.
  echo "\n", "=".repeat(95)
  echo "RANKING DE MOMENTUM - ", name
  echo "Columna >SMA50 es informativa (no excluye activos)"
  echo "=".repeat(95)

  if tickers.len == 0:
    echo "(universo vacío, se omite)"
    return @[]

  var futs = newSeq[Future[seq[float]]](tickers.len)
  var completed = 0
  for idx, ticker in tickers:
    let justFinished = ticker  # copia propia de esta iteración para el callback
    let wasAlreadyCached = isPriceCached(ticker, 365)
    futs[idx] = fetchPrices(ticker)
    futs[idx].addCallback proc() =
      # La barra avanza con la descarga que realmente termina, no con el
      # orden de despacho: si no, al ya estar todas en vuelo por el pipeline,
      # el segundo loop (que solo *espera* en orden) las recorre casi
      # instantáneo y la barra salta de 0% a 100% sin reflejar la espera real.
      inc completed
      printProgress(completed, tickers.len, justFinished)
    if idx < tickers.len - 1 and not wasAlreadyCached:
      await sleepAsync(DispatchIntervalMs)

  var results: seq[Quote]
  for idx, ticker in tickers:
    let prices = await futs[idx]
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
