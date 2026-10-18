## Parámetros configurables del modelo de momentum y del portafolio Markowitz
## (M-006). Se cargan desde `driftfolio.config.json` si existe en el
## directorio de ejecución; si no existe, o algún valor es inválido, se usan
## los valores de fábrica embebidos acá — igual que `universes.loadUniverses`
## (M-001), driftfolio siempre funciona sin ningún archivo de configuración.
##
## `driftfolio --reset-config` escribe (o sobrescribe) ese archivo con los
## valores de fábrica, por si alguien lo editó hasta dejarlo irreconocible.

import std/[json, os, strformat]
import ./errorlog

type
  Config* = object
    # Qué universos correr
    runChile*, runVanguard*, runMegaCap*: bool
    # Score de momentum
    ret1mDays*, ret3mDays*, ret6mDays*: int
    ret1mWeight*, ret3mWeight*, ret6mWeight*: float
    smaPeriod*: int
    minHistoryDays*: int
    # Portafolio Markowitz
    markowitzTopN*: int
    markowitzLookbackYears*: int
    ewmaLambda*: float
    maxWeightPerAsset*: float
    markowitzFinalN*: int
    finalPortfolioCap*: float

const ConfigFile* = "driftfolio.config.json"

const DefaultConfig* = Config(
  runChile: true, runVanguard: true, runMegaCap: true,
  ret1mDays: 21, ret3mDays: 63, ret6mDays: 126,
  ret1mWeight: 0.20, ret3mWeight: 0.40, ret6mWeight: 0.40,
  smaPeriod: 50,
  minHistoryDays: 130,
  markowitzTopN: 15,
  markowitzLookbackYears: 5,
  ewmaLambda: 0.94,
  maxWeightPerAsset: 0.20,
  markowitzFinalN: 4,
  finalPortfolioCap: 0.40
)

proc toJson(c: Config): JsonNode =
  %*{
    "universos": {
      "chile": c.runChile,
      "vanguard": c.runVanguard,
      "megaCap": c.runMegaCap
    },
    "score": {
      "ret1mDias": c.ret1mDays,
      "ret3mDias": c.ret3mDays,
      "ret6mDias": c.ret6mDays,
      "ret1mPeso": c.ret1mWeight,
      "ret3mPeso": c.ret3mWeight,
      "ret6mPeso": c.ret6mWeight,
      "smaPeriodo": c.smaPeriod,
      "historiaMinimaDias": c.minHistoryDays
    },
    "markowitz": {
      "topN": c.markowitzTopN,
      "historicoAnios": c.markowitzLookbackYears,
      "ewmaLambda": c.ewmaLambda,
      "topePorPosicion": c.maxWeightPerAsset,
      "concentradoN": c.markowitzFinalN,
      "concentradoTope": c.finalPortfolioCap
    }
  }

proc writeDefaultConfig*(path: string = ConfigFile) =
  writeFile(path, pretty(toJson(DefaultConfig)))

# ============================================================
# Validación: cada campo inválido cae en su default de fábrica (no en el
# archivo entero), con una línea en el log explicando por qué.
# ============================================================

proc validInt(value, fallback: int, name: string, minVal: int): int =
  if value < minVal:
    logError(fmt"Parámetro '{name}' inválido ({value}), debe ser >= {minVal}. Se usa el valor de fábrica ({fallback}).")
    fallback
  else:
    value

proc validFloat(value, fallback: float, name: string, minVal, maxVal: float): float =
  if value < minVal or value > maxVal:
    logError(fmt"Parámetro '{name}' inválido ({value}), debe estar entre {minVal} y {maxVal}. Se usa el valor de fábrica ({fallback}).")
    fallback
  else:
    value

proc loadConfig*(path: string = ConfigFile): Config =
  result = DefaultConfig
  if not fileExists(path):
    return

  try:
    let data = parseJson(readFile(path))

    let universos = data{"universos"}
    result.runChile = universos{"chile"}.getBool(result.runChile)
    result.runVanguard = universos{"vanguard"}.getBool(result.runVanguard)
    result.runMegaCap = universos{"megaCap"}.getBool(result.runMegaCap)

    let score = data{"score"}
    result.ret1mDays = validInt(score{"ret1mDias"}.getInt(result.ret1mDays),
      DefaultConfig.ret1mDays, "score.ret1mDias", 1)
    result.ret3mDays = validInt(score{"ret3mDias"}.getInt(result.ret3mDays),
      DefaultConfig.ret3mDays, "score.ret3mDias", 1)
    result.ret6mDays = validInt(score{"ret6mDias"}.getInt(result.ret6mDays),
      DefaultConfig.ret6mDays, "score.ret6mDias", 1)
    result.ret1mWeight = validFloat(score{"ret1mPeso"}.getFloat(result.ret1mWeight),
      DefaultConfig.ret1mWeight, "score.ret1mPeso", 0.0, 1.0)
    result.ret3mWeight = validFloat(score{"ret3mPeso"}.getFloat(result.ret3mWeight),
      DefaultConfig.ret3mWeight, "score.ret3mPeso", 0.0, 1.0)
    result.ret6mWeight = validFloat(score{"ret6mPeso"}.getFloat(result.ret6mWeight),
      DefaultConfig.ret6mWeight, "score.ret6mPeso", 0.0, 1.0)
    result.smaPeriod = validInt(score{"smaPeriodo"}.getInt(result.smaPeriod),
      DefaultConfig.smaPeriod, "score.smaPeriodo", 1)
    result.minHistoryDays = validInt(score{"historiaMinimaDias"}.getInt(result.minHistoryDays),
      DefaultConfig.minHistoryDays, "score.historiaMinimaDias", 1)

    let mk = data{"markowitz"}
    result.markowitzTopN = validInt(mk{"topN"}.getInt(result.markowitzTopN),
      DefaultConfig.markowitzTopN, "markowitz.topN", 2)
    result.markowitzLookbackYears = validInt(mk{"historicoAnios"}.getInt(result.markowitzLookbackYears),
      DefaultConfig.markowitzLookbackYears, "markowitz.historicoAnios", 1)
    result.ewmaLambda = validFloat(mk{"ewmaLambda"}.getFloat(result.ewmaLambda),
      DefaultConfig.ewmaLambda, "markowitz.ewmaLambda", 0.01, 0.99)
    result.maxWeightPerAsset = validFloat(mk{"topePorPosicion"}.getFloat(result.maxWeightPerAsset),
      DefaultConfig.maxWeightPerAsset, "markowitz.topePorPosicion", 0.01, 1.0)
    result.markowitzFinalN = validInt(mk{"concentradoN"}.getInt(result.markowitzFinalN),
      DefaultConfig.markowitzFinalN, "markowitz.concentradoN", 1)
    result.finalPortfolioCap = validFloat(mk{"concentradoTope"}.getFloat(result.finalPortfolioCap),
      DefaultConfig.finalPortfolioCap, "markowitz.concentradoTope", 0.01, 1.0)

    # Coherencia entre ventanas: con menos historia que ret6mDias+1 el
    # retorno a 6 meses (y probablemente la SMA) dan 0 para casi todos los
    # tickers, silenciosamente. Se corrige en vez de solo avisar.
    if result.minHistoryDays < result.ret6mDays + 1:
      logError(fmt"'score.historiaMinimaDias' ({result.minHistoryDays}) es menor que 'ret6mDias' + 1 " &
        fmt"({result.ret6mDays + 1}); el retorno a 6 meses daría 0 para casi todos los tickers. " &
        fmt"Se ajusta historiaMinimaDias a {result.ret6mDays + 1}.")
      result.minHistoryDays = result.ret6mDays + 1

    echo "Parámetros cargados desde ", path
  except CatchableError as e:
    logError("No se pudo leer " & path & ", se usan los parámetros de fábrica: " & e.msg & " (" & $e.name & ")")
    result = DefaultConfig
