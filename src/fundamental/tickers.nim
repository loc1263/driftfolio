import std/strutils

## Lista de tickers del IPSA (formato Yahoo Finance, sufijo .SN).
##
## La composicion del indice cambia periodicamente (revisiones semestrales
## de la Bolsa de Santiago). Esta lista puede quedar desactualizada; editala
## directamente o entrega un archivo propio con --tickers=ruta.csv
## (una linea por ticker, p.ej. "SQM-B.SN").

const DefaultIpsaTickers*: seq[string] = @[
  "SQM-B.SN",
  "CHILE.SN",
  "BSANTANDER.SN",
  "BCI.SN",
  "ITAUCL.SN",
  "COPEC.SN",
  "CMPC.SN",
  "FALABELLA.SN",
  "CENCOSUD.SN",
  "CENCOSHOPP.SN",
  "ENELAM.SN",
  "ENELCHILE.SN",
  "COLBUN.SN",
  "AGUAS-A.SN",
  "CCU.SN",
  "ANDINA-B.SN",
  "CAP.SN",
  "PARAUCO.SN",
  "MALLPLAZA.SN",
  "RIPLEY.SN",
  "SMU.SN",
  "ENTEL.SN",
  "LTM.SN",
  "SONDA.SN",
  "QUINENCO.SN",
  "ILC.SN",
  "VAPORES.SN",
  "VSPT.SN",
  # "SECURITY.SN" y "ORO-BLANCO.SN" dejaron de responder en Yahoo Finance
  # (probable reorganizacion/fusion corporativa); verifica el ticker vigente
  # e incluyelo con --tickers=archivo.csv si corresponde.
]

## Mega-caps de EE.UU. (sin sufijo, formato Yahoo Finance estandar).
##
## Esta lista se genero consultando el screener real de Yahoo Finance
## (POST a query1.finance.yahoo.com/v1/finance/screener, mismo crumb/cookie
## que quoteSummary) con el filtro intradaymarketcap > 200,000,000,000 USD,
## el 2026-10-17. Del resultado (119 acciones) se dejaron solo empresas con
## domicilio/sede en EE.UU. y una accion por compania, descartando:
##   - ADRs de empresas extranjeras aunque coticen en NYSE/Nasdaq (TSM, ASML,
##     NVS, BABA, SAP, AZN, RY, HSBC, MUFG, SHEL, ARM, TM, SHOP, LVMH, BHP,
##     Santander, TotalEnergies, etc.)
##   - Duplicados de clase de accion (GOOG vs GOOGL, BRK-A vs BRK-B)
##   - Acciones preferentes/depositarias (JPM-PC, BAC-PB, BML-P*, etc.)
##   - "SPCX" (dato de mercado no fiable / sin flotante publico real)
##
## El umbral de 200B y la composicion cambian con el precio de mercado; esta
## lista quedara desactualizada con el tiempo. Editala directamente o usa
## --tickers=archivo.csv para tu propia lista.
const DefaultUsMegaCapTickers*: seq[string] = @[
  # Technology
  "NVDA", "AAPL", "MSFT", "AVGO", "ORCL", "CSCO", "AMAT", "LRCX", "KLAC",
  "DELL", "PANW", "CRWD", "ANET", "IBM", "MRVL", "INTC", "PLTR", "AMD", "TXN",
  # Communication Services
  "GOOGL", "META", "NFLX",
  # Consumer Cyclical
  "AMZN", "TSLA", "HD",
  # Financial Services
  "BRK-B", "V", "JPM", "MA", "BAC", "MS", "GS", "WFC", "AXP", "C",
  # Healthcare
  "LLY", "UNH", "JNJ", "ABBV", "MRK", "AMGN", "TMO",
  # Energy
  "XOM", "CVX",
  # Consumer Defensive
  "WMT", "COST", "PG", "KO", "PM",
  # Industrials
  "CAT", "GE", "GEV", "RTX",
]

proc loadTickersFromFile*(path: string): seq[string] =
  ## Carga tickers desde un archivo de texto, uno por linea.
  ## Ignora lineas vacias y las que empiezan con '#'.
  result = @[]
  for line in lines(path):
    let t = line.strip()
    if t.len > 0 and not t.startsWith("#"):
      result.add(t)
