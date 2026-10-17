## Cálculos de momentum: retornos, media móvil y el score compuesto.
## Son funciones puras (sin I/O) para poder testearlas de forma aislada.

import ./types

const
  MinHistoryDays* = 130 ## tickers con menos historia que esto se descartan (no hay 6M + SMA50)
  Return1MDays* = 21
  Return3MDays* = 63
  Return6MDays* = 126
  Sma50Period* = 50

  Return1MWeight* = 0.20
  Return3MWeight* = 0.40
  Return6MWeight* = 0.40

proc calcReturn*(prices: seq[float], days: int): float =
  if prices.len < days + 1:
    return 0.0
  let last = prices[^1]
  let past = prices[^(days + 1)]
  if past == 0:
    return 0.0
  (last / past - 1) * 100

proc calcSMA*(prices: seq[float], period: int): float =
  if prices.len < period:
    return 0.0
  var sum = 0.0
  for i in prices.len - period ..< prices.len:
    sum += prices[i]
  sum / period.float

proc momentumScore*(ret1m, ret3m, ret6m: float): float =
  Return1MWeight * ret1m + Return3MWeight * ret3m + Return6MWeight * ret6m

proc buildQuote*(ticker, url: string, prices: seq[float]): Quote =
  ## Requiere `prices.len >= MinHistoryDays` (responsabilidad del llamador).
  let
    r1 = calcReturn(prices, Return1MDays)
    r3 = calcReturn(prices, Return3MDays)
    r6 = calcReturn(prices, Return6MDays)
    sma50 = calcSMA(prices, Sma50Period)
    price = prices[^1]
    score = momentumScore(r1, r3, r6)

  Quote(
    ticker: ticker,
    url: url,
    ret1m: r1,
    ret3m: r3,
    ret6m: r6,
    score: score,
    price: price,
    sma50: sma50,
    aboveSma50: price > sma50
  )
