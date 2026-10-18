## Cálculos de momentum: retornos, media móvil y el score compuesto.
## Son funciones puras (sin I/O) para poder testearlas de forma aislada.

import ./types
import ./config

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

proc momentumScore*(ret1m, ret3m, ret6m: float,
                     w1 = DefaultConfig.ret1mWeight,
                     w3 = DefaultConfig.ret3mWeight,
                     w6 = DefaultConfig.ret6mWeight): float =
  w1 * ret1m + w3 * ret3m + w6 * ret6m

proc buildQuote*(ticker, url: string, prices: seq[float], cfg: Config = DefaultConfig): Quote =
  ## Requiere `prices.len >= cfg.minHistoryDays` (responsabilidad del llamador).
  let
    r1 = calcReturn(prices, cfg.ret1mDays)
    r3 = calcReturn(prices, cfg.ret3mDays)
    r6 = calcReturn(prices, cfg.ret6mDays)
    sma = calcSMA(prices, cfg.smaPeriod)
    price = prices[^1]
    score = momentumScore(r1, r3, r6, cfg.ret1mWeight, cfg.ret3mWeight, cfg.ret6mWeight)

  Quote(
    ticker: ticker,
    url: url,
    ret1m: r1,
    ret3m: r3,
    ret6m: r6,
    score: score,
    price: price,
    sma50: sma,
    aboveSma50: price > sma
  )
