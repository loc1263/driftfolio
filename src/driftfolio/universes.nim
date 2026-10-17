## Universos de activos. Las listas por defecto quedan embebidas en el
## binario (siempre funciona sin configuración); si existe un archivo
## `universes.json` en el directorio donde se ejecuta driftfolio, sus listas
## lo reemplazan sin necesidad de recompilar (M-001).
##
## Formato esperado de universes.json:
##   {"chile": ["CHILE.SN", ...], "vanguard": ["VOO", ...]}
## Cualquier clave ausente, o con un valor que no sea una lista, conserva el
## default embebido para esa clave en particular.
##
## El mega-cap EEUU no está acá: se descarga dinámicamente desde el CSV de
## holdings del ETF iShares S&P 100 (ver `marketdata.fetchMegaCapTickers`)
## porque esa composición cambia seguido.

import std/[json, os, sequtils]
import ./errorlog

const DefaultChileanTickers = [
  "CHILE.SN", "BSANTANDER.SN", "BCI.SN", "ITAUCL.SN",
  "SQM-B.SN", "LTM.SN", "FALABELLA.SN", "CENCOSUD.SN",
  "COPEC.SN", "CMPC.SN", "ENELCHILE.SN", "COLBUN.SN",
  "PARAUCO.SN", "MALLPLAZA.SN", "ANDINA-B.SN", "CCU.SN",
  "CAP.SN", "VAPORES.SN", "ILC.SN", "ENTEL.SN"
]

const DefaultVanguardETFs = [
  "VOO", "VTI", "VEA", "VWO", "VXUS",
  "BND", "VNQ", "VIG", "VUG", "VTV",
  "VOOG", "VOOV", "VB", "VO", "VGT",
  "VHT", "VFH", "VDE", "VAW", "VCR",
  "VPL"
]

const UniversesConfigFile* = "universes.json"

proc loadUniverses*(path: string = UniversesConfigFile): tuple[chile, vanguard: seq[string]] =
  result = (chile: @DefaultChileanTickers, vanguard: @DefaultVanguardETFs)

  if not fileExists(path):
    return

  try:
    let data = parseJson(readFile(path))

    let chileNode = data{"chile"}
    if not chileNode.isNil and chileNode.kind == JArray:
      result.chile = chileNode.mapIt(it.getStr)

    let vanguardNode = data{"vanguard"}
    if not vanguardNode.isNil and vanguardNode.kind == JArray:
      result.vanguard = vanguardNode.mapIt(it.getStr)

    echo "Universos cargados desde ", path
  except CatchableError as e:
    logError("No se pudo leer " & path & ", se usan los tickers por defecto: " &
      e.msg & " (" & $e.name & ")")
