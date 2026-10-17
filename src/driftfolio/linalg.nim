## Álgebra lineal genérica usada por la optimización de portafolio: no
## depende de nada específico a finanzas, por lo que es fácil de testear
## de forma aislada (M-008).

import ./errorlog

proc zeroMatrix*(n: int): seq[seq[float]] =
  result = newSeq[seq[float]](n)
  for i in 0 ..< n:
    result[i] = newSeq[float](n)

proc subMatrix*(cov: seq[seq[float]], n: int): seq[seq[float]] =
  # Submatriz N×N de una covarianza EWMA: cada entrada se calculó por par de
  # activos, independiente de qué otros activos estén en la matriz completa,
  # así que restringir a un subconjunto sigue siendo la covarianza correcta
  # para ese subconjunto (no hace falta recalcular ni volver a descargar).
  result = newSeq[seq[float]](n)
  for i in 0 ..< n:
    result[i] = cov[i][0 ..< n]

const SingularPivotEpsilon* = 1e-12

proc solveLinearSystem*(a: seq[seq[float]], b: seq[float]): seq[float] =
  # Eliminación gaussiana con pivoteo parcial para resolver A x = b.
  # Devuelve seq vacío si la matriz es (casi) singular, en vez de propagar
  # NaN/Inf en silencio.
  let n = b.len
  var m = newSeq[seq[float]](n)
  for i in 0 ..< n:
    m[i] = a[i]
  var rhs = b

  for col in 0 ..< n:
    var pivotRow = col
    var maxVal = abs(m[col][col])
    for r in (col + 1) ..< n:
      if abs(m[r][col]) > maxVal:
        maxVal = abs(m[r][col])
        pivotRow = r
    if pivotRow != col:
      swap(m[col], m[pivotRow])
      swap(rhs[col], rhs[pivotRow])

    let pivot = m[col][col]
    if abs(pivot) < SingularPivotEpsilon:
      logError("Matriz de covarianza (casi) singular, no se pudo resolver el sistema lineal.")
      return @[]

    for r in (col + 1) ..< n:
      let factor = m[r][col] / pivot
      for c in col ..< n:
        m[r][c] -= factor * m[col][c]
      rhs[r] -= factor * rhs[col]

  result = newSeq[float](n)
  for i in countdown(n - 1, 0):
    var s = rhs[i]
    for j in (i + 1) ..< n:
      s -= m[i][j] * result[j]
    result[i] = s / m[i][i]

proc clampVal*(x, lo, hi: float): float =
  max(lo, min(hi, x))

proc projectCappedSimplex*(v: seq[float], cap: float): seq[float] =
  # Proyección euclidiana sobre {w : sum(w)=1, 0<=w_i<=cap} vía bisección
  # (water-filling): busca el umbral tau tal que clamp(v_i - tau, 0, cap) sume 1.
  var lo = min(v) - cap
  var hi = max(v)
  for _ in 0 ..< 60:
    let mid = (lo + hi) / 2
    var s = 0.0
    for x in v:
      s += clampVal(x - mid, 0.0, cap)
    if s > 1.0:
      lo = mid
    else:
      hi = mid
  let tau = (lo + hi) / 2
  result = newSeq[float](v.len)
  for i in 0 ..< v.len:
    result[i] = clampVal(v[i] - tau, 0.0, cap)
