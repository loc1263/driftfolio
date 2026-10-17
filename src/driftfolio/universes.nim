## Universos de activos con lista de tickers fija.
##
## El mega-cap EEUU no está acá: se descarga dinámicamente desde el CSV de
## holdings del ETF iShares S&P 100 (ver `marketdata.fetchMegaCapTickers`)
## porque esa composición cambia seguido.

const ChileanTickers* = [
  "CHILE.SN", "BSANTANDER.SN", "BCI.SN", "ITAUCL.SN",
  "SQM-B.SN", "LTM.SN", "FALABELLA.SN", "CENCOSUD.SN",
  "COPEC.SN", "CMPC.SN", "ENELCHILE.SN", "COLBUN.SN",
  "PARAUCO.SN", "MALLPLAZA.SN", "ANDINA-B.SN", "CCU.SN",
  "CAP.SN", "VAPORES.SN", "ILC.SN", "ENTEL.SN"
]

const VanguardETFs* = [
  "VOO", "VTI", "VEA", "VWO", "VXUS",
  "BND", "VNQ", "VIG", "VUG", "VTV",
  "VOOG", "VOOV", "VB", "VO", "VGT",
  "VHT", "VFH", "VDE", "VAW", "VCR",
  "VPL"
]
