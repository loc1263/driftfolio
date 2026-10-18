## Genera el reporte HTML del ranking fundamental.
##
## Cada ticker es un link que abre stockanalysis.com en una pestana nueva.
## El mapeo de ticker -> URL se basa en como esta armado nuestro propio
## ticker (ver tickers.nim):
##   - EE.UU. (sin sufijo, ej. "AAPL", "BRK-B")   -> stockanalysis.com/stocks/<ticker>/
##   - IPSA (sufijo ".SN", ej. "SQM-B.SN")        -> stockanalysis.com/quote/snse/<base>/
##     donde <base> es el ticker sin ".SN" y con "-" cambiado a "." (asi es
##     como stockanalysis.com nombra las clases de accion en la Bolsa de
##     Santiago, ej. "SQM-B.SN" -> "SQM.B"). Verificado contra su API de
##     busqueda (stockanalysis.com/api/search) el 2026-10-17.

import std/[strutils, strformat, options]
import yahoofinance, scoring
import ../theme

proc tickerUrl*(ticker: string): string =
  if ticker.endsWith(".SN"):
    let base = ticker[0 ..< ticker.len - 3].replace("-", ".")
    "https://stockanalysis.com/quote/snse/" & base & "/"
  else:
    "https://stockanalysis.com/stocks/" & ticker & "/"

proc escapeHtml(s: string): string =
  s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"))

proc fmtPctHtml(v: Option[float]): string =
  if v.isNone: return "&ndash;"
  &"{v.get() * 100.0:.2f}%"

proc fmtNumHtml(v: Option[float]): string =
  if v.isNone: return "&ndash;"
  &"{v.get():.2f}"

proc fmtIntHtml(v: Option[float]): string =
  if v.isNone: return "&ndash;"
  $(v.get().int)

proc fmtRecommendationHtml(key: string): string =
  case key
  of "strong_buy": "Strong Buy"
  of "buy": "Buy"
  of "hold": "Hold"
  of "underperform": "Underperform"
  of "sell": "Sell"
  else: "&ndash;"

proc recommendationBadgeHtml(key: string): string =
  case key
  of "strong_buy": """<span class="badge badge-buy">Strong Buy</span>"""
  of "buy": """<span class="badge badge-buy">Buy</span>"""
  of "hold": """<span class="badge badge-hold">Hold</span>"""
  of "underperform": """<span class="badge badge-sell">Underperform</span>"""
  of "sell": """<span class="badge badge-sell">Sell</span>"""
  else: """<span class="badge badge-na">&ndash;</span>"""

proc cellClass(v: Option[float]): string =
  ## Clase CSS para colorear positivo/negativo donde tiene sentido.
  if v.isNone: return "na"
  if v.get() > 0.0: "pos" elif v.get() < 0.0: "neg" else: ""

proc scoreBandClass(score: float): string =
  if score >= 70.0: "good" elif score >= 40.0: "mid" else: "low"

proc scoreCellHtml(score: float): string =
  let pct = clamp(score, 0.0, 100.0)
  let cls = scoreBandClass(score)
  &"""<div class="score-cell"><span class="score-num {cls}">{score:.1f}</span><span class="score-bar"><span class="score-bar-fill {cls}" style="width:{pct:.0f}%"></span></span></div>"""

proc rankCellHtml(rank: int): string =
  if rank <= 3:
    &"""<span class="rank-badge rank-{rank}">{rank}</span>"""
  else:
    $rank

proc buildTableRows(scored: seq[ScoredCompany]): string =
  var rows: seq[string] = @[]
  for i, sc in scored:
    let r = sc.raw
    let sectorShown = if r.sector.len == 0: "(sin sector)" else: r.sector
    let rowClass = if i < 3: " class=\"top3\"" else: ""
    rows.add(&"""
    <tr{rowClass}>
      <td class="num sticky-col col-rank">{rankCellHtml(i+1)}</td>
      <td class="sticky-col col-ticker"><a href="{tickerUrl(r.ticker)}" target="_blank" rel="noopener">{escapeHtml(r.ticker)}</a></td>
      <td>{escapeHtml(r.name)}</td>
      <td>{escapeHtml(sectorShown)}</td>
      <td class="num score">{scoreCellHtml(sc.score)}</td>
      <td class="num">{fmtNumHtml(r.trailingPE)}</td>
      <td class="num">{fmtNumHtml(r.pegRatio)}</td>
      <td class="num">{fmtNumHtml(r.evToEbitda)}</td>
      <td class="num {cellClass(r.returnOnEquity)}">{fmtPctHtml(r.returnOnEquity)}</td>
      <td class="num {cellClass(r.fcfYield)}">{fmtPctHtml(r.fcfYield)}</td>
      <td class="num {cellClass(r.dividendYield)}">{fmtPctHtml(r.dividendYield)}</td>
      <td class="num {cellClass(r.targetUpside)}">{fmtPctHtml(r.targetUpside)}</td>
      <td>{recommendationBadgeHtml(r.recommendationKey)}</td>
      <td class="num">{fmtIntHtml(r.numberOfAnalystOpinions)}</td>
      <td class="num muted">{sc.sectorMetricsUsed}/{sc.metricsUsed}</td>
    </tr>""")
  rows.join("\n")

proc buildIssuesList(title: string, items: seq[ScoredCompany], showError: bool): string =
  if items.len == 0: return ""
  var lis: seq[string] = @[]
  for sc in items:
    let extra = if showError: ": " & escapeHtml(sc.raw.fetchError) else: ""
    lis.add(&"""<li><a href="{tickerUrl(sc.raw.ticker)}" target="_blank" rel="noopener">{escapeHtml(sc.raw.ticker)}</a>{extra}</li>""")
  &"""
  <div class="issues">
    <h3>{escapeHtml(title)}</h3>
    <ul>
      {lis.join("\n      ")}
    </ul>
  </div>"""

proc buildKpiCards(ok: seq[ScoredCompany], totalConsulted: int): string =
  if ok.len == 0: return ""

  var sumScore = 0.0
  for sc in ok: sumScore += sc.score
  let avgScore = sumScore / ok.len.float

  var bestDiv = -1.0
  var bestDivTicker = ""
  var bestUpside = -1.0e18
  var bestUpsideTicker = ""
  for sc in ok:
    if sc.raw.dividendYield.isSome and sc.raw.dividendYield.get() > bestDiv:
      bestDiv = sc.raw.dividendYield.get()
      bestDivTicker = sc.raw.ticker
    if sc.raw.targetUpside.isSome and sc.raw.targetUpside.get() > bestUpside:
      bestUpside = sc.raw.targetUpside.get()
      bestUpsideTicker = sc.raw.ticker

  let top = ok[0]
  let divValue = if bestDivTicker.len > 0: &"{bestDiv * 100.0:.2f}%" else: "&ndash;"
  let divSub = if bestDivTicker.len > 0: escapeHtml(bestDivTicker) else: "sin datos"
  let upsideValue = if bestUpsideTicker.len > 0: &"{bestUpside * 100.0:.2f}%" else: "&ndash;"
  let upsideSub = if bestUpsideTicker.len > 0: escapeHtml(bestUpsideTicker) else: "sin datos"

  &"""
  <div class="kpi-row">
    <div class="kpi-card">
      <span class="kpi-label">Empresas con datos</span>
      <span class="kpi-value">{ok.len}<span class="kpi-sub"> / {totalConsulted}</span></span>
    </div>
    <div class="kpi-card">
      <span class="kpi-label">Score promedio</span>
      <span class="kpi-value">{avgScore:.1f}</span>
    </div>
    <div class="kpi-card">
      <span class="kpi-label">Top pick</span>
      <span class="kpi-value"><a href="{tickerUrl(top.raw.ticker)}" target="_blank" rel="noopener">{escapeHtml(top.raw.ticker)}</a></span>
      <span class="kpi-sub">score {top.score:.1f}</span>
    </div>
    <div class="kpi-card">
      <span class="kpi-label">Mejor div. yield</span>
      <span class="kpi-value">{divValue}</span>
      <span class="kpi-sub">{divSub}</span>
    </div>
    <div class="kpi-card">
      <span class="kpi-label">Mayor upside analistas</span>
      <span class="kpi-value">{upsideValue}</span>
      <span class="kpi-sub">{upsideSub}</span>
    </div>
  </div>"""

proc buildUniverseSection*(label: string, ok, noData, failed: seq[ScoredCompany], totalConsulted: int): string =
  &"""
  <section>
    <h2>{escapeHtml(label)}</h2>
    <p class="subtitle">{ok.len} empresas con datos validos de {totalConsulted} consultadas</p>
    {buildKpiCards(ok, totalConsulted)}
    <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th class="sticky-col col-rank">#</th><th class="sticky-col col-ticker">Ticker</th><th>Empresa</th><th>Sector</th><th>Score</th>
          <th>P/E</th><th>PEG</th><th>EV/EBITDA</th><th>ROE</th><th>FCF Yield</th>
          <th>Div Yield</th><th>An. Upside</th><th>Recom.</th><th>N. Analistas</th><th>Metricas</th>
        </tr>
      </thead>
      <tbody>
{buildTableRows(ok)}
      </tbody>
    </table>
    </div>
    {buildIssuesList("Sin metricas utilizables", noData, false)}
    {buildIssuesList("Sin datos (error de descarga)", failed, true)}
  </section>"""

const ExtraStyle = """
  .kpi-row { display: flex; flex-wrap: wrap; gap: 12px; margin: 0 0 18px; }
  .kpi-card {
    flex: 1 1 150px; min-width: 150px; background: var(--panel); border: 1px solid var(--border);
    border-radius: 10px; padding: 12px 14px; box-shadow: var(--shadow);
    display: flex; flex-direction: column; gap: 3px;
  }
  .kpi-label { font-size: 0.72rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.04em; }
  .kpi-value { font-size: 1.15rem; font-weight: 700; }
  .kpi-value a { color: var(--text); }
  .kpi-sub { font-size: 0.72rem; color: var(--muted); font-weight: 500; }

  table { min-width: 960px; }
  thead th:nth-child(2), thead th:nth-child(3), thead th:nth-child(4), thead th:nth-child(13) { text-align: left; }
  tbody td:nth-child(3) { white-space: normal; min-width: 180px; font-variant-numeric: normal; }
  tbody tr:nth-child(even) td.sticky-col { background: var(--row-alt); }
  tbody tr:hover td.sticky-col { background: var(--accent-soft); }
  tbody tr.top3 { background: color-mix(in srgb, var(--good) 7%, var(--panel)); }
  tbody tr.top3 td.sticky-col { background: color-mix(in srgb, var(--good) 7%, var(--panel)); }
  td:nth-child(2), td:nth-child(3), td:nth-child(4), td:nth-child(13) { text-align: left; }

  .sticky-col { position: sticky; background: var(--panel); z-index: 1; }
  .col-rank { left: 0; width: 34px; min-width: 34px; }
  .col-ticker { left: 34px; min-width: 88px; box-shadow: 2px 0 0 0 var(--border) inset; }

  td.score { min-width: 130px; }
  .score-cell { display: flex; align-items: center; gap: 8px; justify-content: flex-end; }
  .score-num { font-weight: 700; min-width: 34px; text-align: right; }
  .score-num.good { color: var(--good); }
  .score-num.mid { color: var(--mid); }
  .score-num.low { color: var(--low); }
  .score-bar { width: 52px; height: 6px; border-radius: 4px; background: var(--border); overflow: hidden; flex: 0 0 auto; }
  .score-bar-fill { display: block; height: 100%; border-radius: 4px; }
  .score-bar-fill.good { background: var(--good); }
  .score-bar-fill.mid { background: var(--mid); }
  .score-bar-fill.low { background: var(--low); }

  .rank-badge {
    display: inline-flex; align-items: center; justify-content: center;
    width: 20px; height: 20px; border-radius: 50%; font-weight: 700; font-size: 0.72rem;
    color: #3a2d05;
  }
  .rank-badge.rank-1 { background: #f2c94c; }
  .rank-badge.rank-2 { background: #cfd4db; color: #2a2f38; }
  .rank-badge.rank-3 { background: #d9a066; color: #3a2408; }

  .badge {
    display: inline-block; padding: 3px 10px; border-radius: 999px; font-size: 0.72rem;
    font-weight: 700; letter-spacing: 0.01em;
  }
  .badge-buy { background: color-mix(in srgb, var(--good) 18%, transparent); color: var(--good); }
  .badge-hold { background: color-mix(in srgb, var(--mid) 18%, transparent); color: var(--mid); }
  .badge-sell { background: color-mix(in srgb, var(--low) 18%, transparent); color: var(--low); }
  .badge-na { background: var(--head); color: var(--muted); }

  td.pos { color: var(--pos); }
  td.neg { color: var(--neg); }
  td.muted { color: var(--muted); }
  .issues { margin-top: 16px; font-size: 0.85rem; color: var(--muted); }
  .issues h3 { font-size: 0.85rem; margin: 0 0 6px; color: var(--text); }
  .issues ul { margin: 0; padding-left: 18px; }
  .issues li { margin-bottom: 2px; }

  @media (max-width: 640px) {
    .kpi-card { flex: 1 1 42%; }
  }
"""

const Footer = """El score pondera z-scores de P/E, P/B, EV/EBITDA, PEG, ROE, ROA, margenes, deuda/patrimonio,
    razon corriente, crecimiento de ingresos/utilidades, dividend yield y FCF yield, comparados
    primero contra el propio sector de la empresa (respaldo global si el sector tiene pocos datos),
    winsorizados a +-3 desviaciones estandar y reescalados 0-100.<br/>
    El PEG solo se calcula con crecimiento de utilidades positivo. La columna "An. Upside"
    (precio objetivo promedio de analistas vs. precio actual) es informativa y no entra al score.<br/>
    El score de un universo NO es comparable con el de otro universo: cada ranking es relativo
    solo a las empresas de su propia lista.<br/>
    <strong>No es una recomendacion de inversion.</strong>"""

proc writeReport*(path: string, title: string, generatedAt: string, sections: seq[tuple[label: string, html: string]]) =
  let html = renderPage(
    title = "DriftFolio",
    logo = "CF",
    h1 = "Analisis fundamental &middot; " & escapeHtml(title),
    meta = "Generado el " & escapeHtml(generatedAt) &
      " &middot; datos de Yahoo Finance &middot; cada ticker abre stockanalysis.com en pestana nueva",
    footer = Footer,
    sections = sections,
    extraStyle = ExtraStyle
  )
  writeFile(path, html)
