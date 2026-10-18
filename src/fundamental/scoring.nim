## Calculo del score fundamental.
##
## Cada metrica se normaliza en un z-score: idealmente comparando la empresa
## solo contra su propio sector (assetProfile.sector de Yahoo), porque
## comparar deuda/patrimonio o razon corriente de un banco contra una
## forestal no tiene sentido. Si el sector tiene muy pocas empresas con el
## dato disponible, se usa como respaldo el z-score contra todo el universo
## IPSA descargado.
##
## Los z-scores se "winsorizan" (se acotan a +-3) antes de ponderarlos: a
## veces Yahoo entrega datos financieros de empresas chilenas en una unidad
## o moneda inconsistente con el precio de mercado (p.ej. EBITDA o bookValue
## mal escalados para algunos tickers), lo que genera outliers extremos que
## de otro modo dominarian el score de esa empresa.

import std/[options, math, sequtils, tables]
import yahoofinance

type
  Direction* = enum
    higherIsBetter, lowerIsBetter

  MetricSpec = object
    name: string
    weight: float
    direction: Direction
    getter: proc(c: CompanyRaw): Option[float] {.closure.}

  ScoredCompany* = object
    raw*: CompanyRaw
    rawScore*: float      # promedio ponderado de z-scores winsorizados (sin reescalar)
    score*: float          # reescalado a 0-100
    metricsUsed*: int
    sectorMetricsUsed*: int  # cuantas de esas metricas usaron stats del sector (vs. global)

const
  MinSectorSample = 3   ## minimo de empresas con dato valido en el sector para confiar en sus stats
  ZClip = 3.0            ## winsorizacion: tope de desviaciones estandar por metrica
  UnknownSector = "(sin sector)"

let metricSpecs: seq[MetricSpec] = @[
  MetricSpec(name: "P/E",         weight: 1.0, direction: lowerIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.trailingPE),
  MetricSpec(name: "P/B",         weight: 1.0, direction: lowerIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.priceToBook),
  MetricSpec(name: "EV/EBITDA",   weight: 1.2, direction: lowerIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.evToEbitda),
  MetricSpec(name: "PEG",         weight: 1.0, direction: lowerIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.pegRatio),
  MetricSpec(name: "ROE",         weight: 1.5, direction: higherIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.returnOnEquity),
  MetricSpec(name: "ROA",         weight: 1.0, direction: higherIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.returnOnAssets),
  MetricSpec(name: "Margen neto", weight: 1.0, direction: higherIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.profitMargins),
  MetricSpec(name: "Margen oper.", weight: 0.8, direction: higherIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.operatingMargins),
  MetricSpec(name: "Deuda/Patrim.", weight: 1.0, direction: lowerIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.debtToEquity),
  MetricSpec(name: "Razon corriente", weight: 0.8, direction: higherIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.currentRatio),
  MetricSpec(name: "Crec. ingresos", weight: 1.0, direction: higherIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.revenueGrowth),
  MetricSpec(name: "Crec. utilidades", weight: 1.0, direction: higherIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.earningsGrowth),
  MetricSpec(name: "Div. yield",   weight: 1.0, direction: higherIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.dividendYield),
  MetricSpec(name: "FCF yield",    weight: 1.2, direction: higherIsBetter,
             getter: proc(c: CompanyRaw): Option[float] = c.fcfYield),
]

type Stats = tuple[mean, std: float, n: int]

proc meanStd(values: seq[float]): Stats =
  let n = values.len
  if n == 0:
    return (0.0, 0.0, 0)
  var s = 0.0
  for v in values: s += v
  let m = s / n.float
  var ss = 0.0
  for v in values: ss += (v - m) * (v - m)
  let variance = if n > 1: ss / (n - 1).float else: 0.0
  (m, sqrt(variance), n)

proc sectorOf(c: CompanyRaw): string =
  if c.sector.len > 0: c.sector else: UnknownSector

proc computeScores*(companies: seq[CompanyRaw]): seq[ScoredCompany] =
  let valid = companies.filterIt(it.fetchError.len == 0)

  # Stats globales (todo el universo) por metrica, usadas como respaldo.
  var globalStats: seq[Stats] = @[]
  for spec in metricSpecs:
    globalStats.add(meanStd(valid.mapIt(spec.getter(it)).filterIt(it.isSome).mapIt(it.get())))

  # Stats por sector y por metrica. Solo se usan si hay >= MinSectorSample
  # empresas con dato disponible en ese sector para esa metrica en particular.
  var sectors: seq[string] = @[]
  for c in valid:
    let s = sectorOf(c)
    if s notin sectors: sectors.add(s)

  var sectorStats = initTable[string, seq[Stats]]()
  for s in sectors:
    let companiesInSector = valid.filterIt(sectorOf(it) == s)
    var statsForSector: seq[Stats] = @[]
    for spec in metricSpecs:
      let vals = companiesInSector.mapIt(spec.getter(it)).filterIt(it.isSome).mapIt(it.get())
      statsForSector.add(meanStd(vals))
    sectorStats[s] = statsForSector

  result = @[]
  for c in companies:
    var sc = ScoredCompany(raw: c)
    if c.fetchError.len > 0:
      sc.rawScore = NaN
      sc.score = NaN
      result.add(sc)
      continue

    let s = sectorOf(c)
    var weightedSum = 0.0
    var weightTotal = 0.0
    var used = 0
    var usedSector = 0
    for i, spec in metricSpecs:
      let v = spec.getter(c)
      if v.isNone: continue

      var mean, std: float
      var usingSector = false
      let secStats = sectorStats[s][i]
      if secStats.n >= MinSectorSample and secStats.std > 0.0:
        mean = secStats.mean
        std = secStats.std
        usingSector = true
      elif globalStats[i].std > 0.0:
        mean = globalStats[i].mean
        std = globalStats[i].std
      else:
        continue  # sin variacion en ningun lado: la metrica no aporta informacion

      var z = (v.get() - mean) / std
      if spec.direction == lowerIsBetter: z = -z
      z = clamp(z, -ZClip, ZClip)  # winsorizacion: evita que un dato mal escalado domine el score

      weightedSum += spec.weight * z
      weightTotal += spec.weight
      inc used
      if usingSector: inc usedSector

    sc.rawScore = if weightTotal > 0.0: weightedSum / weightTotal else: 0.0
    sc.metricsUsed = used
    sc.sectorMetricsUsed = usedSector
    result.add(sc)

  # Reescalamos rawScore (acotado aprox a +-ZClip) a un rango 0-100 usando
  # min-max sobre el universo valido, para que el score final sea intuitivo.
  let rawScores = result.filterIt(it.raw.fetchError.len == 0).mapIt(it.rawScore)
  if rawScores.len > 0:
    let lo = rawScores.min()
    let hi = rawScores.max()
    let span = hi - lo
    for sc in result.mitems:
      if sc.raw.fetchError.len > 0:
        continue
      if span <= 0.0:
        sc.score = 50.0
      else:
        sc.score = (sc.rawScore - lo) / span * 100.0

proc metricNames*(): seq[string] =
  result = @[]
  for spec in metricSpecs: result.add(spec.name)
