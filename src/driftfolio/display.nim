## Salida por consola: colores (M-013), barra de progreso y tabla de pesos.

import std/[terminal, strutils, algorithm, sequtils, strformat, unicode]

let useColor* = isatty(stdout)

proc writeColored*(value: float, width: int) =
  let s = align(formatFloat(value, ffDecimal, 2), width)
  if not useColor or value == 0:
    stdout.write(s)
  elif value > 0:
    stdout.styledWrite(fgGreen, s)
  else:
    stdout.styledWrite(fgRed, s)

proc writeAboveStr*(above: bool, width: int) =
  # "Sí" tiene una tilde de 2 bytes en UTF-8 que strutils.align cuenta como
  # 2 caracteres (cuenta bytes, no runas visibles), así que le da un espacio
  # de relleno de menos que a "No" y queda desalineado. unicode.align cuenta
  # runas, no bytes, y alinea igual que "No".
  let s = unicode.align((if above: "Sí" else: "No"), width)
  if above and useColor:
    stdout.styledWrite(fgGreen, s)
  else:
    stdout.write(s)

proc printProgress*(current, total: int, ticker: string) =
  const barWidth = 30
  let filled = (current * barWidth) div total
  let bar = "#".repeat(filled) & "-".repeat(barWidth - filled)
  let line = "[" & bar & "] " & $current & "/" & $total & " " & alignLeft(ticker, 15)
  if useColor:
    stdout.write("\r" & line)
    stdout.flushFile()
  else:
    echo line

proc clearProgress*() =
  if useColor:
    stdout.write("\r" & " ".repeat(60) & "\r")
    stdout.flushFile()

proc printWeights*(tickers: seq[string], weights: seq[float], minWeight = 0.0, useAbs = false) =
  ## `useAbs = true` filtra por `|peso| > minWeight` en vez de `peso >
  ## minWeight`, para no esconder posiciones cortas (M-014): el portafolio
  ## "sin restricciones" puede tener pesos negativos, y con el filtro por
  ## signo quedaban completamente fuera de la tabla sin ningún aviso.
  var order = toSeq(0 ..< weights.len)
  order.sort(proc (a, b: int): int = cmp(weights[b], weights[a]))

  echo fmt"""{"Ticker":<12} {"Peso %":>10}"""
  echo "-".repeat(24)
  for i in order:
    let shown = if useAbs: abs(weights[i]) > minWeight else: weights[i] > minWeight
    if shown:
      echo fmt"{tickers[i]:<12} {weights[i] * 100:>10.2f}"
