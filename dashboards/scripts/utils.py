"""
utils.py — Shared utilities for Optimizely CS Leadership Dashboards
2026 Optimizely brand: Forest Green headers, Lime Green accents, Frost backgrounds, VC Nudge font.
"""

import json, os, re, textwrap
from pathlib import Path
from datetime import datetime

# ─── 2026 Brand Palette ───────────────────────────────────────────────────────
FOREST_GREEN = "#1A3D2B"   # Primary dark — headers, text, anchor color
LIME_GREEN   = "#AAEE44"   # Primary accent — CTAs, KPI borders, highlights
SKY_BLUE     = "#8ECFDB"   # Secondary accent
SOFT_PINK    = "#F0A0A8"   # Secondary accent / warmth
DEEP_TEAL    = "#2A6650"   # Mid-tone dark green
LIGHT_SAGE   = "#E8EEE0"   # Card tint
FROST        = "#EEF2E8"   # Section backgrounds
GREEN        = "#4A9A3C"   # Positive / retained
RED          = "#EF4444"   # Negative / churn
AMBER        = "#F59E0B"   # Neutral / on-target
PURPLE       = "#7A3D5A"   # Mauve accent
DARK         = "#1A3D2B"   # Body text = Forest Green
LIGHT_BG     = "#EEF2E8"   # Page background = Frost
CARD_BG      = "#FFFFFF"   # Card fills

# Backwards-compat aliases
BLUE   = FOREST_GREEN
ORANGE = SKY_BLUE
CYAN   = SKY_BLUE
TEAL   = DEEP_TEAL

CHART_PALETTE = [FOREST_GREEN, LIME_GREEN, SKY_BLUE, SOFT_PINK, DEEP_TEAL, AMBER, GREEN, PURPLE]

PLOTLY_CONFIG = dict(
    responsive=True,
    displayModeBar=True,
    modeBarButtonsToRemove=["pan2d", "lasso2d", "select2d", "toggleSpikelines"],
    toImageButtonOptions={"format": "svg", "filename": "chart"},
)

PLOTLY_LAYOUT_BASE = dict(
    font=dict(family="'VC Nudge', Inter, Arial, sans-serif", color=DARK, size=12),
    paper_bgcolor="rgba(0,0,0,0)",
    plot_bgcolor="rgba(0,0,0,0)",
    margin=dict(l=100, r=30, t=50, b=70),
    colorway=CHART_PALETTE,
    xaxis=dict(showgrid=False, zeroline=False),
    yaxis=dict(showgrid=True, gridcolor="#C8D4C0", zeroline=False, automargin=True),
    legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1),
    hoverlabel=dict(
        bgcolor=FOREST_GREEN,
        bordercolor=LIME_GREEN,
        font=dict(color="#FFFFFF", size=12, family="'VC Nudge', Inter, Arial, sans-serif"),
    ),
)


# ─── Formatting helpers ────────────────────────────────────────────────────────
def fmt_arr(v):
    """Format dollar amount: $1.2M or $450K."""
    if v is None:
        return "N/A"
    v = float(v)
    if abs(v) >= 1_000_000:
        return f"${v/1_000_000:.1f}M"
    if abs(v) >= 1_000:
        return f"${v/1_000:.0f}K"
    return f"${v:,.0f}"

def fmt_pct(v, decimals=1):
    if v is None:
        return "N/A"
    return f"{float(v)*100:.{decimals}f}%"

def fmt_delta(v, is_arr=False, is_pct=False):
    """Return arrow + formatted delta string."""
    if v is None:
        return "—"
    v = float(v)
    arrow = "▲" if v > 0 else ("▼" if v < 0 else "→")
    color_cls = "pos" if v > 0 else ("neg" if v < 0 else "neu")
    if is_arr:
        val = fmt_arr(abs(v))
    elif is_pct:
        val = f"{abs(v)*100:.1f}pp"
    else:
        val = f"{abs(v):,.0f}"
    return f'<span class="delta {color_cls}">{arrow} {val}</span>'

def fmt_count(v):
    if v is None:
        return "N/A"
    return f"{int(v):,}"


# ─── HTML Boilerplate ─────────────────────────────────────────────────────────
PLOTLY_CDN = "https://cdn.plot.ly/plotly-latest.min.js"

def html_head(title: str, extra_css: str = "") -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title}</title>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@40,300,0,0" rel="stylesheet" />
<script src="{PLOTLY_CDN}"></script>
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap');
:root {{
  --forest:  {FOREST_GREEN};
  --lime:    {LIME_GREEN};
  --sky:     {SKY_BLUE};
  --pink:    {SOFT_PINK};
  --teal:    {DEEP_TEAL};
  --frost:   {FROST};
  --sage:    {LIGHT_SAGE};
  --green:   {GREEN};
  --red:     {RED};
  --amber:   {AMBER};
  --purple:  {PURPLE};
  --dark:    {DARK};
  --card:    {CARD_BG};
  --bg:      {LIGHT_BG};
}}
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ font-family: 'VC Nudge', Inter, Arial, sans-serif; background: var(--bg); color: var(--dark); }}

/* ── Header ── */
.top-bar {{
  background: var(--forest); color: #fff; padding: 14px 28px;
  display: flex; align-items: center; justify-content: space-between;
  position: sticky; top: 0; z-index: 100; box-shadow: 0 2px 8px rgba(0,0,0,.3);
}}
.top-bar h1 {{ font-size: 18px; font-weight: 700; letter-spacing: -0.3px; }}
.top-bar .quarter-badge {{
  background: var(--lime); color: var(--forest); padding: 4px 14px;
  border-radius: 20px; font-size: 13px; font-weight: 700;
}}

/* ── Layout ── */
.layout {{ display: flex; min-height: 100vh; }}
.sidebar {{
  width: 220px; background: #fff; border-right: 2px solid var(--sage);
  padding: 24px 0; position: sticky; top: 56px; height: calc(100vh - 56px);
  overflow-y: auto; flex-shrink: 0;
}}
.sidebar a {{
  display: block; padding: 9px 20px; font-size: 13px; color: var(--dark);
  text-decoration: none; border-left: 3px solid transparent;
  transition: all .15s;
}}
.sidebar a:hover, .sidebar a.active {{
  background: var(--frost); border-left-color: var(--lime); color: var(--forest);
  font-weight: 600;
}}
.main {{ flex: 1; padding: 28px; max-width: 1280px; overflow-x: hidden; }}

/* ── Section cards ── */
.section {{ margin-bottom: 32px; }}
.section h2 {{
  font-size: 16px; font-weight: 700; color: var(--forest);
  padding-bottom: 8px; border-bottom: 3px solid var(--lime);
  margin-bottom: 16px;
}}
.card {{
  background: var(--card); border-radius: 12px;
  box-shadow: 0 1px 4px rgba(0,0,0,.1); padding: 20px; margin-bottom: 16px;
}}

/* ── KPI tiles ── */
.kpi-grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(200px,1fr)); gap: 16px; }}
.kpi-card {{
  background: var(--card); border-radius: 12px;
  box-shadow: 0 1px 4px rgba(0,0,0,.1); padding: 18px 20px;
  border-left: 4px solid var(--lime);
}}
.kpi-card.green  {{ border-left-color: var(--green); }}
.kpi-card.red    {{ border-left-color: var(--red);   }}
.kpi-card.sky    {{ border-left-color: var(--sky);   }}
.kpi-card.teal   {{ border-left-color: var(--teal);  }}
.kpi-card.amber  {{ border-left-color: var(--amber); }}
.kpi-card.purple {{ border-left-color: var(--purple);}}
.kpi-card.orange {{ border-left-color: var(--sky);   }}
.kpi-label {{ font-size: 11px; font-weight: 600; color: #6B7280; text-transform: uppercase; letter-spacing: .5px; margin-bottom: 6px; }}
.kpi-value {{ font-size: 26px; font-weight: 700; color: var(--dark); margin-bottom: 4px; }}
.kpi-meta  {{ font-size: 12px; color: #9CA3AF; }}
.delta {{ font-size: 12px; font-weight: 600; }}
.delta.pos {{ color: var(--green); }}
.delta.neg {{ color: var(--red);   }}
.delta.neu {{ color: var(--amber); }}

/* ── Tabs ── */
.tab-bar {{ display: flex; gap: 4px; margin-bottom: 16px; flex-wrap: wrap; }}
.tab-btn {{
  padding: 6px 16px; border-radius: 20px; border: 1px solid var(--sage);
  background: #fff; cursor: pointer; font-size: 13px; color: #6B7280;
  transition: all .15s;
}}
.tab-btn.active {{ background: var(--forest); color: #fff; border-color: var(--forest); }}
.tab-pane {{ display: none; }}
.tab-pane.active {{ display: block; }}

/* ── Tables ── */
.table-wrap {{ overflow-x: auto; }}
table {{ width: 100%; border-collapse: collapse; font-size: 13px; }}
thead th {{
  background: var(--forest); color: #fff; padding: 10px 12px;
  text-align: left; font-weight: 600; position: sticky; top: 0; cursor: pointer;
}}
thead th:hover {{ background: var(--teal); }}
tbody tr:nth-child(even) {{ background: var(--frost); }}
tbody tr:hover {{ background: var(--sage); }}
tbody td {{ padding: 8px 12px; border-bottom: 1px solid #F3F4F6; }}

/* ── Download button ── */
.dl-btn {{
  display: inline-block; margin-top: 12px; padding: 7px 16px; border-radius: 8px;
  background: var(--forest); color: var(--lime); font-size: 12px; font-weight: 700;
  cursor: pointer; border: none; text-decoration: none;
}}
.dl-btn:hover {{ background: var(--teal); color: #fff; }}

/* ── Insights box ── */
.insight {{
  border-left: 4px solid var(--lime); background: var(--frost);
  padding: 12px 16px; border-radius: 0 12px 12px 0; font-size: 13px;
  color: var(--forest); margin-top: 12px; line-height: 1.6;
}}
.insight strong {{ color: var(--forest); }}

/* ── Period badge ── */
.period-badge {{
  display: inline-block; background: var(--lime); color: var(--forest);
  padding: 3px 12px; border-radius: 20px; font-size: 12px; font-weight: 700;
  margin-left: 10px; vertical-align: middle;
}}

/* ── Source footnote ── */
.source {{ font-size: 11px; color: #9CA3AF; margin-top: 8px; }}

/* ── Responsive ── */
@media (max-width: 768px) {{
  .sidebar {{ display: none; }}
  .kpi-grid {{ grid-template-columns: 1fr 1fr; }}
  .kpi-value {{ font-size: 20px; }}
}}

/* ── Print ── */
@media print {{
  .sidebar, .top-bar {{ display: none; }}
  .main {{ padding: 0; }}
  .card {{ box-shadow: none; border: 1px solid var(--sage); }}
}}
{extra_css}
</style>
</head>
"""

def html_topbar(title: str, quarter: str) -> str:
    return f"""<body>
<div class="top-bar">
  <h1>📊 {title}</h1>
  <span class="quarter-badge">{quarter}</span>
</div>
"""

def html_footer(sources: list = None) -> str:
    date_str = datetime.now().strftime("%d %b %Y")
    src = ""
    if sources:
        src = "<br>Sources: " + " · ".join(sources)
    return f"""
<footer style="text-align:center; padding:24px; font-size:12px; color:#9CA3AF; border-top:2px solid {LIME_GREEN}; margin-top:32px; background:{FROST};">
  Generated {date_str} | Optimizely CS Analytics{src}
</footer>
</body></html>"""

def sidebar_link(section_id: str, label: str) -> str:
    return f'<a href="#{section_id}">{label}</a>'

def download_table_js(table_id: str, filename: str) -> str:
    """Returns a JS function + button HTML to download a table as CSV."""
    return f"""
<button class="dl-btn" onclick="downloadCSV('{table_id}','{filename}.csv')">⬇ Download CSV</button>
<script>
function downloadCSV(tableId, fname) {{
  const tbl = document.getElementById(tableId);
  let csv = [];
  for (let row of tbl.rows) {{
    csv.push(Array.from(row.cells).map(c => '"' + c.innerText.replace(/"/g,'""') + '"').join(','));
  }}
  const blob = new Blob([csv.join('\\n')], {{type:'text/csv'}});
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob);
  a.download = fname; a.click();
}}
</script>"""


def plotly_chart(div_id: str, traces: list, layout_overrides: dict = None,
                 height: int = 380) -> str:
    """Returns the HTML+JS for an inline Plotly chart."""
    layout = {**PLOTLY_LAYOUT_BASE, "height": height, **(layout_overrides or {})}
    # Ensure yaxis automargin is always on
    if "yaxis" not in layout:
        layout["yaxis"] = {}
    layout["yaxis"]["automargin"] = True
    config = PLOTLY_CONFIG
    return f"""
<div id="{div_id}" style="width:100%;"></div>
<script>
Plotly.newPlot(
  '{div_id}',
  {json.dumps(traces)},
  {json.dumps(layout)},
  {json.dumps(config)}
);
</script>"""


def tab_switcher(tabs: dict, group: str = "tabs") -> str:
    """
    tabs: {label: content_html}
    Returns tab bar + panes HTML.
    """
    bar = '<div class="tab-bar">'
    panes = ""
    for i, (label, content) in enumerate(tabs.items()):
        tab_id = f"{group}_{i}"
        active = "active" if i == 0 else ""
        bar += f'<button class="tab-btn {active}" onclick="switchTab(\'{group}\',\'{tab_id}\')">{label}</button>'
        panes += f'<div class="tab-pane {active}" id="{tab_id}">{content}</div>'
    bar += "</div>"
    js = f"""
<script>
function switchTab(group, tabId) {{
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
  document.getElementById(tabId).classList.add('active');
  event.currentTarget.classList.add('active');
}}
</script>"""
    return bar + panes + js


# ─── Data loading ─────────────────────────────────────────────────────────────
def load_data(data_dir, query_name):
    """Load a JSON result file. Returns list of row dicts or None.
    Keys are normalised to lowercase so scripts work regardless of
    whether Snowflake returned UPPER or lower case column names."""
    path = Path(data_dir) / f"{query_name}.json"
    if not path.exists():
        print(f"[WARN] Missing data file: {path}")
        return None
    with open(path) as f:
        raw = json.load(f)
    if isinstance(raw, list):
        return [{k.lower(): v for k, v in row.items()} for row in raw]
    if isinstance(raw, dict):
        return {k.lower(): v for k, v in raw.items()}
    return raw

def save_html(content: str, output_dir, filename: str) -> Path:
    out = Path(output_dir) / filename
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(content, encoding="utf-8")
    print(f"[OK] Saved → {out}")
    return out


# ─── Table renderer ───────────────────────────────────────────────────────────
def render_table(rows: list, table_id: str, col_map: dict = None,
                 max_rows: int = None, sortable: bool = True) -> str:
    """
    Renders an HTML table.
    col_map: {original_col: display_name}  — also controls which cols to show
    """
    if not rows:
        return "<p style='color:#9CA3AF'>No data available.</p>"
    cols = list(col_map.keys()) if col_map else list(rows[0].keys())
    headers = [col_map.get(c, c) if col_map else c for c in cols]
    display_rows = rows[:max_rows] if max_rows else rows
    sort_js = f"""
<script>
(function(){{
  var tbl = document.getElementById('{table_id}');
  if (!tbl) return;
  var ths = tbl.querySelectorAll('th');
  ths.forEach(function(th, ci) {{
    var asc = true;
    th.addEventListener('click', function() {{
      var tbody = tbl.querySelector('tbody');
      var rows = Array.from(tbody.rows);
      rows.sort(function(a,b) {{
        var va = a.cells[ci].innerText.replace(/[$,%▲▼→]/g,'').trim();
        var vb = b.cells[ci].innerText.replace(/[$,%▲▼→]/g,'').trim();
        var na = parseFloat(va), nb = parseFloat(vb);
        if (!isNaN(na) && !isNaN(nb)) return asc ? na-nb : nb-na;
        return asc ? va.localeCompare(vb) : vb.localeCompare(va);
      }});
      rows.forEach(r => tbody.appendChild(r));
      asc = !asc;
    }});
  }});
}})();
</script>""" if sortable else ""

    html = f'<div class="table-wrap"><table id="{table_id}"><thead><tr>'
    for h in headers:
        html += f"<th>{h}</th>"
    html += "</tr></thead><tbody>"
    for row in display_rows:
        html += "<tr>"
        for c in cols:
            v = row.get(c)
            html += f"<td>{'' if v is None else v}</td>"
        html += "</tr>"
    html += f"</tbody></table></div>{sort_js}"
    if max_rows and len(rows) > max_rows:
        html += f'<p class="source" style="margin-top:6px">Showing top {max_rows} of {len(rows)} rows. Download CSV for full data.</p>'
    return html
