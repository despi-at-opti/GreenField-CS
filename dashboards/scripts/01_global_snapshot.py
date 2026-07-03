"""
01_global_snapshot.py — Global CS Snapshot Dashboard
=====================================================
Uses data from:
  - 01_scorecard_totals.json    (global KPIs: ARR, accounts, churn, renewal rate)
  - 01_scorecard_trend.json     (multi-quarter global historical trend)
  - 01_regional_trend.json      (NA + EMEA historical trend, 4 quarters)
  - 07_opal_analysis.json       (Opal attach + renewals — KPI cards only)
  - 02_scorecard_dimensions.json (EO / EC product-level renewal rate)

Sections:
  1. KPI Summary  — global metrics + Opal KPI cards in one grid
  2. Global Trend — ARR/churn bars + RR trend line
  3. NA & EMEA Trend — dual ARR/churn bars + dual RR trend lines

Usage:
  python 01_global_snapshot.py --data ../data --quarter 2026-Q2 --out ../output
"""

import argparse, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from utils import (
    html_head, html_topbar, html_footer, save_html,
    load_data, fmt_arr, fmt_pct, fmt_delta, fmt_count,
    plotly_chart, render_table,
    FOREST_GREEN, LIME_GREEN, SKY_BLUE, DEEP_TEAL,
    GREEN, RED, AMBER, DARK, CHART_PALETTE,
    BLUE, ORANGE,
)


# ─── KPI Card Helper ──────────────────────────────────────────────────────────
def kpi_card(label, value, meta="", color=""):
    return f"""
<div class="kpi-card {color}">
  <div class="kpi-label">{label}</div>
  <div class="kpi-value">{value}</div>
  <div class="kpi-meta">{meta}</div>
</div>"""


# ─── Main build ───────────────────────────────────────────────────────────────
def build(data_dir: Path, quarter: str, output_dir: Path):

    # ── Load data ─────────────────────────────────────────────────────────────
    totals       = load_data(data_dir, "01_scorecard_totals")
    trend        = load_data(data_dir, "01_scorecard_trend")
    regional_trd = load_data(data_dir, "01_regional_trend")
    opal         = load_data(data_dir, "07_opal_analysis")
    dims         = load_data(data_dir, "02_scorecard_dimensions")

    if not totals:
        print("[ERROR] 01_scorecard_totals.json missing. Cannot build global snapshot.")
        return

    # ── Current-quarter row ───────────────────────────────────────────────────
    if isinstance(totals, list):
        row = next((r for r in totals if r.get("current_quarter") == quarter), totals[0])
    else:
        row = totals

    # ── Parse Opal ────────────────────────────────────────────────────────────
    opal_attach_all = opal_curr = opal_prior = None
    if opal:
        for o in opal:
            sec = o.get("_section", "")
            if sec == "attach" and str(o.get("region", "")).upper() == "ALL":
                opal_attach_all = o
            elif sec == "renewals":
                if o.get("period") == "Current":
                    opal_curr = o
                elif o.get("period") == "Prior":
                    opal_prior = o

    # ── Parse dims ────────────────────────────────────────────────────────────
    eo_rr = ec_rr = None
    if dims:
        for d in dims:
            dt = d.get("dimension_type", "").strip()
            if dt == "Product Solution":
                dv = str(d.get("dimension_value", "")).upper()
                if dv == "EO":   eo_rr = d.get("renewal_rate")
                elif dv == "EC": ec_rr = d.get("renewal_rate")

    # ── Global trend ──────────────────────────────────────────────────────────
    has_trend = trend and len(trend) >= 2
    if has_trend:
        trend_sorted = sorted(trend, key=lambda r: r.get("quarter", ""))
        trend_qtrs   = [r.get("quarter", "") for r in trend_sorted]
        trend_arr    = [float(r.get("renewal_arr", 0) or 0) for r in trend_sorted]
        trend_churn  = [abs(float(r.get("churn_arr", 0) or 0)) for r in trend_sorted]
        trend_rr     = [float(r.get("renewal_rate", 0) or 0) for r in trend_sorted]
        avg_rr_val   = sum(trend_rr) / len(trend_rr)

    # ── Regional trend ────────────────────────────────────────────────────────
    has_reg_trend = regional_trd and len(regional_trd) >= 2
    if has_reg_trend:
        reg_qtrs  = sorted({r.get("quarter", "") for r in regional_trd})
        na_by_q   = {r.get("quarter"): r for r in regional_trd if r.get("region","").upper() == "NA"}
        emea_by_q = {r.get("quarter"): r for r in regional_trd if r.get("region","").upper() == "EMEA"}

    # ─────────────────────────────────────────────────────────────────────────
    # SECTION 1: KPI grid — global + Opal cards
    # ─────────────────────────────────────────────────────────────────────────
    rr_curr  = float(row.get("current_renewal_rate",  0) or 0)
    rr_prior = float(row.get("prior_renewal_rate",    0) or 0)
    rr_qoq   = rr_curr - rr_prior
    arr_curr  = float(row.get("current_renewal_arr",  0) or 0)
    arr_qoq   = row.get("qoq_renewal_arr_delta")
    arr_yoy   = row.get("yoy_renewal_arr_delta")
    churn_abs = abs(float(row.get("current_churn_arr", 0) or 0))
    churn_qoq = row.get("qoq_churn_arr_delta")
    cnt_curr  = row.get("current_renewal_count")
    cnt_qoq   = row.get("qoq_renewal_count_delta")
    churn_pct = churn_abs / arr_curr if arr_curr else 0

    rr_avg_note = ""
    if has_trend and len(trend_rr) > 1:
        avg_rr = sum(trend_rr) / len(trend_rr)
        diff   = rr_curr - avg_rr
        sign   = "above" if diff >= 0 else "below"
        rr_avg_note = f"{fmt_pct(abs(diff))} {sign} {len(trend_rr)}Q avg ({fmt_pct(avg_rr)})"

    ti = row.get("trend_indicator", "ON_TARGET")
    badge_col  = GREEN if ti == "UP" else (RED if ti == "DOWN" else AMBER)
    badge_icon = "▲" if ti == "UP" else ("▼" if ti == "DOWN" else "→")
    trend_badge = f"""
<div style="display:inline-flex;align-items:center;gap:8px;padding:8px 16px;
  border-radius:20px;background:{badge_col}22;color:{badge_col};
  font-weight:700;font-size:14px;margin-bottom:16px;">
  {badge_icon} Renewal Rate is <strong>{ti.replace('_',' ')}</strong> vs prior quarter
</div>"""

    kpi_html = '<div class="kpi-grid">'

    # Global metrics
    kpi_html += kpi_card(
        "Total Renewal ARR", fmt_arr(arr_curr),
        f"QoQ {fmt_delta(arr_qoq, is_arr=True)} &nbsp;|&nbsp; YoY {fmt_delta(arr_yoy, is_arr=True)}"
        + (f" &nbsp;|&nbsp; ✅ {fmt_pct(row.get('vs_target_pct'))} of target" if row.get("vs_target_pct") else ""),
    )
    kpi_html += kpi_card(
        "Active Accounts", fmt_count(cnt_curr),
        f"QoQ {fmt_delta(cnt_qoq)}", color="green",
    )
    kpi_html += kpi_card(
        "Total Churn ARR", fmt_arr(churn_abs),
        f"QoQ {fmt_delta(churn_qoq, is_arr=True)} &nbsp;|&nbsp; {fmt_pct(churn_pct)} of renewal ARR",
        color="red",
    )
    kpi_html += kpi_card(
        "Overall Renewal Rate", fmt_pct(rr_curr),
        f"QoQ {fmt_delta(rr_qoq, is_pct=True)}" + (f" &nbsp;|&nbsp; {rr_avg_note}" if rr_avg_note else ""),
        color="teal",
    )
    if eo_rr is not None:
        kpi_html += kpi_card("EO Renewal Rate", fmt_pct(eo_rr),
                              "Experimentation Optimization", color="sky")
    if ec_rr is not None:
        kpi_html += kpi_card("EC Renewal Rate", fmt_pct(ec_rr),
                              "Experience Commerce", color="purple")

    # Opal attach rate
    if opal_attach_all:
        oa_rate = opal_attach_all.get("opal_attach_rate") or opal_attach_all.get("attach_rate")
        oa_eo   = opal_attach_all.get("eo_customer_count")
        oa_att  = opal_attach_all.get("opal_attached_count")
        kpi_html += kpi_card(
            "Opal Attach Rate",
            fmt_pct(oa_rate) if oa_rate is not None else "N/A",
            f"EO customers: {fmt_count(oa_eo)} &nbsp;|&nbsp; Opal attached: {fmt_count(oa_att)}",
            color="amber",
        )
        # Opal active accounts
        kpi_html += kpi_card(
            "Opal Active Accounts", fmt_count(oa_att),
            f"of {fmt_count(oa_eo)} EO accounts &nbsp;|&nbsp; {fmt_pct(oa_rate)} attach rate",
            color="amber",
        )

    # Opal renewals
    if opal_curr:
        ren_rr  = opal_curr.get("renewal_rate")
        rr_dlt  = opal_curr.get("renewal_rate_qoq_delta")
        prior_rr_label = fmt_pct(opal_prior.get("renewal_rate")) if opal_prior else "—"
        kpi_html += kpi_card(
            "Opal Renewal ARR", fmt_arr(opal_curr.get("arr_renewal")),
            f"{fmt_count(opal_curr.get('renewal_count'))} accounts &nbsp;·&nbsp; "
            f"RR {fmt_pct(ren_rr)} (QoQ {fmt_delta(rr_dlt, is_pct=True)}, prior {prior_rr_label})",
            color="teal",
        )

    kpi_html += "</div>"

    insights_html = f"""
<div class="insight">
  <strong>Key Insights — {quarter}:</strong><br>
  Overall renewal rate is <strong>{fmt_pct(rr_curr)}</strong>,
  {"▲ up" if rr_qoq >= 0 else "▼ down"} <strong>{fmt_pct(abs(rr_qoq))}pp</strong>
  vs prior quarter ({fmt_pct(rr_prior)}).
  Total churn ARR ({fmt_arr(churn_abs)}) represents <strong>{fmt_pct(churn_pct)}</strong> of renewal ARR.
  {"See Trend section for multi-quarter context." if has_trend else ""}
  Drill into the Breakdowns and Deep Analyses dashboards for dimension-level and account-level drivers.
</div>"""

    # ─────────────────────────────────────────────────────────────────────────
    # SECTION 2: Global Trend (ARR/churn bars + RR line)
    # ─────────────────────────────────────────────────────────────────────────
    if has_trend:
        arr_traces = [
            {"type": "bar", "name": "Renewal ARR",
             "x": trend_qtrs, "y": trend_arr,
             "marker": {"color": FOREST_GREEN},
             "hovertemplate": "%{x}<br>Renewal ARR: $%{y:,.0f}<extra></extra>"},
            {"type": "bar", "name": "Churn ARR",
             "x": trend_qtrs, "y": trend_churn,
             "marker": {"color": RED, "opacity": 0.75},
             "hovertemplate": "%{x}<br>Churn ARR: $%{y:,.0f}<extra></extra>"},
        ]
        arr_layout = {
            "title": {"text": "Global ARR & Churn by Quarter", "font": {"size": 14, "color": DARK}},
            "yaxis": {"title": "ARR ($)", "tickformat": "$,.0f", "automargin": True},
            "barmode": "group",
        }

        rr_traces = [
            {"type": "scatter", "mode": "lines+markers", "name": "Renewal Rate",
             "x": trend_qtrs, "y": [round(v * 100, 1) for v in trend_rr],
             "line": {"color": LIME_GREEN, "width": 3},
             "marker": {"size": 9, "color": FOREST_GREEN},
             "hovertemplate": "%{x}<br>Renewal Rate: %{y:.1f}%<extra></extra>"},
            {"type": "scatter", "mode": "lines", "name": f"Avg {avg_rr_val*100:.1f}%",
             "x": trend_qtrs, "y": [round(avg_rr_val * 100, 1)] * len(trend_qtrs),
             "line": {"color": AMBER, "width": 2, "dash": "dash"},
             "hoverinfo": "skip"},
        ]
        rr_layout = {
            "title": {"text": "Global Renewal Rate Trend", "font": {"size": 14, "color": DARK}},
            "yaxis": {"title": "Renewal Rate (%)", "ticksuffix": "%",
                      "automargin": True, "range": [70, 100]},
        }

        trend_section = f"""
<div class="card">
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">
    <div>{plotly_chart("trend_arr", arr_traces, arr_layout, height=300)}</div>
    <div>{plotly_chart("trend_rr",  rr_traces,  rr_layout,  height=300)}</div>
  </div>
  <p class="source">Source: EXEC_DECK_RENEWAL_RATES_CUSTOMER — {len(trend_qtrs)} quarters ({trend_qtrs[0]} → {trend_qtrs[-1]})</p>
</div>"""
    else:
        trend_section = '<div class="card"><p style="color:#9CA3AF">Trend data not available (01_scorecard_trend.json missing).</p></div>'

    # ─────────────────────────────────────────────────────────────────────────
    # SECTION 3: NA & EMEA Regional Trend
    # ─────────────────────────────────────────────────────────────────────────
    if has_reg_trend:
        na_arr_v    = [float(na_by_q.get(q, {}).get("renewal_arr",   0) or 0) for q in reg_qtrs]
        na_churn_v  = [abs(float(na_by_q.get(q, {}).get("churn_arr", 0) or 0)) for q in reg_qtrs]
        emea_arr_v  = [float(emea_by_q.get(q, {}).get("renewal_arr",   0) or 0) for q in reg_qtrs]
        emea_churn_v= [abs(float(emea_by_q.get(q, {}).get("churn_arr", 0) or 0)) for q in reg_qtrs]
        na_rr_v     = [round(float(na_by_q.get(q, {}).get("renewal_rate",   0) or 0) * 100, 1) for q in reg_qtrs]
        emea_rr_v   = [round(float(emea_by_q.get(q, {}).get("renewal_rate", 0) or 0) * 100, 1) for q in reg_qtrs]
        na_cnt_v    = [int(na_by_q.get(q, {}).get("renewal_count",   0) or 0) for q in reg_qtrs]
        emea_cnt_v  = [int(emea_by_q.get(q, {}).get("renewal_count", 0) or 0) for q in reg_qtrs]

        arr_reg_traces = [
            {"type": "bar", "name": "NA Renewal ARR",
             "x": reg_qtrs, "y": na_arr_v,
             "marker": {"color": FOREST_GREEN},
             "hovertemplate": "<b>NA</b> %{x}<br>Renewal ARR: $%{y:,.0f}<extra></extra>"},
            {"type": "bar", "name": "NA Churn ARR",
             "x": reg_qtrs, "y": na_churn_v,
             "marker": {"color": RED, "opacity": 0.70},
             "hovertemplate": "<b>NA</b> %{x}<br>Churn ARR: $%{y:,.0f}<extra></extra>"},
            {"type": "bar", "name": "EMEA Renewal ARR",
             "x": reg_qtrs, "y": emea_arr_v,
             "marker": {"color": SKY_BLUE},
             "hovertemplate": "<b>EMEA</b> %{x}<br>Renewal ARR: $%{y:,.0f}<extra></extra>"},
            {"type": "bar", "name": "EMEA Churn ARR",
             "x": reg_qtrs, "y": emea_churn_v,
             "marker": {"color": AMBER, "opacity": 0.70},
             "hovertemplate": "<b>EMEA</b> %{x}<br>Churn ARR: $%{y:,.0f}<extra></extra>"},
        ]
        arr_reg_layout = {
            "barmode": "group",
            "title": {"text": "ARR & Churn — NA vs EMEA", "font": {"size": 14}},
            "yaxis": {"title": "ARR ($)", "tickformat": "$,.0f", "automargin": True},
            "legend": {"orientation": "h", "y": 1.08, "x": 0},
        }

        rr_reg_traces = [
            {"type": "scatter", "mode": "lines+markers", "name": "NA",
             "x": reg_qtrs, "y": na_rr_v,
             "line": {"color": FOREST_GREEN, "width": 3},
             "marker": {"size": 9},
             "hovertemplate": "<b>NA</b> %{x}<br>RR: %{y:.1f}%<extra></extra>"},
            {"type": "scatter", "mode": "lines+markers", "name": "EMEA",
             "x": reg_qtrs, "y": emea_rr_v,
             "line": {"color": SKY_BLUE, "width": 3},
             "marker": {"size": 9},
             "hovertemplate": "<b>EMEA</b> %{x}<br>RR: %{y:.1f}%<extra></extra>"},
            {"type": "scatter", "mode": "lines", "name": "90% target",
             "x": reg_qtrs, "y": [90] * len(reg_qtrs),
             "line": {"color": GREEN, "width": 1.5, "dash": "dash"},
             "hoverinfo": "skip"},
        ]
        rr_reg_layout = {
            "title": {"text": "Renewal Rate Trend — NA vs EMEA", "font": {"size": 14}},
            "yaxis": {"title": "Renewal Rate (%)", "ticksuffix": "%",
                      "automargin": True, "range": [70, 100]},
            "legend": {"orientation": "h", "y": 1.08, "x": 0},
        }

        # Summary table
        reg_tbl_rows = []
        for q in reg_qtrs:
            for region, by_q, arr_v, churn_v, rr_v, cnt_v in [
                ("NA",   na_by_q,   na_arr_v,   na_churn_v,   na_rr_v,   na_cnt_v),
                ("EMEA", emea_by_q, emea_arr_v, emea_churn_v, emea_rr_v, emea_cnt_v),
            ]:
                idx = reg_qtrs.index(q)
                if by_q.get(q):
                    reg_tbl_rows.append({
                        "Quarter":      q,
                        "Region":       region,
                        "Renewals":     fmt_count(cnt_v[idx]),
                        "Renewal ARR":  fmt_arr(arr_v[idx]),
                        "Churn ARR":    fmt_arr(churn_v[idx]),
                        "Renewal Rate": f"{rr_v[idx]:.1f}%",
                    })

        regional_trend_section = f"""
<div class="card">
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">
    <div>{plotly_chart("arr_reg_trend", arr_reg_traces, arr_reg_layout, height=300)}</div>
    <div>{plotly_chart("rr_reg_trend",  rr_reg_traces,  rr_reg_layout,  height=300)}</div>
  </div>
  <div style="margin-top:16px">{render_table(reg_tbl_rows, "tbl_reg_trend")}</div>
  <p class="source">Source: EXEC_DECK_RENEWAL_RATES_CUSTOMER (NA &amp; EMEA, {reg_qtrs[0]} → {reg_qtrs[-1]})</p>
</div>"""
    else:
        regional_trend_section = '<div class="card"><p style="color:#9CA3AF">Regional trend data not available (01_regional_trend.json missing).</p></div>'

    # ─────────────────────────────────────────────────────────────────────────
    # Assemble page
    # ─────────────────────────────────────────────────────────────────────────
    sidebar = """
<nav class="sidebar">
  <a href="#kpis">KPI Summary</a>
  <a href="#global_trend">Global Trend</a>
  <a href="#regional_trend">NA &amp; EMEA Trend</a>
</nav>"""

    content = f"""
<div class="layout">
{sidebar}
<div class="main">

<section class="section" id="kpis">
  <h2>Global KPIs <span class="period-badge">{quarter}</span></h2>
  {trend_badge}
  {kpi_html}
  {insights_html}
  <p class="source" style="margin-top:12px;">
    Source: EXEC_DECK_RENEWAL_RATES_CUSTOMER &nbsp;·&nbsp;
    Prior quarter: {row.get('prior_quarter','—')} &nbsp;·&nbsp;
    YoY quarter: {row.get('yoy_quarter','—')}
  </p>
</section>

<section class="section" id="global_trend">
  <h2>Global Trend Analysis <span class="period-badge">{quarter}</span></h2>
  {trend_section}
</section>

<section class="section" id="regional_trend">
  <h2>Regional Trend — NA &amp; EMEA <span class="period-badge">{quarter}</span></h2>
  {regional_trend_section}
</section>

</div>
</div>"""

    html = (
        html_head(f"Global Snapshot — {quarter}")
        + html_topbar("CS Global Snapshot", quarter)
        + content
        + html_footer(["EXEC_DECK_RENEWAL_RATES_CUSTOMER", "RENEWAL_OPPORTUNITY", "SST_REPORT"])
    )

    return save_html(html, output_dir, "01_global_snapshot.html")


# ─── CLI ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Build Global Snapshot Dashboard")
    ap.add_argument("--data",    required=True, help="Directory with JSON data files")
    ap.add_argument("--quarter", required=True, help="Target quarter, e.g. 2026-Q2")
    ap.add_argument("--out",     default="../output", help="Output directory")
    args = ap.parse_args()
    build(Path(args.data), args.quarter, Path(args.out))
