## Reporte HTML: tablas, links a stockanalysis.com y gráficos (Chart.js).
## Comparte diseño (colores, masthead, quicknav, tablas, toggle de tema,
## mobile) con el reporte de análisis fundamental vía ../theme.

import std/[strutils, sequtils, algorithm, strformat]
import ./types, ./errorlog
import ../theme

proc escapeHtml*(s: string): string =
  s.multiReplace([("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;")])

proc jsStrArray*(items: seq[string]): string =
  var parts: seq[string]
  for it in items:
    parts.add("\"" & it.replace("\\", "\\\\").replace("\"", "\\\"") & "\"")
  "[" & parts.join(",") & "]"

proc jsNumArray*(items: seq[float]): string =
  var parts: seq[string]
  for it in items:
    parts.add(formatFloat(it, ffDecimal, 4))
  "[" & parts.join(",") & "]"

proc paletteColors*(n: int): seq[string] =
  for i in 0 ..< n:
    result.add("hsl(" & $((i * 360) div max(n, 1)) & ", 70%, 55%)")

const BarChartTemplate = """
    <script>
      new Chart(document.getElementById('__ID__'), {
        type: 'bar',
        data: {
          labels: __LABELS__,
          datasets: [{
            label: 'Score (momentum)',
            data: __SCORES__,
            backgroundColor: __COLORS__
          }]
        },
        options: {
          indexAxis: 'y',
          plugins: {
            legend: { display: false },
            title: { display: true, text: '__CHARTTITLE__' }
          },
          scales: { x: { title: { display: true, text: 'Score' } } }
        }
      });
    </script>
"""

const DoughnutChartTemplate = """
    <script>
      new Chart(document.getElementById('__ID__'), {
        type: 'doughnut',
        data: {
          labels: __LABELS__,
          datasets: [{
            data: __DATA__,
            backgroundColor: __COLORS__
          }]
        },
        options: {
          plugins: {
            title: { display: true, text: '__CHARTTITLE__' }
          }
        }
      });
    </script>
"""

const UniverseSectionTemplate = """
  <section>
    <h2>__TITLE__</h2>
    <p class="subtitle">Total de activos: __TOTAL__ | Sobre SMA50: __ABOVE__</p>
    <div class="chart-wrap"><canvas id="__CHARTID__"></canvas></div>
    <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th>#</th><th>Ticker</th><th>1M %</th><th>3M %</th><th>6M %</th>
          <th>Score</th><th>Precio</th><th>SMA50</th><th>&gt;SMA50</th>
        </tr>
      </thead>
      <tbody>
__ROWS__
      </tbody>
    </table>
    </div>
__CHARTSCRIPT__
  </section>
"""

proc quoteRowHtml(idx: int, q: Quote): string =
  let c1 = if q.ret1m > 0: "pos" elif q.ret1m < 0: "neg" else: ""
  let c3 = if q.ret3m > 0: "pos" elif q.ret3m < 0: "neg" else: ""
  let c6 = if q.ret6m > 0: "pos" elif q.ret6m < 0: "neg" else: ""
  let cs = if q.score > 0: "pos" elif q.score < 0: "neg" else: ""
  let above = if q.aboveSma50: "Sí" else: "No"
  let ca = if q.aboveSma50: "pos" else: ""
  fmt"""        <tr>
          <td>{idx}</td>
          <td><a href="{escapeHtml(q.url)}" target="_blank" rel="noopener noreferrer">{escapeHtml(q.ticker)}</a></td>
          <td class="{c1}">{q.ret1m:.2f}</td>
          <td class="{c3}">{q.ret3m:.2f}</td>
          <td class="{c6}">{q.ret6m:.2f}</td>
          <td class="{cs}">{q.score:.2f}</td>
          <td>{q.price:.2f}</td>
          <td>{q.sma50:.2f}</td>
          <td class="{ca}">{above}</td>
        </tr>"""

proc universeHtmlSection*(title: string, results: seq[Quote], chartId: string): string =
  var rows: seq[string]
  for i, q in results:
    rows.add(quoteRowHtml(i + 1, q))

  # Para universos grandes (mega-cap) el gráfico se limita a los líderes de
  # score para mantenerlo legible; la tabla completa sigue debajo.
  let chartCount = min(results.len, 20)
  let chartResults = results[0 ..< chartCount]
  let labels = jsStrArray(chartResults.mapIt(it.ticker))
  let scores = jsNumArray(chartResults.mapIt(it.score))
  let colors = jsStrArray(chartResults.mapIt(if it.score >= 0: "#2e9e4f" else: "#d64545"))

  let chartScript = BarChartTemplate.multiReplace([
    ("__ID__", chartId),
    ("__LABELS__", labels),
    ("__SCORES__", scores),
    ("__COLORS__", colors),
    ("__CHARTTITLE__", "Top " & $chartCount & " por score")
  ])

  UniverseSectionTemplate.multiReplace([
    ("__TITLE__", escapeHtml(title)),
    ("__TOTAL__", $results.len),
    ("__ABOVE__", $results.countIt(it.aboveSma50)),
    ("__CHARTID__", chartId),
    ("__ROWS__", rows.join("\n")),
    ("__CHARTSCRIPT__", chartScript)
  ])

const ExtraStyle = """
  h3 { margin: 18px 0 8px; font-size: 1rem; }
  table { min-width: 640px; }
  th:nth-child(2), td:nth-child(2) { text-align: left; }
  table.weights th:first-child, table.weights td:first-child { text-align: left; }
  .chart-wrap { max-width: 720px; margin: 8px 0 20px; }
  .chart-wrap-pie { max-width: 420px; }
"""

const ExtraHead = """<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>"""

const Footer = """El score de momentum pondera retornos a 1, 3 y 6 meses (ver fórmula arriba); la columna
    &gt;SMA50 es informativa y no excluye activos del ranking. El portafolio Markowitz usa el score de
    momentum como proxy de retorno esperado y una covarianza EWMA sobre varios años de histórico diario.<br/>
    <strong>No es una recomendación de inversión.</strong>"""

proc writeHtmlReport*(filename: string, generatedAt: string,
                       sections: seq[tuple[label: string, html: string]]) =
  let meta = "Generado: " & escapeHtml(generatedAt) &
    " &middot; Score = 20% &times; Retorno 1M + 40% &times; Retorno 3M + 40% &times; Retorno 6M " &
    "&middot; &gt;SMA50 es informativo (no excluye activos)"

  let html = renderPage(
    title = "DriftFolio",
    logo = "DF",
    h1 = "DriftFolio &middot; Momentum + Markowitz",
    meta = meta,
    footer = Footer,
    sections = sections,
    extraStyle = ExtraStyle,
    extraHead = ExtraHead
  )

  var f: File
  if not open(f, filename, fmWrite):
    logError("No se pudo escribir el archivo HTML: " & filename)
    return
  defer: f.close()
  f.write(html)

  echo "Reporte HTML exportado a ", filename

proc weightsRowsHtml*(tickers, urls: seq[string], weights: seq[float], minWeight = 0.0, useAbs = false): string =
  ## `useAbs = true` filtra por `|peso| > minWeight` en vez de `peso >
  ## minWeight`, para no esconder posiciones cortas (M-014) en la tabla del
  ## portafolio "sin restricciones". Los pesos negativos se marcan con la
  ## misma clase CSS "neg" que usa el resto del reporte.
  var order = toSeq(0 ..< weights.len)
  order.sort(proc (a, b: int): int = cmp(weights[b], weights[a]))
  var rows: seq[string]
  for i in order:
    let shown = if useAbs: abs(weights[i]) > minWeight else: weights[i] > minWeight
    if shown:
      let cls = if weights[i] < 0: " class=\"neg\"" else: ""
      rows.add fmt"""        <tr>
          <td><a href="{escapeHtml(urls[i])}" target="_blank" rel="noopener noreferrer">{escapeHtml(tickers[i])}</a></td>
          <td{cls}>{weights[i] * 100:.2f}</td>
        </tr>"""
  rows.join("\n")

const MarkowitzSectionTemplate = """
  <section>
    <h2>Markowitz - mejor portafolio (top __N__ por momentum, covarianza EWMA __YEARS__ años)</h2>
    <p class="subtitle">Tasa libre de riesgo (^IRX, 13 semanas): __RF__%</p>

    <h3>Sin restricciones (teórico, permite posiciones en corto)</h3>
    <div class="table-wrap">
    <table class="weights">
      <thead><tr><th>Ticker</th><th>Peso %</th></tr></thead>
      <tbody>
__ROWS_UNCONSTRAINED__
      </tbody>
    </table>
    </div>
    <p>Retorno esperado: <strong>__RET1__%</strong> &middot; Volatilidad anualizada: <strong>__VOL1__%</strong> &middot; Sharpe: <strong>__SHARPE1__</strong></p>
    <p class="muted">Nota: pesos negativos implican posición corto, no ejecutable en un bróker normal.</p>

    <h3>Long-only, tope __CAP__% por posición (ejecutable en un bróker normal)</h3>
    <div class="chart-wrap chart-wrap-pie"><canvas id="chart-markowitz"></canvas></div>
    <div class="table-wrap">
    <table class="weights">
      <thead><tr><th>Ticker</th><th>Peso %</th></tr></thead>
      <tbody>
__ROWS_LONGONLY__
      </tbody>
    </table>
    </div>
    <p>Retorno esperado: <strong>__RET2__%</strong> &middot; Volatilidad anualizada: <strong>__VOL2__%</strong> &middot; Sharpe: <strong>__SHARPE2__</strong></p>
__CHARTSCRIPT__
  </section>
"""

proc markowitzHtmlSection*(tickers, urls: seq[string], weights, loWeights: seq[float],
                            riskFreeRate, cap: float, lookbackYears: int,
                            unconstrainedStats, longOnlyStats: tuple[ret, vol, sharpe: float]): string =
  var loLabels: seq[string]
  var loData: seq[float]
  var order = toSeq(0 ..< loWeights.len)
  order.sort(proc (a, b: int): int = cmp(loWeights[b], loWeights[a]))
  for i in order:
    if loWeights[i] > 0.0001:
      loLabels.add(tickers[i])
      loData.add(loWeights[i] * 100)

  let chartScript = DoughnutChartTemplate.multiReplace([
    ("__ID__", "chart-markowitz"),
    ("__LABELS__", jsStrArray(loLabels)),
    ("__DATA__", jsNumArray(loData)),
    ("__COLORS__", jsStrArray(paletteColors(loLabels.len))),
    ("__CHARTTITLE__", "Asignación long-only (tope " & fmt"{cap * 100:.0f}" & "%)")
  ])

  MarkowitzSectionTemplate.multiReplace([
    ("__N__", $tickers.len),
    ("__YEARS__", $lookbackYears),
    ("__RF__", formatFloat(riskFreeRate * 100, ffDecimal, 2)),
    ("__ROWS_UNCONSTRAINED__", weightsRowsHtml(tickers, urls, weights, useAbs = true)),
    ("__RET1__", formatFloat(unconstrainedStats.ret * 100, ffDecimal, 2)),
    ("__VOL1__", formatFloat(unconstrainedStats.vol * 100, ffDecimal, 2)),
    ("__SHARPE1__", formatFloat(unconstrainedStats.sharpe, ffDecimal, 2)),
    ("__CAP__", fmt"{cap * 100:.0f}"),
    ("__ROWS_LONGONLY__", weightsRowsHtml(tickers, urls, loWeights, 0.0001)),
    ("__RET2__", formatFloat(longOnlyStats.ret * 100, ffDecimal, 2)),
    ("__VOL2__", formatFloat(longOnlyStats.vol * 100, ffDecimal, 2)),
    ("__SHARPE2__", formatFloat(longOnlyStats.sharpe, ffDecimal, 2)),
    ("__CHARTSCRIPT__", chartScript)
  ])

const ConcentratedSectionTemplate = """
  <section>
    <h2>Portafolio concentrado: top __N__ por momentum (re-optimizado)</h2>
    <p class="subtitle">Son los __N__ activos de mayor score dentro del top __FULLN__, pero con pesos
    recalculados desde su propia matriz de covarianza __N__×__N__ — no es un recorte de los pesos
    del portafolio de __FULLN__ activos (ver nota abajo).</p>
    <div class="chart-wrap chart-wrap-pie"><canvas id="chart-concentrado"></canvas></div>
    <div class="table-wrap">
    <table class="weights">
      <thead><tr><th>Ticker</th><th>Peso %</th></tr></thead>
      <tbody>
__ROWS__
      </tbody>
    </table>
    </div>
    <p>Retorno esperado: <strong>__RET__%</strong> &middot; Volatilidad anualizada: <strong>__VOL__%</strong> &middot; Sharpe: <strong>__SHARPE__</strong></p>
    <p class="muted">Tope por posición: __CAP__% (más holgado que el __FULLCAP__% del portafolio de __FULLN__, porque hay menos nombres entre los que repartir el 100%).</p>
__CHARTSCRIPT__
  </section>
"""

proc concentratedHtmlSection*(tickers, urls: seq[string], weights: seq[float],
                               stats: tuple[ret, vol, sharpe: float],
                               cap, fullCap: float, fullN: int): string =
  # A diferencia del portafolio de fullN activos, acá se muestran las N
  # posiciones completas (incluyendo 0.00%) para que quede explícito que el
  # optimizador sí evaluó cada candidato y decidió no asignarle peso.
  var labels: seq[string]
  var data: seq[float]
  var order = toSeq(0 ..< weights.len)
  order.sort(proc (a, b: int): int = cmp(weights[b], weights[a]))
  for i in order:
    labels.add(tickers[i])
    data.add(weights[i] * 100)

  let chartScript = DoughnutChartTemplate.multiReplace([
    ("__ID__", "chart-concentrado"),
    ("__LABELS__", jsStrArray(labels)),
    ("__DATA__", jsNumArray(data)),
    ("__COLORS__", jsStrArray(paletteColors(labels.len))),
    ("__CHARTTITLE__", "Portafolio concentrado (" & $tickers.len & " activos)")
  ])

  ConcentratedSectionTemplate.multiReplace([
    ("__N__", $tickers.len),
    ("__FULLN__", $fullN),
    ("__ROWS__", weightsRowsHtml(tickers, urls, weights, -1.0)),
    ("__RET__", formatFloat(stats.ret * 100, ffDecimal, 2)),
    ("__VOL__", formatFloat(stats.vol * 100, ffDecimal, 2)),
    ("__SHARPE__", formatFloat(stats.sharpe, ffDecimal, 2)),
    ("__CAP__", fmt"{cap * 100:.0f}"),
    ("__FULLCAP__", fmt"{fullCap * 100:.0f}"),
    ("__CHARTSCRIPT__", chartScript)
  ])
