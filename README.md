# DriftFolio

Script en [Nim](https://nim-lang.org/documentation.html) que descarga precios históricos desde Yahoo Finance, calcula un **ranking de momentum** para tres universos de activos y construye un **portafolio óptimo (Markowitz)** sobre el universo de mega-cap de EEUU.

- **Acciones chilenas (IPSA)**: CHILE, BSANTANDER, BCI, ITAUCL, SQM-B, LTM, FALABELLA, CENCOSUD, COPEC, CMPC, ENELCHILE, COLBUN, PARAUCO, MALLPLAZA, ANDINA-B, CCU, CAP, VAPORES, ILC, ENTEL.
- **ETFs de Vanguard**: VOO, VTI, VEA, VWO, VXUS, BND, VNQ, VIG, VUG, VTV, VOOG, VOOV, VB, VO, VGT, VHT, VFH, VDE, VAW, VCR, VPL.
- **Mega-cap EEUU**: se descarga dinámicamente (no hardcodeado) desde el CSV de holdings del ETF **iShares S&P 100 (OEF)**, filtrando solo posiciones de renta variable de EEUU (~100 tickers: NVDA, AAPL, MSFT, AMZN, GOOGL, ...).

Las listas de Chile y Vanguard son editables sin recompilar: ver [Universos configurables](#universos-configurables-m-001).

Cada corrida de `driftfolio` también calcula un **análisis fundamental** (P/E, ROE, márgenes, deuda, dividend yield, etc.) de esos mismos universos de Chile y EEUU; es un flujo independiente del ranking de momentum (otra fuente de datos, otras métricas) y genera su propio reporte HTML aparte — ver [Análisis fundamental](#análisis-fundamental). Todas las salidas de una corrida (los dos reportes HTML, sus CSV y un `index.html` que los enlaza) quedan juntas en una carpeta propia `output/<fecha-hora>/`.

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

### Descargas: paralelas, con reintentos, timeout y caché

Las ~175 descargas de precios (3 universos + histórico de 5 años para Markowitz) no son secuenciales: se despachan en pipeline, una petición nueva cada 200ms (el mismo ritmo que antes evitaba el rate-limiting de Yahoo Finance), pero sin esperar a que cada respuesta vuelva antes de lanzar la siguiente. Una corrida completa sin caché toma **menos de un minuto** en vez de los varios minutos de la versión secuencial original.

- **Timeout**: ninguna petición espera más de 15 segundos; una conexión colgada ya no cuelga el programa entero.
- **Reintentos**: si Yahoo Finance responde con rate-limit (429) o un error de servidor (5xx), o si la petición hace timeout, se reintenta hasta 3 veces con backoff (500ms, 1s). Un ticker inválido (4xx que no es 429) no se reintenta, porque reintentarlo no cambia el resultado.
- **Caché por día**: cada combinación ticker/ventana de histórico se guarda en `.driftfolio_cache/` (no se sube al repo). Si corrés el programa varias veces el mismo día, los precios ya descargados se leen de ahí en vez de volver a pedirlos — una segunda corrida el mismo día toma bajo un segundo. Para forzar una descarga real (ignorando lo cacheado hoy), usá `./driftfolio.exe --no-cache`. El análisis fundamental no tiene este caché: siempre descarga de nuevo, con o sin `--no-cache`.

### Portafolio Markowitz (sobre el top-15 momentum de mega-cap EEUU)

Tomando el top-15 por score de momentum del universo mega-cap, se construye el portafolio de mejor Sharpe:

- **μ (retorno esperado)**: proxy = score de momentum (ventana corta, refleja el régimen reciente).
- **Σ (covarianza de riesgo)**: calculada sobre **5 años** de retornos diarios con **EWMA** (RiskMetrics, λ=0.94), que da más peso a los días recientes sin descartar la historia larga — necesaria porque con ~15-100 activos y solo 1 año de datos la covarianza estimada es demasiado ruidosa.
- **Tasa libre de riesgo**: se descarga `^IRX` (letra del Tesoro de EEUU a 13 semanas) y se usa para calcular retornos en exceso (`μ - rf`), como exige la fórmula de máximo Sharpe.
- Se muestran **dos portafolios**:
  - **Sin restricciones (teórico)**: `w ∝ Σ⁻¹(μ-rf)`, solución cerrada vía sistema lineal. Puede asignar pesos negativos (posiciones en corto, no ejecutables en un bróker normal) — la tabla los muestra igual que los positivos, para que el lector vea el portafolio completo que calculó el modelo.
  - **Long-only, tope por posición (ejecutable en un bróker normal)**: mismo objetivo (máximo Sharpe) pero con `0 ≤ w_i ≤ tope` y `Σw_i = 1`. Al no tener solución cerrada, se resuelve con *projected gradient ascent* sobre el simplex capado (proyección por bisección/water-filling). Si quedan pocos activos con histórico suficiente, el tope sube automáticamente al mínimo que permite que los pesos sumen 100% (y queda registrado en el log si eso pasó).
- Para cada portafolio se imprime retorno esperado, volatilidad anualizada y Sharpe ratio.

### Exportación y logging

- **Carpeta por corrida**: cada ejecución crea `output/<yyyy-MM-dd_HH-mm-ss>/` y deja ahí **todas** sus salidas (nada se escribe en la raíz del proyecto ni se sobrescribe entre corridas): `driftfolio_resultados.csv`, `driftfolio_resultados.html`, `analisis_fundamental_resultados.html`, `analisis_fundamental_ipsa.csv`, `analisis_fundamental_us.csv` e `index.html`.
- **CSV**: `driftfolio_resultados.csv` trae los resultados de los 3 universos de momentum (`fecha,universo,ticker,ret1m,ret3m,ret6m,score,precio,sma50,sobre_sma50`), pensado para alimentar otro análisis o modelo.
- **Log de errores**: todo error o advertencia (fallo de descarga de un ticker, histórico insuficiente para Markowitz, etc.) se acumula durante la corrida y se vuelca al final con timestamp (con milisegundos, ej. `[2026-10-17 21:24:44.403]`) a `driftfolio_errors.log`, en la raíz del proyecto (modo *append*, histórico entre corridas, no va dentro de `output/`) además de mostrarse en consola. Los milisegundos ayudan a distinguir y ordenar errores que caen dentro del mismo segundo, algo frecuente con las descargas concurrentes (ver [Descargas](#descargas-paralelas-con-reintentos-timeout-y-caché)).

## Análisis fundamental

Cada corrida de `./driftfolio.exe` calcula, además del ranking de momentum, un análisis fundamental de IPSA y mega-caps EEUU (scoring de P/E, P/B, EV/EBITDA, PEG, ROE, ROA, márgenes, deuda, liquidez, crecimiento, dividend yield y FCF yield, comparado primero contra el sector de cada empresa). Es un flujo aparte dentro del mismo binario — distinta fuente de datos (`quoteSummary` de Yahoo Finance en vez de precios históricos) y sin código compartido con el ranking/Markowitz — orquestado por `src/driftfolio/fundamentalrunner.nim` después de terminar el flujo de momentum.

Dentro de la carpeta `output/<fecha-hora>/` de esa corrida deja `analisis_fundamental_resultados.html` y un CSV por universo (`analisis_fundamental_ipsa.csv`, `analisis_fundamental_us.csv`) — archivos separados de los de momentum: los dos análisis nunca se mezclan en el mismo reporte.

**`index.html`** es la página principal de esa misma carpeta: enlaza ambos reportes (`driftfolio_resultados.html` y `analisis_fundamental_resultados.html`) desde un solo lugar. La genera `src/driftfolio/indexreport.nim` al final de cada corrida — ábrela directamente en el navegador para navegar entre los dos.

### Diseño compartido, tema claro/oscuro y mobile

Las tres páginas de una corrida (`driftfolio_resultados.html`, `analisis_fundamental_resultados.html`, `index.html`) comparten un mismo diseño — colores, masthead, quicknav, tipografía, tablas con scroll horizontal — definido una sola vez en `src/theme.nim` e importado por los tres generadores, para que se sientan como una sola aplicación en vez de tres reportes sueltos.

- **Tema claro/oscuro**: cada página trae un botón flotante (arriba a la derecha) que alterna el tema y lo guarda en `localStorage`; por defecto sigue la preferencia del sistema operativo (`prefers-color-scheme`), pero el botón la sobreescribe. La elección se recuerda entre visitas a esa misma carpeta `output/<fecha-hora>/` (cada carpeta es su propio origen de `localStorage`, así que no se comparte entre corridas distintas).
- **Mobile**: layout responsive con breakpoint a 640px (masthead, quicknav y botón de tema se reacomodan) y cada tabla vive dentro de un contenedor con scroll horizontal propio, así que una tabla ancha nunca rompe el layout de la página en una pantalla angosta.
- **Navegación tipo SPA**: en `driftfolio_resultados.html` y `analisis_fundamental_resultados.html`, el quicknav de arriba (ej. los 4 ítems de la página de momentum: IPSA, Vanguard, mega-cap, Markowitz) funciona como pestañas — clickear uno muestra solo esa sección en el mismo body, sin recargar la página. Soporta deep-link por `#hash` (compartible, entra directo en esa pestaña) y funciona igual sin JavaScript (la primera pestaña ya viene marcada activa en el HTML generado). Implementado en `src/theme.nim` (`renderPage` + `TabScript`), reusado por ambos reportes.

## Universos configurables (M-001)

Las listas de Chile y Vanguard están embebidas en el binario como *default*, así que driftfolio funciona sin ninguna configuración. Para editarlas sin recompilar, creá un `universes.json` en el directorio desde donde ejecutás driftfolio:

```json
{
  "chile": ["CHILE.SN", "BSANTANDER.SN", "SQM-B.SN"],
  "vanguard": ["VOO", "VTI", "VXUS"]
}
```

Cualquier clave ausente (o que no sea una lista) conserva el default embebido para esa clave. Si el archivo existe pero no se puede parsear, se usan los defaults completos y queda registrado en `driftfolio_errors.log`. El mega-cap EEUU no es configurable acá porque se descarga dinámicamente del CSV de iShares.

`universes.json` controla **qué tickers** entran en cada universo. Para controlar **qué universos correr** y los parámetros del modelo (pesos, ventanas, SMA, Markowitz), ver la siguiente sección.

## Parámetros del modelo configurables (M-006)

Los pesos del score, las ventanas de retorno, el período de SMA y los parámetros de Markowitz (topN, años de histórico, λ de la EWMA, tope por posición, tamaño y tope del portafolio concentrado) se leen de `driftfolio.config.json` en el directorio de ejecución, si existe. Sin ese archivo, driftfolio usa los valores de fábrica (los mismos que documenta este README).

```sh
driftfolio --reset-config
```

Escribe (o sobrescribe) `driftfolio.config.json` con los valores de fábrica, listo para editar:

```json
{
  "universos": { "chile": true, "vanguard": true, "megaCap": true },
  "score": {
    "ret1mDias": 21, "ret3mDias": 63, "ret6mDias": 126,
    "ret1mPeso": 0.2, "ret3mPeso": 0.4, "ret6mPeso": 0.4,
    "smaPeriodo": 50, "historiaMinimaDias": 130
  },
  "markowitz": {
    "topN": 15, "historicoAnios": 5, "ewmaLambda": 0.94,
    "topePorPosicion": 0.2, "concentradoN": 4, "concentradoTope": 0.4
  }
}
```

- `universos.*`: en `false`, ese universo no corre (ni aparece en consola, CSV ni HTML). Desactivar `megaCap` también desactiva la sección Markowitz, porque depende de ese universo.
- Cada campo se valida por separado al cargar: uno inválido (negativo, fuera de rango, etc.) cae en su valor de fábrica y queda registrado en `driftfolio_errors.log`; el resto del archivo se respeta igual. Si `historiaMinimaDias` queda por debajo de `ret6mDias + 1`, se ajusta automáticamente (si no, el retorno a 6 meses daría 0 para casi todos los tickers).
- Los textos dinámicos de consola (`>SMA{smaPeriodo}`, `Score = X% × ... `) reflejan los valores configurados. Los encabezados de columna del CSV (`sma50`, `sobre_sma50`) y del reporte HTML se mantienen fijos aunque cambies `smaPeriodo`: son nombres de campo estables para quien consuma el CSV programáticamente, no una descripción literal del período.

## Requisitos

- [Nim](https://nim-lang.org/install.html) (probado con la versión 2.2.x)
- Conexión a internet (consume la API pública de Yahoo Finance y el CSV público de holdings de iShares)
- OpenSSL disponible en el sistema (ver sección de compilación)

No usa dependencias externas: solo módulos de la librería estándar (`std/httpclient`, `std/asyncdispatch`, `std/json`, `std/strutils`, `std/times`, `std/algorithm`, `std/strformat`, `std/sequtils`, `std/terminal`, `std/parsecsv`, `std/streams`, `std/os`, `std/math`, `std/net`, `std/unittest`).

## Estructura del proyecto

Paquete Nimble con un módulo por responsabilidad, para que agregar un universo, una métrica o un reporte nuevo no implique tocar un archivo de 900+ líneas:

```
driftfolio.nimble        # manifiesto del paquete (bin: driftfolio, deps, task test)
output/<fecha-hora>/      # salidas de cada corrida (generado; no versionado, ver .gitignore)
src/driftfolio.nim       # entry point async: crea output/<fecha-hora>/, orquesta momentum+Markowitz,
                          # luego el análisis fundamental, y por último index.html
src/theme.nim             # diseño compartido por los 3 reportes: colores, masthead, quicknav,
                          # tablas, botón de tema claro/oscuro, breakpoints mobile
src/driftfolio/
  types.nim              # tipo Quote
  errorlog.nim           # logging de errores (buffer en memoria + flush a driftfolio_errors.log)
  config.nim             # parámetros del modelo (defaults embebidos + driftfolio.config.json opcional)
  universes.nim          # listas de tickers (defaults embebidos + universes.json opcional)
  marketdata.nim         # I/O async: Yahoo Finance e iShares, con timeout/retry/caché
  analytics.nim          # cálculos puros: retornos, SMA, score de momentum
  display.nim            # salida por consola: colores, barra de progreso, tabla de pesos
  ranking.nim            # orquesta el ranking de un universo (pipeline de descargas + tabla)
  csvexport.nim          # exportación a CSV
  htmlreport.nim         # plantillas y generación del reporte HTML de momentum (Chart.js)
  linalg.nim             # álgebra lineal genérica (sistema lineal, proyección sobre simplex)
  markowitz.nim          # covarianza EWMA, optimización del portafolio, orquestación Markowitz
  fundamentalrunner.nim  # orquesta el análisis fundamental (descarga + scoring + CSV + HTML) dentro de driftfolio.exe
  indexreport.nim        # genera el index.html que enlaza los dos reportes de una corrida
src/fundamental/
  tickers.nim            # listas de tickers IPSA y mega-cap EEUU para el análisis fundamental
  yahoofinance.nim       # cliente de quoteSummary de Yahoo Finance (sesión, crumb, descargas paralelas)
  scoring.nim            # z-scores por sector (con respaldo global), winsorizados, reescalados 0-100
  htmlreport.nim         # plantilla y generación de analisis_fundamental_resultados.html
tests/
  test_analytics.nim           # calcReturn, calcSMA, momentumScore, buildQuote
  test_linalg.nim               # solveLinearSystem, projectCappedSimplex, subMatrix
  test_marketdata_parsing.nim   # parseAdjClosePrices con JSON sintético (sin red)
  test_universes.nim            # loadUniverses: defaults, archivo válido/parcial/inválido
  test_config.nim               # loadConfig: defaults, archivo válido/parcial/inválido, validación de rangos
```

`analytics.nim`, `linalg.nim` y la función `marketdata.parseAdjClosePrices` son puros (sin I/O), lo que permite testearlos de forma aislada; el resto de los módulos separan I/O (`marketdata`, `csvexport`, `htmlreport`) de orquestación (`ranking`, `markowitz`, `src/driftfolio.nim`).

## Compilar y ejecutar

```sh
nimble build -d:release
./driftfolio.exe
```

Una sola corrida de `driftfolio.exe` hace todo: momentum + Markowitz primero, análisis fundamental después, y deja todo listo en su propia carpeta `output/<fecha-hora>/`. Abrí el `index.html` de esa carpeta en el navegador para navegar entre los dos reportes.

Opciones de línea de comandos:

```sh
./driftfolio.exe --no-cache       # ignora el caché de precios de hoy, vuelve a descargar todo
./driftfolio.exe --reset-config   # escribe driftfolio.config.json con los valores de fábrica y termina
./driftfolio.exe --help           # muestra la ayuda y termina
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

Corre los tests unitarios de las funciones puras del proyecto (`analytics`, `linalg`, `marketdata.parseAdjClosePrices`, `universes.loadUniverses`, `config.loadConfig`).

La corrida completa (3 universos + el histórico de 5 años para Markowitz, ~175 descargas en total) toma menos de un minuto sin caché; con caché del mismo día, menos de un segundo (ver [Descargas](#descargas-paralelas-con-reintentos-timeout-y-caché)).

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

Resultados exportados a output/2026-01-15_09-30-00/driftfolio_resultados.csv
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
