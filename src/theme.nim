## Diseño compartido entre los reportes HTML del proyecto (momentum,
## análisis fundamental e index.html): mismas variables de color, mismo
## layout base (masthead, quicknav, tablas, footer), mismo botón de
## claro/oscuro y mismos breakpoints para mobile. Cada reporte importa esto
## y le agrega encima solo el CSS específico de su propio contenido (charts,
## columnas sticky, badges, etc.), para que los tres se vean como una sola
## aplicación en vez de tres páginas sueltas.

import std/strutils

proc slugify*(s: string): string =
  for c in s.toLowerAscii():
    if c in {'a'..'z', '0'..'9'}:
      result.add(c)
    elif result.len > 0 and result[^1] != '-':
      result.add('-')
  result = result.strip(chars = {'-'})

## Variables de color (claro por defecto, oscuro por `prefers-color-scheme`)
## más el override manual vía `data-theme` que controla el botón de tema:
## `:root:not([data-theme="light"])` dentro del media query evita que un
## usuario que eligió "claro" a mano vuelva a oscuro solo porque el SO está
## en modo oscuro; `:root[data-theme="dark"]` fuerza oscuro aunque el SO
## esté en claro.
const ThemeVars* = """
  :root {
    color-scheme: light dark;
    --bg: #f4f6f9; --panel: #ffffff; --border: #e1e4ea; --text: #161a22;
    --muted: #636d7e; --accent: #1a5fd6; --accent-soft: #e8f0fe;
    --pos: #157f4a; --neg: #c0392b; --head: #eef1f6; --row-alt: #fafbfd;
    --good: #1f9d55; --mid: #c9892b; --low: #c0392b;
    --shadow: 0 1px 2px rgba(20, 24, 32, 0.04), 0 8px 24px rgba(20, 24, 32, 0.05);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --bg: #0f1115; --panel: #171a21; --border: #2a2f3a; --text: #e7e9ee;
      --muted: #96a0b2; --accent: #6ea8ff; --accent-soft: #1c2b4d;
      --pos: #3fbf7f; --neg: #ef6b5e; --head: #1d212b; --row-alt: #14171e;
      --good: #3fbf7f; --mid: #e0a847; --low: #ef6b5e;
      --shadow: 0 1px 2px rgba(0, 0, 0, 0.3), 0 8px 24px rgba(0, 0, 0, 0.35);
    }
  }
  :root[data-theme="dark"] {
    --bg: #0f1115; --panel: #171a21; --border: #2a2f3a; --text: #e7e9ee;
    --muted: #96a0b2; --accent: #6ea8ff; --accent-soft: #1c2b4d;
    --pos: #3fbf7f; --neg: #ef6b5e; --head: #1d212b; --row-alt: #14171e;
    --good: #3fbf7f; --mid: #e0a847; --low: #ef6b5e;
    --shadow: 0 1px 2px rgba(0, 0, 0, 0.3), 0 8px 24px rgba(0, 0, 0, 0.35);
  }
"""

## Layout base común: masthead, quicknav, tablas con scroll horizontal
## (mobile), footer. Cada reporte agrega su propio CSS extra a continuación
## de esto para lo que le sea específico (charts, columnas sticky, badges...).
const ThemeBase* = """
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 28px 16px 56px; background: var(--bg); color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  .wrap { max-width: 1320px; margin: 0 auto; }
  .masthead { display: flex; align-items: center; gap: 14px; margin-bottom: 6px; }
  .logo-mark {
    flex: 0 0 auto; width: 40px; height: 40px; border-radius: 10px;
    background: linear-gradient(135deg, var(--accent), #6ea8ff);
    color: #fff; font-weight: 700; font-size: 0.8rem; letter-spacing: 0.02em;
    display: flex; align-items: center; justify-content: center;
    text-decoration: none; transition: opacity 0.15s ease;
  }
  .logo-mark:hover { opacity: 0.85; text-decoration: none; }
  h1 { font-size: 1.4rem; margin: 0; letter-spacing: -0.01em; }
  .meta { color: var(--muted); font-size: 0.82rem; margin: 6px 0 18px; }
  .quicknav { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 30px; }
  .quicknav a {
    display: inline-block; padding: 6px 14px; border-radius: 999px; font-size: 0.8rem;
    font-weight: 600; text-decoration: none; color: var(--accent); background: var(--accent-soft);
    border: 1px solid transparent;
  }
  .quicknav a:hover { border-color: var(--accent); }
  .quicknav a.active { background: var(--accent); color: #fff; }
  h2 { font-size: 1.15rem; margin: 0 0 2px; border-left: 4px solid var(--accent); padding-left: 10px; }
  .subtitle, .muted { color: var(--muted); font-size: 0.82rem; }
  section { margin-bottom: 44px; }

  .tab-panel { display: none; }
  .tab-panel.active { display: block; }

  .table-wrap {
    overflow-x: auto; border: 1px solid var(--border); border-radius: 10px;
    background: var(--panel); box-shadow: var(--shadow);
  }
  table { border-collapse: collapse; width: 100%; font-size: 0.85rem; }
  thead th {
    background: var(--head); text-align: right; padding: 10px 12px; white-space: nowrap;
    border-bottom: 1px solid var(--border); position: sticky; top: 0; font-weight: 600;
    color: var(--muted); text-transform: uppercase; font-size: 0.68rem; letter-spacing: 0.03em;
    z-index: 2;
  }
  tbody td {
    padding: 8px 12px; border-bottom: 1px solid var(--border); text-align: right;
    white-space: nowrap; font-variant-numeric: tabular-nums;
  }
  tbody tr:nth-child(even) { background: var(--row-alt); }
  tbody tr:hover { background: var(--accent-soft); }
  a { color: var(--accent); text-decoration: none; font-weight: 600; }
  a:hover { text-decoration: underline; }
  .pos { color: var(--pos); }
  .neg { color: var(--neg); }

  footer {
    color: var(--muted); font-size: 0.8rem; line-height: 1.6; border-top: 1px solid var(--border);
    padding-top: 18px; margin-top: 28px;
  }
  footer strong { color: var(--text); }

  .theme-toggle {
    position: fixed; top: 16px; right: 16px; z-index: 50;
    width: 38px; height: 38px; border-radius: 50%; border: 1px solid var(--border);
    background: var(--panel); color: var(--text); font-size: 1rem; line-height: 1; cursor: pointer;
    display: flex; align-items: center; justify-content: center; box-shadow: var(--shadow);
    padding: 0;
  }
  .theme-toggle:hover { border-color: var(--accent); }
  .theme-toggle .icon-dark { display: none; }
  :root[data-theme="dark"] .theme-toggle .icon-light { display: none; }
  :root[data-theme="dark"] .theme-toggle .icon-dark { display: inline; }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) .theme-toggle .icon-light { display: none; }
    :root:not([data-theme="light"]) .theme-toggle .icon-dark { display: inline; }
  }

  @media (max-width: 640px) {
    body { padding: 64px 10px 40px; }
    h1 { font-size: 1.2rem; }
    .logo-mark { width: 34px; height: 34px; font-size: 0.7rem; }
    .theme-toggle { top: 10px; right: 10px; }
  }
"""

## Botón flotante de tema. Muestra los dos íconos superpuestos (CSS decide
## cuál se ve) para no depender de JS para pintar el ícono correcto antes de
## que corra el script de abajo.
const ThemeToggleButtonHtml* =
  """<button class="theme-toggle" id="theme-toggle" type="button" aria-label="Cambiar entre tema claro y oscuro" title="Cambiar tema">""" &
  "<span class=\"icon-light\">&#9728;</span><span class=\"icon-dark\">&#9789;</span></button>"

## Se ejecuta antes de pintar la página (va justo después de <meta
## viewport>, antes del <style>) para evitar el flash del tema equivocado:
## si el usuario ya eligió un tema a mano en una visita anterior, se aplica
## de inmediato en vez de esperar a que corra el resto del JS al final del body.
const ThemeInitScript* = """<script>
(function() {
  try {
    var saved = localStorage.getItem('driftfolio-theme');
    if (saved === 'light' || saved === 'dark') {
      document.documentElement.setAttribute('data-theme', saved);
    }
  } catch (e) {}
  // Saca el #hash de la URL ANTES de que el navegador pueda hacer su
  // scroll-to-anchor nativo (eso pasaría apenas exista en el DOM un
  // elemento con ese id, bien antes de que corra TabScript al final del
  // body) — si no, con las pestañas el deep-link entraría scrolleado a la
  // mitad de la pestaña en vez de arriba del todo. TabScript reactiva la
  // pestaña correcta a partir de window.__driftfolioInitialTab y repone el
  // hash en la URL con replaceState, que no dispara scroll.
  if (location.hash.length > 1) {
    window.__driftfolioInitialTab = location.hash.slice(1);
    try { history.replaceState(null, '', location.pathname + location.search); } catch (e) {}
  }
})();
</script>"""

const ThemeToggleScript* = """<script>
(function() {
  var btn = document.getElementById('theme-toggle');
  if (!btn) return;
  function current() {
    var attr = document.documentElement.getAttribute('data-theme');
    if (attr === 'light' || attr === 'dark') return attr;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  btn.addEventListener('click', function() {
    var next = current() === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    try { localStorage.setItem('driftfolio-theme', next); } catch (e) {}
  });
})();
</script>"""

## Convierte el quicknav de "links que hacen scroll a un ancla" en pestañas
## reales: solo un `.tab-panel` visible a la vez, sin recargar la página (el
## primero ya viene marcado `active` desde el HTML generado, así que
## funciona igual sin JS — esto solo agrega el cambio instantáneo al
## clickear y el deep-link por `#hash`).
const TabScript* = """<script>
(function() {
  var links = Array.prototype.slice.call(document.querySelectorAll('.quicknav a[data-tab]'));
  var panels = Array.prototype.slice.call(document.querySelectorAll('.tab-panel'));
  if (links.length === 0 || panels.length === 0) return;

  function activate(id) {
    var matched = false;
    for (var i = 0; i < panels.length; i++) {
      var isMatch = panels[i].id === id;
      panels[i].classList.toggle('active', isMatch);
      if (isMatch) matched = true;
    }
    if (!matched) return false;
    for (var j = 0; j < links.length; j++) {
      links[j].classList.toggle('active', links[j].getAttribute('data-tab') === id);
    }
    return true;
  }

  links.forEach(function(a) {
    a.addEventListener('click', function(e) {
      e.preventDefault();
      var id = a.getAttribute('data-tab');
      if (activate(id)) {
        history.replaceState(null, '', '#' + id);
        window.scrollTo(0, 0);
      }
    });
  });

  if (window.__driftfolioInitialTab && activate(window.__driftfolioInitialTab)) {
    history.replaceState(null, '', '#' + window.__driftfolioInitialTab);
    // Aunque ya sacamos el hash de la URL en ThemeInitScript antes de que
    // existiera el elemento destino, Chrome igual resuelve el scroll-to-
    // fragment de la navegación original de forma asíncrona (en 'load' o
    // después) — más robusto es dejar que pase y corregirlo acá, en vez de
    // tratar de impedirlo.
    window.addEventListener('load', function() { window.scrollTo(0, 0); });
  }
})();
</script>"""

## Armazón de página compartido por los reportes con secciones + quicknav
## (momentum y fundamental). index.html arma su propio body (tarjetas, no
## secciones) pero reusa ThemeVars/ThemeBase/Toggle* igual que este template.
const PageTemplate* = """
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>$title</title>
$themeinit
<style>
$themevars
$themebase
$extrastyle
</style>
$extrahead
</head>
<body>
$togglebutton
<div class="wrap">
  <div class="masthead">
    <a class="logo-mark" href="index.html" title="Volver al inicio">$logo</a>
    <h1>$h1</h1>
  </div>
  <div class="meta">$meta</div>
  <nav class="quicknav">
$navlinks
  </nav>
$sections
  <footer>
    $footer
  </footer>
</div>
$togglescript
$tabscript
</body>
</html>
"""

proc renderPage*(title, logo, h1, meta, footer: string,
                  sections: seq[tuple[label: string, html: string]],
                  extraStyle = "", extraHead = ""): string =
  var navLinks: seq[string]
  var sectionHtml: seq[string]
  for i, sec in sections:
    let slug = slugify(sec.label)
    let activeCls = if i == 0: " active" else: ""
    # El primer tab ya viene marcado `active` en el HTML generado (no
    # depende de que corra JS): sin JS, o si TabScript falla, la página
    # igual muestra algo coherente en vez de quedar en blanco o con todo
    # amontonado.
    navLinks.add("    <a href=\"#" & slug & "\" class=\"tab-link" & activeCls &
      "\" data-tab=\"" & slug & "\">" & sec.label & "</a>")
    sectionHtml.add("  <div class=\"tab-panel" & activeCls & "\" id=\"" & slug & "\">\n" &
      sec.html & "\n  </div>")

  PageTemplate.multiReplace(
    ("$title", title),
    ("$themeinit", ThemeInitScript),
    ("$themevars", ThemeVars),
    ("$themebase", ThemeBase),
    ("$extrastyle", extraStyle),
    ("$extrahead", extraHead),
    ("$togglebutton", ThemeToggleButtonHtml),
    ("$logo", logo),
    ("$h1", h1),
    ("$meta", meta),
    ("$navlinks", navLinks.join("\n")),
    ("$sections", sectionHtml.join("\n")),
    ("$footer", footer),
    ("$togglescript", ThemeToggleScript),
    ("$tabscript", TabScript)
  )
