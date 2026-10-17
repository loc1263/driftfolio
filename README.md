# DriftFolio

Script en [Nim](https://nim-lang.org/documentation.html) que descarga precios históricos desde Yahoo Finance, calcula un **ranking de momentum** para tres universos de activos y construye un **portafolio óptimo (Markowitz)** sobre el universo de mega-cap de EEUU.

- **Acciones chilenas (IPSA)**: CHILE, BSANTANDER, BCI, ITAUCL, SQM-B, LTM, FALABELLA, CENCOSUD, COPEC, CMPC, ENELCHILE, COLBUN, PARAUCO, MALLPLAZA, ANDINA-B, CCU, CAP, VAPORES, ILC, ENTEL.
- **ETFs de Vanguard**: VOO, VTI, VEA, VWO, VXUS, BND, VNQ, VIG, VUG, VTV, VOOG, VOOV, VB, VO, VGT, VHT, VFH, VDE, VAW, VCR, VPL.
- **Mega-cap EEUU**: se descarga dinámicamente (no hardcodeado) desde el CSV de holdings del ETF **iShares S&P 100 (OEF)**, filtrando solo posiciones de renta variable de EEUU (~100 tickers: NVDA, AAPL, MSFT, AMZN, GOOGL, ...).

## Qué hace

### Ranking de momentum (los 3 universos)

Para cada ticker:

1. Descarga ~1 año de precios de cierre ajustado desde la API de Yahoo Finance (`query1.finance.yahoo.com`).
2. Calcula los retornos a 1 mes (21 días), 3 meses (63 días) y 6 meses (126 días).
3. Calcula la media móvil simple de 50 días (SMA50) y si el precio actual está por sobre ella (dato informativo, no filtra resultados).
4. Calcula un **score de momentum**:

   ```
   score = 0.20 × retorno 1M + 0.40 × retorno 3M + 0.40 × retorno 6M
   ```

5. Ordena los activos de cada universo por score descendente y los imprime en una tabla por consola, con colores (retornos/score en verde si son positivos, rojo si son negativos; columna `>SMA50` en verde cuando es "Sí").

Los tickers con menos de 130 precios disponibles se descartan (no hay suficiente historia para calcular retorno a 6M y SMA50). Mientras corre, se muestra una barra de progreso por ticker (en consola interactiva se sobrescribe en una sola línea; si la salida está redirigida a un archivo, se imprime una línea por ticker).

### Portafolio Markowitz (sobre el top-15 momentum de mega-cap EEUU)

Tomando el top-15 por score de momentum del universo mega-cap, se construye el portafolio de mejor Sharpe:

- **μ (retorno esperado)**: proxy = score de momentum (ventana corta, refleja el régimen reciente).
- **Σ (covarianza de riesgo)**: calculada sobre **5 años** de retornos diarios con **EWMA** (RiskMetrics, λ=0.94), que da más peso a los días recientes sin descartar la historia larga — necesaria porque con ~15-100 activos y solo 1 año de datos la covarianza estimada es demasiado ruidosa.
- **Tasa libre de riesgo**: se descarga `^IRX` (letra del Tesoro de EEUU a 13 semanas) y se usa para calcular retornos en exceso (`μ - rf`), como exige la fórmula de máximo Sharpe.
- Se muestran **dos portafolios**:
  - **Sin restricciones (teórico)**: `w ∝ Σ⁻¹(μ-rf)`, solución cerrada vía sistema lineal. Puede asignar pesos negativos (posiciones en corto) — no es ejecutable en un bróker normal.
  - **Long-only, tope 20% por posición (ejecutable en un bróker normal)**: mismo objetivo (máximo Sharpe) pero con `0 ≤ w_i ≤ 20%` y `Σw_i = 1`. Al no tener solución cerrada, se resuelve con *projected gradient ascent* sobre el simplex capado (proyección por bisección/water-filling).
- Para cada portafolio se imprime retorno esperado, volatilidad anualizada y Sharpe ratio.

### Exportación y logging

- **CSV**: al final de cada corrida se exporta `driftfolio_resultados.csv` con los resultados de los 3 universos (`fecha,universo,ticker,ret1m,ret3m,ret6m,score,precio,sma50,sobre_sma50`), pensado para alimentar otro análisis o modelo. Se sobrescribe en cada ejecución.
- **Log de errores**: todo error o advertencia (fallo de descarga de un ticker, histórico insuficiente para Markowitz, etc.) se registra con timestamp en `driftfolio_errors.log` (modo *append*, se acumula entre corridas) además de mostrarse en consola.

## Requisitos

- [Nim](https://nim-lang.org/install.html) (probado con la versión 2.2.x)
- Conexión a internet (consume la API pública de Yahoo Finance y el CSV público de holdings de iShares)
- OpenSSL disponible en el sistema (ver sección de compilación)

No usa dependencias externas: solo módulos de la librería estándar (`std/httpclient`, `std/json`, `std/strutils`, `std/times`, `std/algorithm`, `std/strformat`, `std/sequtils`, `std/terminal`, `std/parsecsv`, `std/streams`, `std/os`, `std/math`, `std/unittest`).

## Estructura del proyecto

Paquete Nimble con un módulo por responsabilidad, para que agregar un universo, una métrica o un reporte nuevo no implique tocar un archivo de 900+ líneas:

```
driftfolio.nimble        # manifiesto del paquete (bin, deps, task test)
src/driftfolio.nim       # entry point: orquesta todo el flujo (main)
src/driftfolio/
  types.nim              # tipo Quote
  errorlog.nim           # logging de errores (consola + driftfolio_errors.log)
  universes.nim          # listas de tickers fijas (Chile, Vanguard)
  marketdata.nim         # I/O: Yahoo Finance (precios, tasa libre de riesgo) e iShares (mega-cap)
  analytics.nim          # cálculos puros: retornos, SMA, score de momentum
  display.nim            # salida por consola: colores, barra de progreso, tabla de pesos
  ranking.nim            # orquesta el ranking de un universo (fetch + cálculo + tabla)
  csvexport.nim          # exportación a CSV
  htmlreport.nim         # plantillas y generación del reporte HTML (Chart.js)
  linalg.nim             # álgebra lineal genérica (sistema lineal, proyección sobre simplex)
  markowitz.nim          # covarianza EWMA, optimización del portafolio, orquestación Markowitz
tests/
  test_analytics.nim     # calcReturn, calcSMA, momentumScore, buildQuote
  test_linalg.nim        # solveLinearSystem, projectCappedSimplex, subMatrix
```

`analytics.nim` y `linalg.nim` son funciones puras (sin I/O), lo que permite testearlas de forma aislada; el resto de los módulos separan I/O (`marketdata`, `csvexport`, `htmlreport`) de orquestación (`ranking`, `markowitz`, `src/driftfolio.nim`).

## Compilar y ejecutar

```sh
nimble build -d:release
./driftfolio.exe
```

O directamente con `nim`:

```sh
nim c -r src/driftfolio.nim
```

El archivo `src/driftfolio.nim.cfg` fuerza siempre `-d:ssl` (requerido para consultar la API de Yahoo Finance por HTTPS), así que no es necesario pasarlo manualmente. Si falla con un error de SSL, verifica que las DLLs de OpenSSL estén disponibles en el `PATH` (en Windows).

### Tests

```sh
nimble test
```

Corre los tests unitarios de `analytics.nim` y `linalg.nim` (las funciones puras del proyecto).

La corrida completa (3 universos + el histórico de 5 años para Markowitz, ~140 tickers en total) toma varios minutos, ya que hay una pausa de 200ms entre cada descarga para evitar rate-limiting de Yahoo Finance.

## Ejemplo de salida

```
===============================================================================================
RANKING DE MOMENTUM - ACCIONES CHILENAS (IPSA)
Columna >SMA50 es informativa (no excluye activos)
===============================================================================================
#    Ticker           1M %     3M %     6M %     Score    Precio     SMA50   >SMA50
-----------------------------------------------------------------------------------------------
1    SQM-B             8.12    15.40    22.30    16.42    48.20     44.10      Sí
...
===============================================================================================
Total de activos: 20 | Sobre SMA50: 14

Score = 20% × Retorno 1M + 40% × Retorno 3M + 40% × Retorno 6M
>SMA50: Sí si el precio actual > SMA de 50 días (solo informativo)

Resultados exportados a driftfolio_resultados.csv
```

Y para la sección de Markowitz:

```
===============================================================================================
MARKOWITZ - MEJOR PORTAFOLIO (top 15 por momentum, covarianza EWMA 5 años)
===============================================================================================
Tasa libre de riesgo (^IRX, 13 semanas): 4.07%

--- Sin restricciones (teórico, permite posiciones en corto) ---
Ticker           Peso %
------------------------
NVDA              34.21
...
------------------------
Retorno esperado (proxy score momentum): 28.40%
Volatilidad anualizada (cov. EWMA): 22.10%
Sharpe (vs. tasa libre de riesgo): 1.10
Nota: pesos negativos implican posición corto, no ejecutable en un bróker normal.

--- Long-only, tope 20% por posición (ejecutable en un bróker normal) ---
Ticker           Peso %
------------------------
NVDA              20.00
...
------------------------
Retorno esperado (proxy score momentum): 24.15%
Volatilidad anualizada (cov. EWMA): 19.80%
Sharpe (vs. tasa libre de riesgo): 1.02
```

## Notas

- La API de Yahoo Finance no es oficial y puede cambiar o limitar las solicitudes sin aviso.
- Si un ticker falla al descargarse, se omite y se registra en `driftfolio_errors.log`; el resto del universo sigue procesándose.
- El score de momentum usado como μ no es un retorno anualizado propiamente dicho; es una aproximación práctica para capturar el régimen reciente. Si se necesita mayor rigor estadístico, conviene reemplazarlo por un retorno esperado anualizado y aplicar *shrinkage* (ej. Ledoit-Wolf) a la covarianza.
