"""
02_breakdowns.py — Dimension Breakdowns Dashboard
==================================================
Uses data from:
  - 02_scorecard_dimensions.json  (ARR/Churn/RR by dimension)
  - 01_regional_trend.json        (NA & EMEA 4-quarter trend — reused from global snapshot)

Section order:
  Summary > Region > Territory > SFDC Segment > Revenue Segment >
  ARR Band > Solution Type > Product Solution > Product Group

Region section is special:
  - KPI tiles per region (Renewal ARR, Churn ARR, RR, Accounts up for renewal)
  - ARR/Churn horizontal bar chart
  - Renewal Rate shown as a line plot (scatter with markers)
  - Regional time trend chart (NA & EMEA, reused from 01_regional_trend.json)
  - No download table

All other dimensions:
  - Horizontal bar charts (ARR/Churn + RR colour-coded)
  - Download table

2026 Optimizely brand: Forest Green, Lime Green, Sky Blue, Deep Teal.
"""

import argparse, sys
from pathlib import Path
from collections import defaultdict

sys.path.insert(0, str(Path(__file__).parent))
from utils import (
    html_head, html_topbar, html_footer, save_html,
    load_data, fmt_arr, fmt_pct, fmt_count,
    plotly_chart, render_table,
    FOREST_GREEN, LIME_GREEN, SKY_BLUE, DEEP_TEAL, SOFT_PINK,
    GREEN, RED, AMBER, DARK, CHART_PALETTE,
    BLUE, ORANGE, PURPLE, TEAL,
)


# ─── Territory ID → readable label ───────────────────────────────────────────
TERRITORY_MAP = {
    "a1V4J000002hagjUAA": "APJ – T1",
    "a1V4J000002hagoUAA": "APJ – T2",
    "a1V4J000002haglUAA": "EMEA – Nordics",
    "a1V4J000002hah9UAA": "EMEA – Cont. Europe",
    "a1V4J000002hahDUAQ": "EMEA – UK & Ireland",
    "a1V4J000002hahEUAQ": "EMEA – Scandinavia",
    "a1V4J000002hahFUAQ": "EMEA – DACH",
    "a1V4J000002hahIUAQ": "EMEA – Nordics 2",
    "a1V8d000000HLCZEA4": "EMEA – South Europe",
    "a1V8d000000HRi7EAG": "EMEA – DACH 2",
    "a1V4J000002hagqUAA": "NA – Mid-Market",
    "a1VPz000003QcBBMA0": "NA – Enterprise",
    "a1VPz00000E8E7NMAV": "NA – Commercial 1",
    "a1VPz00000E8E8zMAF": "NA – Commercial 2",
    "a1VPz00000E8ECDMA3": "NA – Strategic",
}

def resolve_territory(raw_id):
    return TERRITORY_MAP.get(raw_id, f"Territory …{str(raw_id)[-8:]}")


# ─── Sort helpers ─────────────────────────────────────────────────────────────
def _sort_arr_band(label):
    return {"<=100k": 0, "100k-250k": 1, "250k-500k": 2, "500k+": 3}.get(label, 99)

def _segment_order(label):
    return {"Enterprise": 0, "Mid-Market": 1, "Digital": 2, "Unknown": 99}.get(label, 99)


DIMENSION_META = {
    "Region":           {"color": FOREST_GREEN, "sort": None,            "icon": "🌍"},
    "Territory":        {"color": DEEP_TEAL,    "sort": None,            "icon": "📍", "id_resolver": resolve_territory},
    "SFDC Segment":     {"color": PURPLE,       "sort": None,            "icon": "🏷"},
    "Revenue Segment":  {"color": PURPLE,       "sort": _segment_order,  "icon": "🏢"},
    "ARR Band":         {"color": SKY_BLUE,     "sort": _sort_arr_band,  "icon": "💰"},
    "Solution Type":    {"color": SOFT_PINK,    "sort": None,            "icon": "🔗"},
    "Product Solution": {"color": LIME_GREEN,   "sort": None,            "icon": "📦"},
    "Product Group":    {"color": LIME_GREEN,   "sort": None,            "icon": "🔧"},
}

# Fixed display order per user request
DISPLAY_ORDER = [
    "Region",
    "Territory",
    "SFDC Segment",
    "Revenue Segment",
    "ARR Band",
    "Solution Type",
    "Product Solution",
    "Product Group",
]


# ─── KPI card helper ──────────────────────────────────────────────────────────
def kpi_card(label, value, meta="", color=""):
    return f"""
<div class="kpi-card {color}">
  <div class="kpi-label">{label}</div>
  <div class="kpi-value">{value}</div>
  <div class="kpi-meta">{meta}</div>
</div>"""


# ─── Region section (special) ─────────────────────────────────────────────────
def region_section(rows: list, quarter: str, regional_trend: list) -> str:
    """
    Special Region section:
      1. ARR (positive) / Churn (negative) horizontal bar + RR colour-coded bar side by side
      2. NA & EMEA trend chart (reused from global snapshot)
    No KPI tiles (already shown in Summary). No download table.
    """
    rows = sorted(rows, key=lambda r: -(float(r.get("renewal_arr") or 0)))
    labels  = [r.get("dimension_value", "Unknown") for r in rows]
    arr_v   = [float(r.get("renewal_arr")  or 0) for r in rows]
    churn_v = [float(r.get("churn_arr") or 0) for r in rows]   # keep negative
    rr_v    = [round(float(r.get("renewal_rate") or 0) * 100, 1) for r in rows]
    chart_h = max(280, len(labels) * 48 + 90)

    # ── 1. ARR/Churn horizontal bar (churn negative = extends left) ───────────
    bar_traces = [
        {"type": "bar", "name": "Renewal ARR",
         "x": arr_v, "y": labels, "orientation": "h",
         "marker": {"color": FOREST_GREEN, "opacity": 0.9},
         "hovertemplate": "<b>%{y}</b><br>Renewal ARR: $%{x:,.0f}<extra></extra>"},
        {"type": "bar", "name": "Churn ARR",
         "x": churn_v, "y": labels, "orientation": "h",
         "marker": {"color": RED, "opacity": 0.75},
         "hovertemplate": "<b>%{y}</b><br>Churn ARR: $%{x:,.0f}<extra></extra>"},
    ]
    bar_layout = {
        "barmode": "overlay",
        "title": {"text": "Renewal ARR & Churn by Region", "font": {"size": 13}},
        "xaxis": {"title": "ARR ($) — churn shown as negative", "tickformat": "$,.0f", "automargin": True},
        "yaxis": {"autorange": "reversed", "automargin": True},
        "shapes": [{"type": "line", "x0": 0, "x1": 0, "y0": 0, "y1": 1,
                    "xref": "x", "yref": "paper",
                    "line": {"color": DARK, "width": 1, "dash": "dot"}}],
    }
    arr_bar = plotly_chart("bar_region", bar_traces, bar_layout, height=chart_h)

    # ── 2. RR colour-coded horizontal bar ────────────────────────────────────
    rr_colors = [GREEN if v >= 90 else (AMBER if v >= 80 else RED) for v in rr_v]
    rr_traces = [
        {"type": "bar", "name": "Renewal Rate",
         "x": rr_v, "y": labels, "orientation": "h",
         "marker": {"color": rr_colors},
         "text": [f"{v:.1f}%" for v in rr_v], "textposition": "outside",
         "hovertemplate": "<b>%{y}</b><br>RR: %{x:.1f}%<extra></extra>"},
    ]
    rr_layout = {
        "title": {"text": "Renewal Rate by Region", "font": {"size": 13}},
        "xaxis": {"title": "Renewal Rate (%)", "ticksuffix": "%",
                  "range": [0, 115], "automargin": True},
        "yaxis": {"autorange": "reversed", "automargin": True},
        "shapes": [{"type": "line", "x0": 90, "x1": 90, "y0": 0, "y1": 1,
                    "xref": "x", "yref": "paper",
                    "line": {"color": GREEN, "width": 1.5, "dash": "dot"}}],
        "annotations": [{"x": 90, "y": 1, "xref": "x", "yref": "paper",
                          "text": "90% target", "showarrow": False,
                          "font": {"color": GREEN, "size": 10}, "xanchor": "left"}],
    }
    rr_line = plotly_chart("rr_region", rr_traces, rr_layout, height=chart_h)

    # ── 4. Regional time trend (NA & EMEA) — reused from global snapshot ──────
    if regional_trend and len(regional_trend) >= 2:
        reg_qtrs  = sorted({r.get("quarter", "") for r in regional_trend})
        na_by_q   = {r.get("quarter"): r for r in regional_trend if r.get("region","").upper() == "NA"}
        emea_by_q = {r.get("quarter"): r for r in regional_trend if r.get("region","").upper() == "EMEA"}

        na_rr_t   = [round(float(na_by_q.get(q,{}).get("renewal_rate",0)   or 0) * 100, 1) for q in reg_qtrs]
        emea_rr_t = [round(float(emea_by_q.get(q,{}).get("renewal_rate",0) or 0) * 100, 1) for q in reg_qtrs]
        na_arr_t  = [float(na_by_q.get(q,{}).get("renewal_arr",0)   or 0) for q in reg_qtrs]
        emea_arr_t= [float(emea_by_q.get(q,{}).get("renewal_arr",0) or 0) for q in reg_qtrs]
        na_ch_t   = [float(na_by_q.get(q,{}).get("churn_arr",0)   or 0) for q in reg_qtrs]
        emea_ch_t = [float(emea_by_q.get(q,{}).get("churn_arr",0) or 0) for q in reg_qtrs]

        arr_trend_traces = [
            {"type": "bar", "name": "NA Renewal ARR",
             "x": reg_qtrs, "y": na_arr_t,
             "marker": {"color": FOREST_GREEN},
             "hovertemplate": "<b>NA</b> %{x}<br>Renewal ARR: $%{y:,.0f}<extra></extra>"},
            {"type": "bar", "name": "NA Churn ARR",
             "x": reg_qtrs, "y": na_ch_t,
             "marker": {"color": RED, "opacity": 0.70},
             "hovertemplate": "<b>NA</b> %{x}<br>Churn ARR: $%{y:,.0f}<extra></extra>"},
            {"type": "bar", "name": "EMEA Renewal ARR",
             "x": reg_qtrs, "y": emea_arr_t,
             "marker": {"color": SKY_BLUE},
             "hovertemplate": "<b>EMEA</b> %{x}<br>Renewal ARR: $%{y:,.0f}<extra></extra>"},
            {"type": "bar", "name": "EMEA Churn ARR",
             "x": reg_qtrs, "y": emea_ch_t,
             "marker": {"color": AMBER, "opacity": 0.75},
             "hovertemplate": "<b>EMEA</b> %{x}<br>Churn ARR: $%{y:,.0f}<extra></extra>"},
        ]
        arr_trend_layout = {
            "barmode": "group",
            "title": {"text": "ARR & Churn Trend — NA vs EMEA (churn negative)", "font": {"size": 13}},
            "yaxis": {"title": "ARR ($)", "tickformat": "$,.0f", "automargin": True},
            "legend": {"orientation": "h", "y": 1.08, "x": 0},
            "shapes": [{"type": "line", "x0": -0.5, "x1": len(reg_qtrs) - 0.5,
                        "y0": 0, "y1": 0,
                        "line": {"color": DARK, "width": 1, "dash": "dot"}}],
        }

        rr_trend_traces = [
            {"type": "scatter", "mode": "lines+markers", "name": "NA",
             "x": reg_qtrs, "y": na_rr_t,
             "line": {"color": FOREST_GREEN, "width": 3}, "marker": {"size": 9},
             "hovertemplate": "<b>NA</b> %{x}<br>RR: %{y:.1f}%<extra></extra>"},
            {"type": "scatter", "mode": "lines+markers", "name": "EMEA",
             "x": reg_qtrs, "y": emea_rr_t,
             "line": {"color": SKY_BLUE, "width": 3}, "marker": {"size": 9},
             "hovertemplate": "<b>EMEA</b> %{x}<br>RR: %{y:.1f}%<extra></extra>"},
            {"type": "scatter", "mode": "lines", "name": "90% target",
             "x": reg_qtrs, "y": [90] * len(reg_qtrs),
             "line": {"color": GREEN, "width": 1.5, "dash": "dash"}, "hoverinfo": "skip"},
        ]
        rr_trend_layout = {
            "title": {"text": "Renewal Rate Trend — NA vs EMEA", "font": {"size": 13}},
            "yaxis": {"title": "Renewal Rate (%)", "ticksuffix": "%",
                      "automargin": True, "range": [70, 100]},
            "legend": {"orientation": "h", "y": 1.08, "x": 0},
        }

        trend_html = f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:10px;">Regional Trend — NA &amp; EMEA</h3>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">
    <div>{plotly_chart("arr_reg_bd_trend", arr_trend_traces, arr_trend_layout, height=280)}</div>
    <div>{plotly_chart("rr_reg_bd_trend",  rr_trend_traces,  rr_trend_layout,  height=280)}</div>
  </div>
  <p class="source">Source: EXEC_DECK_RENEWAL_RATES_CUSTOMER (NA &amp; EMEA, {reg_qtrs[0]} → {reg_qtrs[-1]})</p>
</div>"""
    else:
        trend_html = '<div class="card"><p style="color:#9CA3AF">Regional trend data not available (01_regional_trend.json missing).</p></div>'

    # ── Insight ───────────────────────────────────────────────────────────────
    if rows:
        top_rr  = max(zip(rr_v, labels), key=lambda x: x[0])
        bot_rr  = min(zip(rr_v, labels), key=lambda x: x[0])
        top_arr = max(zip(arr_v, labels), key=lambda x: x[0])
        insight = (
            f"<b>{top_arr[1]}</b> contributes the most renewal ARR ({fmt_arr(top_arr[0])}). "
            f"Highest renewal rate: <b>{top_rr[1]}</b> at {top_rr[0]:.1f}%. "
            f"Lowest: <b>{bot_rr[1]}</b> at {bot_rr[0]:.1f}%. "
            f"Spread: <strong>{top_rr[0]-bot_rr[0]:.1f}pp</strong>."
        )
    else:
        insight = "No regional data available."

    return f"""
<section class="section" id="region">
  <h2>🌍 Region <span class="period-badge">{quarter}</span></h2>
  <div class="card">
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">
      <div>{arr_bar}</div>
      <div>{rr_line}</div>
    </div>
    <p class="source" style="margin-top:8px;">
      Source: EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP (deduped) &nbsp;·&nbsp; Period: {quarter}
    </p>
  </div>
  {trend_html}
  <div class="insight"><strong>What the data shows ({quarter}):</strong> {insight}</div>
</section>"""


# ─── Generic dimension section ────────────────────────────────────────────────
def dimension_section(dim_type: str, rows: list, section_id: str, quarter: str) -> str:
    meta      = DIMENSION_META.get(dim_type, {"color": FOREST_GREEN, "sort": None, "icon": "📊"})
    color     = meta["color"]
    sort_fn   = meta.get("sort")
    icon      = meta["icon"]
    resolver  = meta.get("id_resolver")

    if sort_fn:
        rows = sorted(rows, key=lambda r: sort_fn(r.get("dimension_value", "")))
    elif dim_type == "Territory":
        # Sort alphabetically by resolved label
        rows = sorted(rows, key=lambda r: (resolver(r.get("dimension_value","")) if resolver else r.get("dimension_value","")))
    elif dim_type == "Product Solution":
        # Sort by RR% descending
        rows = sorted(rows, key=lambda r: -(float(r.get("renewal_rate") or 0)))
    else:
        rows = sorted(rows, key=lambda r: -(float(r.get("renewal_arr") or 0)))

    raw_labels = [r.get("dimension_value", "Unknown") for r in rows]
    labels = [resolver(l) if resolver else l for l in raw_labels]

    arr_v   = [float(r.get("renewal_arr")  or 0) for r in rows]
    churn_v = [float(r.get("churn_arr") or 0) for r in rows]   # keep negative
    rr_v    = [round(float(r.get("renewal_rate") or 0) * 100, 1) for r in rows]

    chart_h = max(280, len(labels) * 38 + 90)

    # ARR + Churn horizontal bar (churn negative = extends left)
    bar_traces = [
        {"type": "bar", "name": "Renewal ARR",
         "x": arr_v, "y": labels, "orientation": "h",
         "marker": {"color": color, "opacity": 0.9},
         "hovertemplate": "<b>%{y}</b><br>Renewal ARR: $%{x:,.0f}<extra></extra>"},
        {"type": "bar", "name": "Churn ARR",
         "x": churn_v, "y": labels, "orientation": "h",
         "marker": {"color": RED, "opacity": 0.75},
         "hovertemplate": "<b>%{y}</b><br>Churn ARR: $%{x:,.0f}<extra></extra>"},
    ]
    bar_layout = {
        "barmode": "overlay",
        "title": {"text": f"ARR & Churn by {dim_type}", "font": {"size": 13, "color": DARK}},
        "xaxis": {"title": "ARR ($) — churn shown as negative", "tickformat": "$,.0f", "automargin": True},
        "yaxis": {"autorange": "reversed", "automargin": True},
        "shapes": [{"type": "line", "x0": 0, "x1": 0, "y0": 0, "y1": 1,
                    "xref": "x", "yref": "paper",
                    "line": {"color": DARK, "width": 1, "dash": "dot"}}],
    }
    arr_bar = plotly_chart(f"bar_{section_id}", bar_traces, bar_layout, height=chart_h)

    # RR colour-coded horizontal bar
    rr_colors = [GREEN if v >= 90 else (AMBER if v >= 80 else RED) for v in rr_v]
    rr_traces = [
        {"type": "bar", "name": "Renewal Rate",
         "x": rr_v, "y": labels, "orientation": "h",
         "marker": {"color": rr_colors},
         "text": [f"{v}%" for v in rr_v], "textposition": "outside",
         "hovertemplate": "<b>%{y}</b><br>Renewal Rate: %{x:.1f}%<extra></extra>"},
    ]
    rr_layout = {
        "title": {"text": f"Renewal Rate by {dim_type}", "font": {"size": 13, "color": DARK}},
        "xaxis": {"title": "Renewal Rate (%)", "ticksuffix": "%",
                  "range": [0, 115], "automargin": True},
        "yaxis": {"autorange": "reversed", "automargin": True},
        "shapes": [{"type": "line", "x0": 90, "x1": 90, "y0": 0, "y1": 1,
                    "xref": "x", "yref": "paper",
                    "line": {"color": GREEN, "width": 1.5, "dash": "dot"}}],
        "annotations": [{"x": 90, "y": 1, "xref": "x", "yref": "paper",
                          "text": "90% target", "showarrow": False,
                          "font": {"color": GREEN, "size": 10}, "xanchor": "left"}],
    }
    rr_bar = plotly_chart(f"rr_{section_id}", rr_traces, rr_layout, height=chart_h)

    # Table + optional filter (Territory) + download
    table_rows = []
    for i, r in enumerate(rows):
        table_rows.append({
            "Dimension":    labels[i],
            "Accounts":     fmt_count(r.get("renewal_count")),
            "Renewal ARR":  fmt_arr(r.get("renewal_arr")),
            "Churn ARR":    fmt_arr(float(r.get("churn_arr") or 0)),
            "Renewal Rate": fmt_pct(float(r.get("renewal_rate") or 0)),
        })
    tbl_id     = f"tbl_{section_id}"
    filter_id  = f"filter_{section_id}"
    table_html = render_table(table_rows, tbl_id)

    # Dynamic filter input for Territory (many rows)
    filter_html = ""
    if dim_type == "Territory":
        filter_html = f"""
<div style="margin-bottom:10px;">
  <input id="{filter_id}" type="text" placeholder="Filter territories…"
    oninput="filterTable('{filter_id}','{tbl_id}')"
    style="padding:6px 12px;border:1px solid #C8D4C0;border-radius:6px;
           font-size:13px;width:260px;outline:none;" />
</div>"""

    dl_btn = f"""
<button class="dl-btn" onclick="downloadCSV('{tbl_id}','{dim_type.replace(' ','_')}_{quarter}.csv')">
  ⬇ Download CSV
</button>"""

    # Insight
    if rows:
        top_rr  = max(zip(rr_v, labels), key=lambda x: x[0])
        bot_rr  = min(zip(rr_v, labels), key=lambda x: x[0])
        top_arr = max(zip(arr_v, labels), key=lambda x: x[0])
        total_churn_dim = sum(churn_v)
        insight = (
            f"<b>{top_arr[1]}</b> contributes the most renewal ARR ({fmt_arr(top_arr[0])}). "
            f"Highest RR: <b>{top_rr[1]}</b> at {top_rr[0]:.1f}%. "
            f"Lowest: <b>{bot_rr[1]}</b> at {bot_rr[0]:.1f}%. "
            f"Spread: <strong>{top_rr[0]-bot_rr[0]:.1f}pp</strong>. "
            f"Total churn ARR across this dimension: {fmt_arr(total_churn_dim)}."
        )
    else:
        insight = "No data available."

    return f"""
<section class="section" id="{section_id}">
  <h2>{icon} {dim_type} <span class="period-badge">{quarter}</span></h2>
  <div class="card">
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">
      <div>{arr_bar}</div>
      <div>{rr_bar}</div>
    </div>
  </div>
  <div class="card">
    {filter_html}
    {table_html}
    {dl_btn}
    <p class="source" style="margin-top:8px;">
      Source: EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP (deduped) &nbsp;·&nbsp; Period: {quarter}
    </p>
  </div>
  <div class="insight"><strong>What the data shows ({quarter}):</strong> {insight}</div>
</section>"""


# ─── Main ─────────────────────────────────────────────────────────────────────
def build(data_dir: Path, quarter: str, output_dir: Path):
    dims         = load_data(data_dir, "02_scorecard_dimensions")
    regional_trd = load_data(data_dir, "01_regional_trend")

    if not dims:
        print("[ERROR] 02_scorecard_dimensions.json missing.")
        return

    # Group rows by dimension_type
    by_type = defaultdict(list)
    for r in dims:
        by_type[r.get("dimension_type", "Unknown")].append(r)

    # Final order: fixed list first, then any extras not in the list
    ordered_dims = [d for d in DISPLAY_ORDER if d in by_type]
    for dt in by_type:
        if dt not in ordered_dims:
            ordered_dims.append(dt)

    # ── Summary KPIs — global + per-region ───────────────────────────────────
    region_rows = by_type.get("Region", [])
    total_arr   = sum(float(r.get("renewal_arr") or 0) for r in region_rows)
    total_churn = sum(float(r.get("churn_arr")   or 0) for r in region_rows)
    total_rr    = (total_arr + total_churn) / total_arr if total_arr else 0

    reg_sorted = sorted(region_rows, key=lambda r: -(float(r.get("renewal_arr") or 0)))

    region_colors = {"NA": "teal", "EMEA": "sky", "APJ": "green"}
    reg_kpis = ""
    for r in reg_sorted:
        region = r.get("dimension_value", "")
        rr_val = float(r.get("renewal_rate") or 0)
        rr_col = "#22C55E" if rr_val * 100 >= 90 else ("#F59E0B" if rr_val * 100 >= 80 else "#EF4444")
        col    = region_colors.get(region, "")
        reg_kpis += f"""
<div class="kpi-card {col}">
  <div class="kpi-label">{region}</div>
  <div class="kpi-value">{fmt_arr(r.get("renewal_arr"))}</div>
  <div class="kpi-meta">
    {fmt_count(r.get("renewal_count"))} accounts &nbsp;·&nbsp; Churn {fmt_arr(abs(float(r.get("churn_arr") or 0)))}<br>
    <span style="color:{rr_col};font-weight:700;">RR {rr_val*100:.1f}%</span>
  </div>
</div>"""

    summary_html = f"""
<section class="section" id="summary">
  <h2>Breakdown Summary <span class="period-badge">{quarter}</span></h2>
  <div class="kpi-grid">
    <div class="kpi-card">
      <div class="kpi-label">Total Renewal ARR</div>
      <div class="kpi-value">{fmt_arr(total_arr)}</div>
      <div class="kpi-meta">All regions — {quarter}</div>
    </div>
    <div class="kpi-card red">
      <div class="kpi-label">Total Churn ARR</div>
      <div class="kpi-value">{fmt_arr(abs(total_churn))}</div>
      <div class="kpi-meta">{fmt_pct(abs(total_churn)/total_arr) if total_arr else 'N/A'} of renewal ARR</div>
    </div>
    <div class="kpi-card green">
      <div class="kpi-label">Blended Renewal Rate</div>
      <div class="kpi-value">{fmt_pct(total_rr)}</div>
      <div class="kpi-meta">Region-level aggregate</div>
    </div>
    {reg_kpis}
  </div>
  <p class="source" style="margin-top:12px;">
    Territory labels derived from Salesforce territory IDs mapped to regional groups.
  </p>
</section>"""

    # ── Build all dimension sections ──────────────────────────────────────────
    sections_html = ""
    for dt in ordered_dims:
        if dt == "Region":
            sections_html += region_section(by_type["Region"], quarter, regional_trd or [])
        else:
            sid = dt.lower().replace(" ", "_")
            sections_html += dimension_section(dt, by_type[dt], sid, quarter)

    # ── Sidebar ───────────────────────────────────────────────────────────────
    sidebar_links = '<a href="#summary">Summary</a>\n'
    for dt in ordered_dims:
        sid = "region" if dt == "Region" else dt.lower().replace(" ", "_")
        sidebar_links += f'<a href="#{sid}">{dt}</a>\n'
    sidebar = f'<nav class="sidebar">{sidebar_links}</nav>'

    # Shared JS: CSV download + table filter
    dl_js = """
<script>
function downloadCSV(tableId, fname) {
  const tbl = document.getElementById(tableId);
  let csv = [];
  for (let row of tbl.rows) {
    csv.push(Array.from(row.cells).map(c => '"' + c.innerText.replace(/"/g,'""') + '"').join(','));
  }
  const blob = new Blob([csv.join('\\n')], {type:'text/csv'});
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob);
  a.download = fname; a.click();
}
function filterTable(inputId, tableId) {
  const query = document.getElementById(inputId).value.toLowerCase();
  const rows  = document.getElementById(tableId).querySelectorAll('tbody tr');
  rows.forEach(row => {
    const text = row.textContent.toLowerCase();
    row.style.display = text.includes(query) ? '' : 'none';
  });
}
</script>"""

    content = f"""
<div class="layout">
{sidebar}
<div class="main">
{summary_html}
{sections_html}
{dl_js}
</div>
</div>"""

    html = (
        html_head(f"CS Breakdowns — {quarter}")
        + html_topbar("CS Breakdowns by Dimension", quarter)
        + content
        + html_footer(["EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP"])
    )

    return save_html(html, output_dir, "02_breakdowns.html")


# ─── CLI ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Build Dimension Breakdowns Dashboard")
    ap.add_argument("--data",    required=True)
    ap.add_argument("--quarter", required=True)
    ap.add_argument("--out",     default="../output")
    args = ap.parse_args()
    build(Path(args.data), args.quarter, Path(args.out))
