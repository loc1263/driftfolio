## Genera la página principal (index.html) de una corrida: enlaza, desde un
## solo lugar, los dos reportes independientes que deja esa corrida en su
## carpeta output/<fecha-hora>/ (driftfolio_resultados.html y
## analisis_fundamental_resultados.html). Reusa el mismo diseño, toggle de
## tema y breakpoints mobile que esos dos reportes (ver ../theme).

import std/strutils
import ../theme

const ExtraStyle = """
  body { padding: 48px 16px; }
  .wrap { max-width: 880px; }
  .logo-mark { width: 44px; height: 44px; border-radius: 12px; font-size: 0.85rem; }
  h1 { font-size: 1.6rem; }
  .tagline { color: var(--muted); font-size: 0.95rem; margin: 10px 0 6px; max-width: 560px; }

  .cards { display: grid; grid-template-columns: repeat(2, 1fr); gap: 18px; }
  @media (max-width: 680px) { .cards { grid-template-columns: 1fr; } }

  .card {
    background: var(--panel); border: 1px solid var(--border); border-radius: 14px;
    padding: 22px 24px; box-shadow: var(--shadow); text-decoration: none; color: var(--text);
    display: flex; flex-direction: column; gap: 10px; transition: border-color 0.15s ease;
  }
  .card:hover { border-color: var(--accent); }
  .card .icon {
    width: 36px; height: 36px; border-radius: 9px; background: var(--accent-soft);
    color: var(--accent); display: flex; align-items: center; justify-content: center;
    font-size: 1.15rem;
  }
  .card h2 { font-size: 1.1rem; margin: 0; }
  .card p { font-size: 0.86rem; color: var(--muted); margin: 0; line-height: 1.5; }
  .card .cta { font-size: 0.8rem; font-weight: 700; color: var(--accent); margin-top: auto; }

  @media (max-width: 640px) { body { padding: 64px 10px 40px; } }
"""

const PageTemplate = """
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>DriftFolio</title>
$themeinit
<style>
$themevars
$themebase
$extrastyle
</style>
</head>
<body>
$togglebutton
<div class="wrap">
  <div class="masthead">
    <div class="logo-mark">DF</div>
    <h1>DriftFolio</h1>
  </div>
  <p class="tagline">Dos análisis independientes sobre los mismos universos de acciones: momentum/portafolio y fundamentales. Cada uno corre por su cuenta y genera su propio reporte HTML.</p>
  <p class="meta">Generado el $generatedAt</p>

  <div class="cards">
    <a class="card" href="driftfolio_resultados.html">
      <div class="icon">&#8599;</div>
      <h2>Momentum + Markowitz</h2>
      <p>Ranking de momentum (retornos 1M/3M/6M + filtro de media móvil) sobre acciones chilenas, ETFs Vanguard y mega-cap EE.UU., más el portafolio óptimo de Markowitz (máximo Sharpe) sobre el top del universo mega-cap.</p>
      <span class="cta">Ver reporte &rarr;</span>
    </a>
    <a class="card" href="analisis_fundamental_resultados.html">
      <div class="icon">&#9776;</div>
      <h2>Análisis fundamental</h2>
      <p>Scoring fundamental (P/E, P/B, EV/EBITDA, ROE, márgenes, deuda, crecimiento, dividend yield, FCF yield) del IPSA y las mega-caps de EE.UU., comparado contra el sector de cada empresa.</p>
      <span class="cta">Ver reporte &rarr;</span>
    </a>
  </div>

  <footer>
    Esta página y los dos reportes que enlaza pertenecen a una misma corrida de <code>driftfolio.exe</code>, guardada en su propia carpeta <code>output/&lt;fecha-hora&gt;/</code>. Ninguno de los dos análisis es una recomendación de inversión.
  </footer>
</div>
$togglescript
</body>
</html>
"""

proc writeIndexHtml*(path: string, generatedAt: string) =
  let html = PageTemplate.multiReplace(
    ("$themeinit", ThemeInitScript),
    ("$themevars", ThemeVars),
    ("$themebase", ThemeBase),
    ("$extrastyle", ExtraStyle),
    ("$togglebutton", ThemeToggleButtonHtml),
    ("$generatedAt", generatedAt),
    ("$togglescript", ThemeToggleScript)
  )
  writeFile(path, html)
