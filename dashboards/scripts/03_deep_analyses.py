"""
03_deep_analyses.py — Deep Analyses Dashboard
==============================================
All column names validated against live Snowflake data (2026-Q2).

Data files and their confirmed key names (post lowercase normalisation):
  06_churn_reason.json   → churn_reason, opportunity_count, churn_arr
  03_detailed_renewals   → account_name, csm, region, territory, arr_renewal, arr_churn, revenue_segment,
                           arr_band, sol_type, product_groups, retained_churned, renewal_rate
  04_churn_list          → account_name, csm, region, territory, arr_renewal, arr_churn, revenue_segment,
                           arr_band, sol_type, product_groups, product_count,
                           type_of_churn, churn_category (NULL — SFDC ACCOUNT_ID ≠ MCID mapping gap)
  05_cross_upsell        → _section: cross_sell (product_group, account_count, total_arr)
                                      upsell     (product_group, account_count, total_arr_increase)
                           cross_sell = existing customer adds a net-new product (ARR = new product line ARR)
                           upsell     = existing customer grows ARR on a product already held (ARR = delta)
  08_oa_analysis         → _section: customers (region, active_customer_count)
                                      regional (region, renewal_arr, churn_arr, renewal_rate)
                                      trend (activity_month, active_customer_count, avg_experiments_started, total_experiments_started)
  09_eo_deep_dive        → _section: regional (period, date_yq, region, renewal_rate, renewal_arr)
                                      opal_corr (opal_attach, renewal_rate, renewal_arr)
                                      tester (tester_type, renewal_rate, renewal_arr)
                                      next_prod (next_product, customers_who_had_webex_at_start,
                                                 customers_who_added_next_product, conversion_rate_pct)
  10_cms_paas_saas       → _section: trend (snapshot_month, product_type, customer_count, total_arr)
                                      renewal_trend (product_group_cleaned, renewal_rate, renewal_arr)
                                      upcoming (account_name, csm, region, paas_arr, saas_arr, total_arr)
  11_cms_portfolio       → cms_manager, account_name, region, territory, revenue_segment,
                           product_groups, arr_renewal, renewal_rate, pipeline_stage

Usage:
  python 03_deep_analyses.py --data ../data --quarter 2026-Q2 --out ../output
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

# Territory ID mapping (same as Dashboard 2)
from importlib.util import spec_from_file_location, module_from_spec
import os
_TERR_MAP = {
    "a1V4J000002hagjUAA": "APJ – T1", "a1V4J000002hagoUAA": "APJ – T2",
    "a1V4J000002haglUAA": "EMEA – Nordics", "a1V4J000002hah9UAA": "EMEA – Cont. Europe",
    "a1V4J000002hahDUAQ": "EMEA – UK & Ireland", "a1V4J000002hahEUAQ": "EMEA – Scandinavia",
    "a1V4J000002hahFUAQ": "EMEA – DACH", "a1V4J000002hahIUAQ": "EMEA – Nordics 2",
    "a1V8d000000HLCZEA4": "EMEA – South Europe", "a1V8d000000HRi7EAG": "EMEA – DACH 2",
    "a1V4J000002hagqUAA": "NA – Mid-Market", "a1VPz000003QcBBMA0": "NA – Enterprise",
    "a1VPz00000E8E7NMAV": "NA – Commercial 1", "a1VPz00000E8E8zMAF": "NA – Commercial 2",
    "a1VPz00000E8ECDMA3": "NA – Strategic",
}
def _terr(v): return _TERR_MAP.get(v, f"…{str(v)[-8:]}" if v else "—")

DL_JS = """
<script>
function downloadCSV(tableId, fname) {
  const tbl = document.getElementById(tableId);
  if (!tbl) return;
  let csv = [];
  for (let row of tbl.rows) {
    csv.push(Array.from(row.cells).map(c => '"' + c.innerText.replace(/"/g,'""') + '"').join(','));
  }
  const blob = new Blob([csv.join('\\n')], {type:'text/csv'});
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob);
  a.download = fname; a.click();
}
</script>"""


# ─── 3a: Churn Codes ─────────────────────────────────────────────────────────
def section_churn_reasons(data, quarter):
    if not data:
        return '<div class="card"><p style="color:#9CA3AF">Churn reason data not available.</p></div>'

    # Sort by largest ARR loss first (churn_arr is negative, so ascending = most loss first)
    rows = sorted(data, key=lambda r: float(r.get("churn_arr") or 0))
    # Exclude nulls/not captured for chart clarity — show as footnote
    captured = [r for r in rows if r.get("churn_reason") and r.get("churn_reason") != "Not Captured"]
    not_cap  = next((r for r in rows if r.get("churn_reason") == "Not Captured"), None)

    labels   = [r.get("churn_reason", "Unknown") for r in captured]
    arr_vals = [abs(float(r.get("churn_arr") or 0)) for r in captured]
    opp_vals = [int(r.get("opportunity_count") or 0) for r in captured]
    total_arr = sum(arr_vals)

    chart_h = max(320, len(labels) * 28 + 80)

    # Horizontal bar — ARR by churn reason (sorted largest at top)
    traces = [
        {
            "type": "bar", "name": "Churn ARR",
            "x": arr_vals, "y": labels, "orientation": "h",
            "marker": {"color": RED, "opacity": 0.85},
            "hovertemplate": "<b>%{y}</b><br>Churn ARR: $%{x:,.0f}<br>Opps: %{customdata}<extra></extra>",
            "customdata": opp_vals,
        },
    ]
    layout = {
        "title": {"text": f"Churn ARR by Reason — {quarter} (captured reasons only)", "font": {"size": 14}},
        "xaxis": {"title": "Churn ARR ($)", "tickformat": "$,.0f", "automargin": True},
        "yaxis": {"autorange": "reversed", "automargin": True},
    }
    chart = plotly_chart("churn_reason_chart", traces, layout, height=chart_h)

    # Opportunity count bar
    opp_traces = [
        {
            "type": "bar", "name": "# Opportunities",
            "x": opp_vals, "y": labels, "orientation": "h",
            "marker": {"color": SOFT_PINK, "opacity": 0.9},
            "hovertemplate": "<b>%{y}</b><br>Opps: %{x}<extra></extra>",
        },
    ]
    opp_layout = {
        "title": {"text": "Opportunity Count by Churn Reason", "font": {"size": 14}},
        "xaxis": {"title": "# Opportunities", "automargin": True},
        "yaxis": {"autorange": "reversed", "automargin": True},
    }
    opp_chart = plotly_chart("churn_opp_chart", opp_traces, opp_layout, height=chart_h)

    # Summary table (all rows including not captured)
    tbl_rows = []
    for r in rows:
        a = abs(float(r.get("churn_arr") or 0))
        tbl_rows.append({
            "Churn Reason":   r.get("churn_reason") or "Not Captured",
            "# Opportunities": fmt_count(r.get("opportunity_count")),
            "Churn ARR":      fmt_arr(a),
            "% of Total":     fmt_pct(a / total_arr) if total_arr else "N/A",
        })
    tbl = render_table(tbl_rows, "tbl_churn")

    not_cap_note = ""
    if not_cap:
        nc_arr = abs(float(not_cap.get("churn_arr") or 0))
        nc_opp = int(not_cap.get("opportunity_count") or 0)
        not_cap_note = (
            f'<div class="insight" style="margin-top:12px;">'
            f'<strong>⚠ Not Captured:</strong> {fmt_count(nc_opp)} opportunities totalling '
            f'{fmt_arr(nc_arr)} ({fmt_pct(nc_arr/(total_arr+nc_arr))}) had no churn reason recorded. '
            f'These are excluded from the charts above but included in the table.'
            f'</div>'
        )

    # Top-3 insight
    top3 = captured[:3]
    top3_text = ", ".join(
        f"<b>{r.get('churn_reason')}</b> ({fmt_arr(abs(float(r.get('churn_arr') or 0)))})"
        for r in top3
    )
    pct_top = sum(abs(float(r.get("churn_arr") or 0)) for r in top3) / total_arr if total_arr else 0
    insight = (
        f"Top 3 churn reasons by ARR: {top3_text} — together representing "
        f"<strong>{fmt_pct(pct_top)}</strong> of captured churn ARR in {quarter}."
    )

    return f"""
<section class="section" id="churn_reasons">
  <h2>🔍 Churn Codes Analysis <span class="period-badge">{quarter}</span></h2>
  <div class="card">
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;">
      <div>{chart}</div>
      <div>{opp_chart}</div>
    </div>
  </div>
  <div class="card">
    {tbl}
    <button class="dl-btn" onclick="downloadCSV('tbl_churn','churn_reasons_{quarter}.csv')">⬇ Download CSV</button>
    <p class="source">Source: SALESFORCE.RAW_OPPORTUNITY_REPORT (Closed Lost, {quarter})</p>
  </div>
  {not_cap_note}
  <div class="insight"><strong>What the data shows:</strong> {insight}</div>
</section>"""


# ─── 3b: Top Accounts ────────────────────────────────────────────────────────
def _sol_badge(sol):
    """Render a small colour-coded pill for Single / Multi / Unknown."""
    sol = (sol or "Unknown").strip()
    if sol == "Single":
        bg, fg = SKY_BLUE, FOREST_GREEN
    elif sol == "Multi":
        bg, fg = LIME_GREEN, FOREST_GREEN
    else:
        bg, fg = "#E5E7EB", "#6B7280"
    return (
        f'<span style="background:{bg};color:{fg};border-radius:4px;'
        f'padding:1px 6px;font-size:11px;font-weight:700;white-space:nowrap;">'
        f'{sol}</span>'
    )

def section_top_accounts(renewals, churn_list, quarter):
    parts = []

    # ── Churned accounts table
    if churn_list:
        churn_sorted = sorted(churn_list, key=lambda r: float(r.get("arr_churn") or 0))[:25]

        # Check if any churn codes were captured
        has_churn_codes = any(r.get("type_of_churn") for r in churn_sorted)

        rows = []
        for r in churn_sorted:
            sol  = (r.get("sol_type") or "Unknown").strip()
            prods = r.get("product_groups") or r.get("product_group") or "—"
            churn_code = r.get("type_of_churn") or "—"
            churn_cat  = r.get("churn_category") or "—"
            row = {
                "Account":       r.get("account_name", ""),
                "CSM":           r.get("csm") or "—",
                "Region":        r.get("region", ""),
                "Segment":       r.get("revenue_segment") or r.get("sfdc_segment") or "",
                "Solution":      _sol_badge(sol),
                "Products":      prods,
                "Renewal ARR":   fmt_arr(float(r.get("arr_renewal") or 0)),
                "Churn ARR":     fmt_arr(abs(float(r.get("arr_churn") or 0))),
            }
            if has_churn_codes:
                row["Churn Code"]     = churn_code
                row["Churn Category"] = churn_cat
            rows.append(row)

        tbl = render_table(rows, "tbl_top_churn")

        churn_code_note = ""
        if not has_churn_codes:
            churn_code_note = (
                f'<p class="source" style="margin-top:8px;">'
                f'<strong>ℹ Churn codes:</strong> Account-level codes unavailable — '
                f'Salesforce ACCOUNT_ID does not map directly to Optimizely MASTER_CUSTOMER_ID. '
                f'See the <em>Churn Codes</em> section above for aggregate breakdown.'
                f'</p>'
            )

        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:12px;color:{RED};">
    ⚠️ Top Churned Accounts — {quarter}
  </h3>
  {tbl}
  <button class="dl-btn" onclick="downloadCSV('tbl_top_churn','churned_accounts_{quarter}.csv')">⬇ Download CSV</button>
  {churn_code_note}
  <p class="source">Source: EXEC_DECK_RENEWAL_RATES_CUSTOMER · EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP · SST_REPORT</p>
</div>""")

    # ── Renewed accounts table
    if renewals:
        renewed = sorted(renewals, key=lambda r: -(float(r.get("arr_renewal") or 0)))[:25]
        rows = []
        for r in renewed:
            sol   = (r.get("sol_type") or "Unknown").strip()
            prods = r.get("product_groups") or r.get("product_group") or "—"
            rows.append({
                "Account":     r.get("account_name", ""),
                "CSM":         r.get("csm") or "—",
                "Region":      r.get("region", ""),
                "Segment":     r.get("revenue_segment") or "",
                "ARR Band":    r.get("arr_band") or "",
                "Solution":    _sol_badge(sol),
                "Products":    prods,
                "Renewal ARR": fmt_arr(float(r.get("arr_renewal") or 0)),
                "Churn ARR":   fmt_arr(abs(float(r.get("arr_churn") or 0))),
            })
        tbl2 = render_table(rows, "tbl_top_renewed")
        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:12px;color:{GREEN};">
    ✅ Top Renewed Accounts (by ARR) — {quarter}
  </h3>
  {tbl2}
  <button class="dl-btn" onclick="downloadCSV('tbl_top_renewed','renewed_accounts_{quarter}.csv')">⬇ Download CSV</button>
  <p class="source">Source: EXEC_DECK_RENEWAL_RATES_CUSTOMER · EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP · SST_REPORT</p>
</div>""")

    if not parts:
        return '<div class="card"><p style="color:#9CA3AF">Account detail data not available.</p></div>'

    return f"""
<section class="section" id="top_accounts">
  <h2>📋 Account Detail <span class="period-badge">{quarter}</span></h2>
  {"".join(parts)}
</section>"""


# ─── 3c: EO Deep Dive ────────────────────────────────────────────────────────
def section_eo(data, quarter):
    if not data:
        return '<div class="card"><p style="color:#9CA3AF">EO deep dive data not available.</p></div>'

    eo_by_product   = [r for r in data if r.get("_section") == "eo_by_product"]
    regional        = [r for r in data if r.get("_section") == "regional"]
    opal_corr       = [r for r in data if r.get("_section") == "opal_corr"]
    opal_portfolio  = [r for r in data if r.get("_section") == "opal_portfolio"]
    opal_rr         = [r for r in data if r.get("_section") == "opal_rr"]
    tester          = [r for r in data if r.get("_section") == "tester"]
    next_prod       = [r for r in data if r.get("_section") == "next_prod"]
    next_prod_featex= [r for r in data if r.get("_section") == "next_prod_featex"]

    parts = []

    # ── 1. EO by Product — renewal rate QoQ per product group
    if eo_by_product:
        curr_prod  = [r for r in eo_by_product if r.get("date_yq") == quarter]
        prior_rows = [r for r in eo_by_product if r.get("date_yq") != quarter]
        prior_q    = prior_rows[0].get("date_yq", "Prior") if prior_rows else "Prior"
        prior_prod = {r.get("product_group"): r for r in prior_rows}

        # Sort by current RR descending
        curr_sorted = sorted(curr_prod, key=lambda r: -float(r.get("renewal_rate") or 0))
        prods   = [r.get("product_group", "") for r in curr_sorted]
        curr_rr = [round(float(r.get("renewal_rate") or 0) * 100, 1) for r in curr_sorted]
        prior_rr= [round(float(prior_prod[p].get("renewal_rate") or 0) * 100, 1)
                   if p in prior_prod else 0 for p in prods]
        curr_arr= [float(r.get("renewal_arr") or 0) for r in curr_sorted]
        curr_cnt= [int(r.get("renewal_count") or 0) for r in curr_sorted]

        traces = [
            {"type": "bar", "name": f"Current ({quarter})",
             "x": prods, "y": curr_rr,
             "marker": {"color": FOREST_GREEN},
             "text": [f"{v:.1f}%" for v in curr_rr], "textposition": "auto",
             "hovertemplate": "<b>%{x}</b><br>RR: %{y:.1f}%<br>ARR: $%{customdata[0]:,.0f}<br>Renewals: %{customdata[1]}<extra></extra>",
             "customdata": list(zip(curr_arr, curr_cnt))},
            {"type": "bar", "name": f"Prior ({prior_q})",
             "x": prods, "y": prior_rr,
             "marker": {"color": SKY_BLUE, "opacity": 0.75},
             "hovertemplate": "<b>%{x}</b><br>Prior RR: %{y:.1f}%<extra></extra>"},
        ]
        layout = {
            "barmode": "group",
            "title": {"text": "EO Renewal Rate by Product — QoQ", "font": {"size": 14}},
            "yaxis": {"title": "Renewal Rate (%)", "ticksuffix": "%", "range": [0, 115], "automargin": True},
            "shapes": [{"type":"line","x0":-0.5,"x1":len(prods)-0.5,
                        "y0":90,"y1":90,"line":{"color":GREEN,"width":1.5,"dash":"dash"}}],
            "annotations": [{"x":len(prods)-0.5,"y":90,"xanchor":"right",
                              "text":"90% target","showarrow":False,
                              "font":{"color":GREEN,"size":11}}],
        }
        # QoQ delta table
        tbl_rows = []
        for r in curr_sorted:
            p = r.get("product_group","")
            curr_v = float(r.get("renewal_rate") or 0)
            prev_v = float(prior_prod[p].get("renewal_rate") or 0) if p in prior_prod else None
            delta  = f"{(curr_v - prev_v)*100:+.1f}pp" if prev_v is not None else "—"
            tbl_rows.append({
                "Product":       p,
                "Renewals":      fmt_count(r.get("renewal_count")),
                "Renewal ARR":   fmt_arr(r.get("renewal_arr")),
                "Churn ARR":     fmt_arr(abs(float(r.get("churn_arr") or 0))),
                f"RR ({quarter})": fmt_pct(curr_v),
                f"RR ({prior_q})": fmt_pct(prior_prod[p].get("renewal_rate")) if p in prior_prod else "—",
                "QoQ Δ":         delta,
            })
        tbl = render_table(tbl_rows, "tbl_eo_prod")
        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:10px;">EO Renewal Rate by Product</h3>
  {plotly_chart("eo_by_product", traces, layout, height=320)}
  <div style="margin-top:16px">{tbl}</div>
  <p class="source">Source: EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP (EO products, deduped)</p>
</div>""")

    # ── 2. Regional QoQ
    if regional:
        curr  = [r for r in regional if str(r.get("period","")).lower() == "current"]
        prior = [r for r in regional if str(r.get("period","")).lower() == "prior"]
        regions = sorted({r.get("region","") for r in regional})
        curr_rr  = {r.get("region"): float(r.get("renewal_rate") or 0) * 100 for r in curr}
        prior_rr = {r.get("region"): float(r.get("renewal_rate") or 0) * 100 for r in prior}
        prior_q  = prior[0].get("date_yq", "Prior") if prior else "Prior"
        traces = [
            {"type": "bar", "name": f"Current ({quarter})",
             "x": regions, "y": [curr_rr.get(r, 0) for r in regions],
             "marker": {"color": FOREST_GREEN},
             "text": [f"{curr_rr.get(r,0):.1f}%" for r in regions], "textposition": "auto",
             "hovertemplate": "<b>%{x}</b><br>RR: %{y:.1f}%<extra></extra>"},
            {"type": "bar", "name": f"Prior ({prior_q})",
             "x": regions, "y": [prior_rr.get(r, 0) for r in regions],
             "marker": {"color": SKY_BLUE, "opacity": 0.8},
             "hovertemplate": "<b>%{x}</b><br>Prior RR: %{y:.1f}%<extra></extra>"},
        ]
        layout = {
            "barmode": "group",
            "title": {"text": "EO Renewal Rate by Region — QoQ", "font": {"size": 14}},
            "yaxis": {"title": "Renewal Rate (%)", "ticksuffix": "%", "range": [0, 115], "automargin": True},
        }
        tbl_rows = []
        for r in curr:
            tbl_rows.append({
                "Region":       r.get("region", ""),
                "Renewals":     fmt_count(r.get("renewal_count")),
                "Renewal ARR":  fmt_arr(r.get("renewal_arr")),
                "Churn ARR":    fmt_arr(abs(float(r.get("churn_arr") or 0))),
                "Renewal Rate": fmt_pct(r.get("renewal_rate")),
                "QoQ Δ":        f"{float(r.get('renewal_rate_qoq_delta') or 0)*100:+.1f}pp",
            })
        tbl = render_table(tbl_rows, "tbl_eo_reg")
        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:10px;">EO Renewal Rate by Region</h3>
  {plotly_chart("eo_regional", traces, layout, height=320)}
  {tbl}
  <p class="source">Source: EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP (EO products, deduped)</p>
</div>""")

    # ── 3. Opal Attach yes/no correlation (keep existing)
    if opal_corr:
        labels = [str(r.get("opal_attach", "")) for r in opal_corr]
        rr_v   = [float(r.get("renewal_rate") or 0) * 100 for r in opal_corr]
        arr_v  = [float(r.get("renewal_arr") or 0) for r in opal_corr]
        cnt_v  = [int(r.get("renewal_count") or 0) for r in opal_corr]
        colors = [LIME_GREEN if l.lower() == "yes" else DEEP_TEAL for l in labels]
        traces = [
            {"type": "bar", "name": "Renewal Rate",
             "x": rr_v, "y": [f"Opal: {l}" for l in labels], "orientation": "h",
             "marker": {"color": colors},
             "text": [f"{v:.1f}%" for v in rr_v], "textposition": "outside",
             "hovertemplate": "<b>%{y}</b><br>RR: %{x:.1f}%<br>ARR: $%{customdata[0]:,.0f}<br>Accounts: %{customdata[1]}<extra></extra>",
             "customdata": list(zip(arr_v, cnt_v))},
        ]
        layout = {
            "title": {"text": "EO Renewal Rate: Opal Attach Correlation", "font": {"size": 14}},
            "xaxis": {"title": "Renewal Rate (%)", "ticksuffix": "%", "range": [0, 115], "automargin": True},
            "yaxis": {"automargin": True},
        }
        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:10px;">Opal Attach → EO Renewal Rate Correlation</h3>
  {plotly_chart("eo_opal_corr", traces, layout, height=220)}
  <p class="source">Source: SST_REPORT (Opal) + EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP</p>
</div>""")

    # ── 4. Opal Portfolio: Accounts, ARR, and Renewal Rate by region
    if opal_portfolio or opal_rr:
        # Merge portfolio (accounts + ARR from SST) with RR (from RENEWAL_OPPORTUNITY)
        port_map = {r.get("region",""): r for r in opal_portfolio}
        rr_map   = {r.get("region",""): r for r in opal_rr}
        all_regions = sorted(set(list(port_map.keys()) + list(rr_map.keys())))

        total_accts = sum(int(r.get("opal_account_count") or 0) for r in opal_portfolio)
        total_arr   = sum(float(r.get("opal_arr") or 0) for r in opal_portfolio)
        # Overall RR from RR data (exclude NA which has 0)
        rr_data_with_won = [r for r in opal_rr if float(r.get("won_arr") or 0) > 0]
        total_won_arr  = sum(float(r.get("won_arr") or 0) for r in opal_rr)
        total_lost_arr = sum(float(r.get("lost_arr") or 0) for r in opal_rr)
        overall_rr = total_won_arr / (total_won_arr + total_lost_arr) if (total_won_arr + total_lost_arr) > 0 else None

        kpi_html = f"""
<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:16px;">
  <div style="background:{FOREST_GREEN};color:#fff;border-radius:10px;padding:16px 14px;text-align:center;">
    <div style="font-size:26px;font-weight:800;">{total_accts:,}</div>
    <div style="font-size:11px;margin-top:4px;opacity:0.85;">Active Opal Accounts</div>
  </div>
  <div style="background:{DEEP_TEAL};color:#fff;border-radius:10px;padding:16px 14px;text-align:center;">
    <div style="font-size:26px;font-weight:800;">{fmt_arr(total_arr)}</div>
    <div style="font-size:11px;margin-top:4px;opacity:0.85;">Total Opal ARR</div>
  </div>
  <div style="background:{LIME_GREEN};color:{FOREST_GREEN};border-radius:10px;padding:16px 14px;text-align:center;">
    <div style="font-size:26px;font-weight:800;">{f"{overall_rr*100:.1f}%" if overall_rr else "—"}</div>
    <div style="font-size:11px;margin-top:4px;">Renewal Rate ({quarter})</div>
  </div>
</div>"""

        # Dual chart: accounts by region (bar) + won ARR by region (bar) side by side
        known_regions = [r for r in all_regions if r != "Unknown"]
        acct_v = [int(port_map.get(r, {}).get("opal_account_count") or 0) for r in known_regions]
        arr_v  = [float(port_map.get(r, {}).get("opal_arr") or 0) for r in known_regions]
        won_v  = [float(rr_map.get(r, {}).get("won_arr") or 0) for r in known_regions]
        rr_v   = [float(rr_map.get(r, {}).get("renewal_rate") or 0) * 100 for r in known_regions]
        won_cnt= [int(rr_map.get(r, {}).get("won_accounts") or 0) for r in known_regions]

        traces = [
            {"type": "bar", "name": "Active Accounts (SST)",
             "x": known_regions, "y": acct_v,
             "marker": {"color": FOREST_GREEN, "opacity": 0.85},
             "hovertemplate": "<b>%{x}</b><br>Active: %{y} accounts<br>ARR: $%{customdata:,.0f}<extra></extra>",
             "customdata": arr_v},
            {"type": "bar", "name": "Renewed Accounts (Q2)",
             "x": known_regions, "y": won_cnt,
             "marker": {"color": LIME_GREEN, "opacity": 0.9},
             "hovertemplate": "<b>%{x}</b><br>Renewed: %{y} accounts<br>Won ARR: $%{customdata:,.0f}<extra></extra>",
             "customdata": won_v},
            {"type": "scatter", "mode": "markers+text", "name": "Renewal Rate",
             "x": known_regions,
             "y": [v if v > 0 else None for v in rr_v],
             "yaxis": "y2",
             "marker": {"color": RED, "size": 14, "symbol": "diamond"},
             "text": [f"{v:.1f}%" if v > 0 else "" for v in rr_v],
             "textposition": "top center",
             "hovertemplate": "<b>%{x}</b><br>RR: %{y:.1f}%<extra></extra>"},
        ]
        layout = {
            "barmode": "group",
            "title": {"text": "Opal — Accounts, ARR &amp; Renewal Rate by Region", "font": {"size": 14}},
            "yaxis":  {"title": "Account Count", "automargin": True},
            "yaxis2": {"title": "Renewal Rate (%)", "overlaying": "y", "side": "right",
                       "ticksuffix": "%", "range": [0, 130], "showgrid": False, "automargin": True},
            "legend": {"orientation": "h", "y": 1.08, "x": 0},
        }

        unknown_note = ""
        unk = port_map.get("Unknown")
        if unk:
            unknown_note = (
                f'<p class="source" style="margin-top:8px;">'
                f'<strong>ℹ Region "Unknown"</strong>: {int(unk.get("opal_account_count",0)):,} accounts '
                f'({fmt_arr(unk.get("opal_arr"))}) not shown — EXEC_DECK region join didn\'t match SST snapshot. '
                f'Total includes all regions.</p>'
            )

        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:12px;">Opal Portfolio — Accounts, ARR &amp; Renewal Rate</h3>
  {kpi_html}
  {plotly_chart("opal_portfolio", traces, layout, height=300)}
  {unknown_note}
  <p class="source">Sources: SST_REPORT (active accounts + ARR) · RENEWAL_OPPORTUNITY IS_OPAL=TRUE ({quarter})</p>
</div>""")

    # ── 5. High/Low tester
    if tester:
        types = [r.get("tester_type", "") for r in tester]
        rr_v  = [float(r.get("renewal_rate") or 0) * 100 for r in tester]
        arr_v = [float(r.get("renewal_arr") or 0) for r in tester]
        colors = [GREEN if "High" in t else (AMBER if "No" in t else RED) for t in types]
        traces = [
            {"type": "bar", "name": "Renewal Rate",
             "x": rr_v, "y": types, "orientation": "h",
             "marker": {"color": colors},
             "text": [f"{v:.1f}%" for v in rr_v], "textposition": "outside",
             "hovertemplate": "<b>%{y}</b><br>RR: %{x:.1f}%<br>ARR: $%{customdata:,.0f}<extra></extra>",
             "customdata": arr_v},
        ]
        layout = {
            "title": {"text": "EO RR: High vs Low Testers (≥9 experiments/month = High)", "font": {"size": 14}},
            "xaxis": {"title": "Renewal Rate (%)", "ticksuffix": "%", "range": [0, 115], "automargin": True},
            "yaxis": {"automargin": True},
        }
        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:10px;">Experimentation Intensity vs Renewal Rate</h3>
  {plotly_chart("eo_tester", traces, layout, height=260)}
  <p class="source">Source: EXPERIMENT_METRICS (avg experiments/month threshold ≥9)</p>
</div>""")

    # ── 6. Next product conversion — both cohorts
    if next_prod or next_prod_featex:
        web_data  = {r.get("next_product", ""): r for r in next_prod}
        feat_data = {r.get("next_product", ""): r for r in next_prod_featex}
        all_prods = sorted(
            set(list(web_data.keys()) + list(feat_data.keys())),
            key=lambda p: -max(
                float(web_data[p].get("conversion_rate_pct") or 0)  if p in web_data  else 0,
                float(feat_data[p].get("conversion_rate_pct") or 0) if p in feat_data else 0,
            )
        )
        web_rates  = [float(web_data[p].get("conversion_rate_pct") or 0)  if p in web_data  else None for p in all_prods]
        feat_rates = [float(feat_data[p].get("conversion_rate_pct") or 0) if p in feat_data else None for p in all_prods]
        chart_h = max(380, len(all_prods) * 34 + 110)
        traces = [
            {"type": "bar", "name": "Web Experimentation cohort",
             "x": web_rates, "y": all_prods, "orientation": "h",
             "marker": {"color": FOREST_GREEN, "opacity": 0.9},
             "hovertemplate": "<b>%{y}</b><br>WebEx cohort: %{x:.2f}%<extra></extra>"},
            {"type": "bar", "name": "Feature Experimentation cohort",
             "x": feat_rates, "y": all_prods, "orientation": "h",
             "marker": {"color": LIME_GREEN, "opacity": 0.9},
             "hovertemplate": "<b>%{y}</b><br>FeatEx cohort: %{x:.2f}%<extra></extra>"},
        ]
        layout = {
            "barmode": "group",
            "title": {"text": "Next Product Conversion — Web vs Feature Experimentation Cohorts (%)", "font": {"size": 14}},
            "xaxis": {"title": "Conversion Rate (%)", "ticksuffix": "%", "automargin": True},
            "yaxis": {"autorange": "reversed", "automargin": True},
            "legend": {"orientation": "h", "y": 1.08, "x": 0},
        }
        tbl_rows = []
        for p in all_prods:
            wr = float(web_data[p].get("conversion_rate_pct") or 0)  if p in web_data  else None
            fr = float(feat_data[p].get("conversion_rate_pct") or 0) if p in feat_data else None
            if wr is not None and fr is not None:
                diff = fr - wr
                leader = f"{'FEx' if diff >= 0 else 'Web'} +{abs(diff):.1f}pp"
            else:
                leader = "—"
            web_n  = f"{web_data[p].get('customers_who_added_next_product','')} / {web_data[p].get('customers_who_had_webex_at_start','')}"  if p in web_data  else "—"
            feat_n = f"{feat_data[p].get('customers_who_added_next_product','')} / {feat_data[p].get('customers_who_had_webex_at_start','')}" if p in feat_data else "—"
            tbl_rows.append({
                "Next Product":            p,
                "WebEx rate":              f"{wr:.2f}%" if wr is not None else "—",
                "WebEx n (added/eligible)": web_n,
                "FeatEx rate":             f"{fr:.2f}%" if fr is not None else "—",
                "FeatEx n (added/eligible)": feat_n,
                "Leader":                  leader,
            })
        tbl = render_table(tbl_rows, "tbl_next_prod")
        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:10px;">Next Product Conversion — Web &amp; Feature Experimentation Cohorts</h3>
  {plotly_chart("eo_next_prod", traces, layout, height=chart_h)}
  <div style="margin-top:16px">{tbl}</div>
  <button class="dl-btn" onclick="downloadCSV('tbl_next_prod','next_product_conversion_{quarter}.csv')">⬇ Download CSV</button>
  <p class="source">Source: SST_REPORT snapshots Dec 2025 → May 2026 &nbsp;·&nbsp; {quarter}</p>
</div>""")

    if not parts:
        parts = ['<div class="card"><p style="color:#9CA3AF">EO detail sections not parsed.</p></div>']

    return f"""
<section class="section" id="eo_deep_dive">
  <h2>🧪 EO Deep Dive <span class="period-badge">{quarter}</span></h2>
  {"".join(parts)}
</section>"""


# ─── 3d: OA Analytics ────────────────────────────────────────────────────────
def section_oa(data, quarter):
    if not data:
        return '<div class="card"><p style="color:#9CA3AF">OA analysis data not available.</p></div>'

    customers = [r for r in data if r.get("_section") == "customers"]
    regional  = [r for r in data if r.get("_section") == "regional"]
    trend     = [r for r in data if r.get("_section") == "trend"]

    parts = []

    # ── KPI header row
    if customers:
        total_cust = sum(int(r.get("active_customer_count") or 0) for r in customers)
        region_map = {r.get("region", ""): int(r.get("active_customer_count") or 0) for r in customers}
        na_c  = region_map.get("NA", 0)
        emea_c= region_map.get("EMEA", 0)
        apj_c = region_map.get("APJ", 0)
        kpi_html = f"""
<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:16px;">
  <div style="background:{FOREST_GREEN};color:#fff;border-radius:10px;padding:18px 14px;text-align:center;">
    <div style="font-size:28px;font-weight:800;">{total_cust:,}</div>
    <div style="font-size:12px;margin-top:4px;opacity:0.85;">Total Active Customers</div>
  </div>
  <div style="background:{SKY_BLUE};color:{FOREST_GREEN};border-radius:10px;padding:18px 14px;text-align:center;">
    <div style="font-size:28px;font-weight:800;">{na_c:,}</div>
    <div style="font-size:12px;margin-top:4px;">NA</div>
  </div>
  <div style="background:{SKY_BLUE};color:{FOREST_GREEN};border-radius:10px;padding:18px 14px;text-align:center;">
    <div style="font-size:28px;font-weight:800;">{emea_c:,}</div>
    <div style="font-size:12px;margin-top:4px;">EMEA</div>
  </div>
  <div style="background:{SKY_BLUE};color:{FOREST_GREEN};border-radius:10px;padding:18px 14px;text-align:center;">
    <div style="font-size:28px;font-weight:800;">{apj_c:,}</div>
    <div style="font-size:12px;margin-top:4px;">APJ</div>
  </div>
</div>"""

        # ── Customer count bar chart by region
        reg_sorted = sorted(customers, key=lambda r: -int(r.get("active_customer_count") or 0))
        regs  = [r.get("region", "") for r in reg_sorted]
        cnts  = [int(r.get("active_customer_count") or 0) for r in reg_sorted]
        bar_colors = [FOREST_GREEN if r == "NA" else (SKY_BLUE if r == "EMEA" else LIME_GREEN) for r in regs]
        traces = [
            {"type": "bar", "name": "Active Customers",
             "x": regs, "y": cnts,
             "marker": {"color": bar_colors},
             "text": [str(v) for v in cnts], "textposition": "auto",
             "hovertemplate": "<b>%{x}</b><br>Customers: %{y:,}<extra></extra>"},
        ]
        layout = {
            "title": {"text": "OA Active Customers by Region", "font": {"size": 14}},
            "yaxis": {"title": "Active Customers", "automargin": True},
            "showlegend": False,
        }
        parts.append(f"""
<div class="card">
  {kpi_html}
  {plotly_chart("oa_cust_region", traces, layout, height=280)}
  <p class="source">Source: OA_CUSTOMER_DETAIL (IS_ACTIVE = TRUE)</p>
</div>""")

    # ── Renewal rates by region (bar chart, color-coded, 90% target line)
    if regional:
        reg_sorted = sorted(regional, key=lambda r: -(float(r.get("renewal_rate") or 0)))
        regs   = [r.get("region", "") for r in reg_sorted]
        rr_vals= [round(float(r.get("renewal_rate") or 0) * 100, 1) for r in reg_sorted]
        r_arr  = [float(r.get("renewal_arr") or 0) for r in reg_sorted]
        c_arr  = [abs(float(r.get("churn_arr") or 0)) for r in reg_sorted]

        # Color-code: green ≥90%, amber 80–90%, red <80%
        def rr_color(v):
            if v >= 90: return GREEN
            if v >= 80: return AMBER
            return RED
        colors = [rr_color(v) for v in rr_vals]

        traces = [
            {"type": "bar", "name": "Renewal Rate",
             "x": regs, "y": rr_vals,
             "marker": {"color": colors},
             "text": [f"{v:.1f}%" for v in rr_vals], "textposition": "auto",
             "hovertemplate": (
                 "<b>%{x}</b><br>RR: %{y:.1f}%"
                 "<br>Renewal ARR: $%{customdata[0]:,.0f}"
                 "<br>Churn ARR: -$%{customdata[1]:,.0f}<extra></extra>"
             ),
             "customdata": list(zip(r_arr, c_arr))},
        ]
        layout = {
            "title": {"text": "OA Renewal Rate by Region", "font": {"size": 14}},
            "yaxis": {"title": "Renewal Rate (%)", "ticksuffix": "%",
                      "range": [0, 110], "automargin": True},
            "shapes": [{
                "type": "line", "x0": -0.5, "x1": len(regs) - 0.5,
                "y0": 90, "y1": 90,
                "line": {"color": GREEN, "width": 1.5, "dash": "dash"},
            }],
            "annotations": [{"x": len(regs) - 0.5, "y": 90, "xanchor": "right",
                              "text": "90% target", "showarrow": False,
                              "font": {"color": GREEN, "size": 11}}],
            "showlegend": False,
        }

        # ARR summary table
        tbl_rows = []
        for r in reg_sorted:
            tbl_rows.append({
                "Region":        r.get("region", ""),
                "Renewal ARR":   fmt_arr(r.get("renewal_arr")),
                "Churn ARR":     f"-{fmt_arr(abs(float(r.get('churn_arr') or 0)))}",
                "Renewal Rate":  fmt_pct(r.get("renewal_rate")),
            })
        tbl = render_table(tbl_rows, "tbl_oa_rr")

        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:10px;">OA Renewal Performance by Region</h3>
  {plotly_chart("oa_rr_region", traces, layout, height=280)}
  <div style="margin-top:16px">{tbl}</div>
  <button class="dl-btn" onclick="downloadCSV('tbl_oa_rr','oa_renewal_rates_{quarter}.csv')">⬇ Download CSV</button>
  <p class="source" style="margin-top:8px;">
    Source: OA_CUSTOMER_DETAIL + RAW_OPPORTUNITY_REPORT (Closed Won/Lost, {quarter}) &nbsp;·&nbsp;
    <strong>⚠ Note:</strong> Renewal ARR is account-level (all products), not OA-specific ARR.
  </p>
</div>""")

    # ── Usage trend: dual-axis bar (total expts) + line (avg per customer)
    if trend:
        trend_sorted = sorted(trend, key=lambda r: r.get("activity_month", ""))
        months    = [r.get("activity_month", "") for r in trend_sorted]
        avg_exp   = [round(float(r.get("avg_experiments_started") or 0), 1) for r in trend_sorted]
        total_exp = [int(r.get("total_experiments_started") or 0) for r in trend_sorted]
        cust_cnt  = [int(r.get("active_customer_count") or 0) for r in trend_sorted]

        traces = [
            {"type": "bar", "name": "Total Experiments",
             "x": months, "y": total_exp,
             "marker": {"color": FOREST_GREEN, "opacity": 0.5},
             "hovertemplate": "%{x}<br>Total expts: %{y:,}<extra></extra>"},
            {"type": "scatter", "mode": "lines+markers", "name": "Avg per Customer",
             "x": months, "y": avg_exp, "yaxis": "y2",
             "line": {"color": LIME_GREEN, "width": 3},
             "marker": {"size": 8},
             "hovertemplate": "%{x}<br>Avg: %{y:.1f} expts/customer<extra></extra>"},
        ]
        layout = {
            "title": {"text": "OA Monthly Experiment Activity (OA Active Customer Cohort)", "font": {"size": 14}},
            "yaxis":  {"title": "Total Experiments Started", "automargin": True},
            "yaxis2": {"title": "Avg per Customer", "overlaying": "y", "side": "right",
                       "showgrid": False, "automargin": True},
            "legend": {"orientation": "h", "y": 1.08, "x": 0},
        }
        # Flat customer count note (all 79 = snapshot cohort effect)
        unique_cnts = set(cust_cnt)
        cohort_note = ""
        if len(unique_cnts) == 1:
            cohort_note = (
                f'<div class="insight" style="margin-top:10px;">'
                f'<strong>ℹ Note:</strong> Active customer count is flat ({list(unique_cnts)[0]}) because '
                f'the OA cohort is derived from the current {quarter} snapshot — all accounts appear '
                f'as "active" across historical months. 2026 data not yet available.'
                f'</div>'
            )
        parts.append(f"""
<div class="card">
  {plotly_chart("oa_trend", traces, layout, height=320)}
  <p class="source">Source: EXP_CUSTOMER_ADOPTION_BRAVE joined to OA_CUSTOMER_DETAIL (last 12 months)</p>
  {cohort_note}
</div>""")

    if not parts:
        parts = ['<div class="card"><p style="color:#9CA3AF">OA data not parsed. Check 08_oa_analysis.json.</p></div>']

    return f"""
<section class="section" id="oa_analysis">
  <h2>📊 OA Analytics Deep Dive <span class="period-badge">{quarter}</span></h2>
  {"".join(parts)}
</section>"""


# ─── 3e: CMS PaaS → SaaS ─────────────────────────────────────────────────────
def section_cms(paas_data, portfolio, quarter):
    parts = []

    if paas_data:
        # ── Trend: pivot product_type rows into PaaS vs SaaS lines
        trend_rows = [r for r in paas_data if r.get("_section") == "trend"]
        if trend_rows:
            paas_rows = sorted(
                [r for r in trend_rows if "paas" in str(r.get("product_type","")).lower()],
                key=lambda r: r.get("snapshot_month", "")
            )
            saas_rows = sorted(
                [r for r in trend_rows if "saas" in str(r.get("product_type","")).lower()],
                key=lambda r: r.get("snapshot_month", "")
            )
            months   = [str(r.get("snapshot_month",""))[:7] for r in paas_rows]
            paas_arr = [float(r.get("total_arr") or 0) for r in paas_rows]
            saas_arr = [float(r.get("total_arr") or 0) for r in saas_rows]
            paas_cnt = [int(r.get("customer_count") or 0) for r in paas_rows]
            saas_cnt = [int(r.get("customer_count") or 0) for r in saas_rows]
            traces = [
                {"type": "scatter", "mode": "lines+markers", "name": "CMS PaaS ARR",
                 "x": months, "y": paas_arr, "line": {"color": RED, "width": 3},
                 "hovertemplate": "%{x}<br>PaaS ARR: $%{y:,.0f}<extra></extra>"},
                {"type": "scatter", "mode": "lines+markers", "name": "CMS SaaS ARR",
                 "x": months, "y": saas_arr, "line": {"color": GREEN, "width": 3},
                 "hovertemplate": "%{x}<br>SaaS ARR: $%{y:,.0f}<extra></extra>"},
                {"type": "scatter", "mode": "lines", "name": "PaaS Customers",
                 "x": months, "y": paas_cnt, "yaxis": "y2",
                 "line": {"color": RED, "dash": "dot", "width": 1.5},
                 "hovertemplate": "%{x}<br>PaaS Customers: %{y}<extra></extra>"},
                {"type": "scatter", "mode": "lines", "name": "SaaS Customers",
                 "x": months, "y": saas_cnt, "yaxis": "y2",
                 "line": {"color": GREEN, "dash": "dot", "width": 1.5},
                 "hovertemplate": "%{x}<br>SaaS Customers: %{y}<extra></extra>"},
            ]
            layout = {
                "title": {"text": "CMS PaaS → SaaS Migration: ARR & Customer Trend", "font": {"size": 14}},
                "yaxis":  {"title": "ARR ($)", "tickformat": "$,.0f", "automargin": True},
                "yaxis2": {"title": "Customers", "overlaying": "y", "side": "right",
                           "showgrid": False, "automargin": True},
            }
            parts.append(f"""
<div class="card">
  {plotly_chart("cms_trend", traces, layout, height=340)}
  <p class="source">Source: SST_REPORT (CMS PaaS / SaaS product groups, last 12 months)</p>
</div>""")

        # ── Renewal performance comparison
        renewal_trend = [r for r in paas_data if r.get("_section") == "renewal_trend"]
        if renewal_trend:
            pgs  = [r.get("product_group_cleaned","") for r in renewal_trend]
            rrs  = [round(float(r.get("renewal_rate") or 0)*100, 1) for r in renewal_trend]
            arrs = [float(r.get("renewal_arr") or 0) for r in renewal_trend]
            colors = [RED if "paas" in p.lower() else GREEN for p in pgs]
            traces = [
                {"type": "bar", "name": "Renewal Rate",
                 "x": pgs, "y": rrs,
                 "marker": {"color": colors},
                 "text": [f"{v:.1f}%" for v in rrs], "textposition": "auto",
                 "hovertemplate": "<b>%{x}</b><br>RR: %{y:.1f}%<br>ARR: $%{customdata:,.0f}<extra></extra>",
                 "customdata": arrs},
            ]
            layout = {
                "title": {"text": "CMS Renewal Rate: PaaS vs SaaS", "font": {"size": 14}},
                "yaxis": {"title": "Renewal Rate (%)", "ticksuffix": "%", "range": [0, 110], "automargin": True},
            }
            parts.append(f"""
<div class="card">
  {plotly_chart("cms_rr_compare", traces, layout, height=280)}
  <p class="source">Source: EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP (deduped, {quarter})</p>
</div>""")

        # ── Upcoming (migration customers)
        upcoming = [r for r in paas_data if r.get("_section") == "upcoming"]
        if upcoming:
            up_sorted = sorted(upcoming, key=lambda r: -(float(r.get("total_arr") or 0)))
            rows = []
            for r in up_sorted:
                rows.append({
                    "Account":    r.get("account_name") or "—",
                    "CSM":        r.get("csm") or "—",
                    "Region":     r.get("region") or "—",
                    "PaaS ARR":   fmt_arr(r.get("paas_arr")),
                    "SaaS ARR":   fmt_arr(r.get("saas_arr")),
                    "Total ARR":  fmt_arr(r.get("total_arr")),
                })
            tbl = render_table(rows, "tbl_cms_upcoming")
            parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:10px;">Active Migration Customers (holding both PaaS + SaaS)</h3>
  {tbl}
  <button class="dl-btn" onclick="downloadCSV('tbl_cms_upcoming','cms_migration_{quarter}.csv')">⬇ Download CSV</button>
  <p class="source">Source: SST_REPORT snapshot — accounts with BOTH PaaS and SaaS active</p>
</div>""")

    # ── CMS Portfolio table
    if portfolio:
        rows = []
        for r in portfolio:
            rows.append({
                "Account":      r.get("account_name") or "",
                "CSM":          r.get("cms_manager") or r.get("csm") or "",
                "Region":       r.get("region") or "",
                "Segment":      r.get("revenue_segment") or "",
                "Products":     r.get("product_groups") or "",
                "Renewal ARR":  fmt_arr(r.get("arr_renewal")),
                "Renewal Rate": fmt_pct(r.get("renewal_rate")) if r.get("renewal_rate") else "—",
                "Pipeline":     r.get("pipeline_stage") or "—",
            })
        tbl = render_table(rows, "tbl_cms_port", max_rows=50)
        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:10px;">CMS Portfolio — Top Accounts</h3>
  {tbl}
  <button class="dl-btn" onclick="downloadCSV('tbl_cms_port','cms_portfolio_{quarter}.csv')">⬇ Download CSV</button>
  <p class="source">Source: EXEC_DECK_RENEWAL_RATES_CUSTOMER · SST_REPORT · RENEWAL_OPPORTUNITY</p>
</div>""")

    if not parts:
        parts = ['<div class="card"><p style="color:#9CA3AF">CMS data not available.</p></div>']

    return f"""
<section class="section" id="cms">
  <h2>🖥 CMS PaaS → SaaS <span class="period-badge">{quarter}</span></h2>
  {"".join(parts)}
</section>"""


# ─── 3f: Cross-Sell / Upsell ─────────────────────────────────────────────────
def section_cross_upsell(data, quarter):
    if not data:
        return '<div class="card"><p style="color:#9CA3AF">Cross-sell/upsell data not available.</p></div>'

    cross_rows = sorted(
        [r for r in data if r.get("_section") == "cross_sell"],
        key=lambda r: -float(r.get("total_arr") or 0)
    )
    upsell_rows = sorted(
        [r for r in data if r.get("_section") == "upsell"],
        key=lambda r: -float(r.get("total_arr_increase") or 0)
    )

    # ── Totals for KPI header
    xsell_total_arr   = sum(float(r.get("total_arr") or 0) for r in cross_rows)
    xsell_total_accts = sum(int(r.get("account_count") or 0) for r in cross_rows)
    up_total_arr      = sum(float(r.get("total_arr_increase") or 0) for r in upsell_rows)
    up_total_accts    = sum(int(r.get("account_count") or 0) for r in upsell_rows)

    kpi_html = f"""
<div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:20px;">
  <div style="background:{FOREST_GREEN};color:#fff;border-radius:10px;padding:18px 20px;">
    <div style="font-size:11px;text-transform:uppercase;letter-spacing:1px;opacity:0.75;margin-bottom:6px;">Cross-Sell (new products)</div>
    <div style="font-size:28px;font-weight:800;">{fmt_arr(xsell_total_arr)}</div>
    <div style="font-size:13px;margin-top:4px;opacity:0.85;">{xsell_total_accts:,} account additions across {len(cross_rows)} products</div>
  </div>
  <div style="background:{DEEP_TEAL};color:#fff;border-radius:10px;padding:18px 20px;">
    <div style="font-size:11px;text-transform:uppercase;letter-spacing:1px;opacity:0.75;margin-bottom:6px;">Upsell (ARR expansion)</div>
    <div style="font-size:28px;font-weight:800;">{fmt_arr(up_total_arr)}</div>
    <div style="font-size:13px;margin-top:4px;opacity:0.85;">{up_total_accts:,} accounts expanded across {len(upsell_rows)} products</div>
  </div>
</div>"""

    parts = [f'<div class="card">{kpi_html}<p class="source" style="margin:0;">Source: SST_REPORT snapshots 2026-Q1 → 2026-Q2 (existing customers only)</p></div>']

    # ── Cross-sell chart + table (filter $0 ARR to a footnote)
    if cross_rows:
        has_arr  = [r for r in cross_rows if float(r.get("total_arr") or 0) > 0]
        zero_arr = [r for r in cross_rows if float(r.get("total_arr") or 0) == 0]

        prods   = [r.get("product_group", "") for r in has_arr]
        arr_v   = [float(r.get("total_arr") or 0) for r in has_arr]
        acct_v  = [int(r.get("account_count") or 0) for r in has_arr]
        chart_h = max(300, len(prods) * 30 + 100)

        traces = [
            {"type": "bar", "name": "New ARR",
             "x": arr_v, "y": prods, "orientation": "h",
             "marker": {"color": LIME_GREEN, "opacity": 0.9},
             "hovertemplate": "<b>%{y}</b><br>New ARR: $%{x:,.0f}<br>Accounts: %{customdata}<extra></extra>",
             "customdata": acct_v},
        ]
        layout = {
            "title": {"text": "Cross-Sell — New Product ARR Added (Q1→Q2 2026)", "font": {"size": 14}},
            "xaxis": {"title": "New ARR ($)", "tickformat": "$,.0f", "automargin": True},
            "yaxis": {"autorange": "reversed", "automargin": True},
            "showlegend": False,
        }

        tbl_rows = []
        for r in cross_rows:
            tbl_rows.append({
                "Product":          r.get("product_group", ""),
                "Accounts Added":   fmt_count(r.get("account_count")),
                "New ARR":          fmt_arr(r.get("total_arr")) if float(r.get("total_arr") or 0) > 0 else "—",
            })
        tbl = render_table(tbl_rows, "tbl_xsell")

        zero_note = ""
        if zero_arr:
            zero_prods = ", ".join(r.get("product_group","") for r in zero_arr)
            zero_note = (
                f'<p class="source" style="margin-top:8px;">'
                f'<strong>ℹ $0 ARR products</strong> (likely license/bundled): {zero_prods}</p>'
            )

        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:12px;color:{FOREST_GREEN};">
    ➕ Cross-Sell — Existing customers adding a net-new product
  </h3>
  {plotly_chart("xsell_arr", traces, layout, height=chart_h)}
  <div style="margin-top:16px">{tbl}</div>
  <button class="dl-btn" onclick="downloadCSV('tbl_xsell','cross_sell_{quarter}.csv')">⬇ Download CSV</button>
  {zero_note}
</div>""")

    # ── Upsell chart + table
    if upsell_rows:
        # Top 15 by ARR for chart readability
        chart_rows = upsell_rows[:15]
        prods  = [r.get("product_group", "") for r in chart_rows]
        arr_v  = [float(r.get("total_arr_increase") or 0) for r in chart_rows]
        acct_v = [int(r.get("account_count") or 0) for r in chart_rows]
        chart_h = max(320, len(prods) * 30 + 100)

        traces = [
            {"type": "bar", "name": "ARR Expansion",
             "x": arr_v, "y": prods, "orientation": "h",
             "marker": {"color": SKY_BLUE, "opacity": 0.9},
             "hovertemplate": "<b>%{y}</b><br>ARR Expansion: $%{x:,.0f}<br>Accounts: %{customdata}<extra></extra>",
             "customdata": acct_v},
        ]
        layout = {
            "title": {"text": "Upsell — ARR Expansion on Existing Products (Q1→Q2 2026, top 15)", "font": {"size": 14}},
            "xaxis": {"title": "ARR Increase ($)", "tickformat": "$,.0f", "automargin": True},
            "yaxis": {"autorange": "reversed", "automargin": True},
            "showlegend": False,
        }

        tbl_rows = []
        for r in upsell_rows:
            tbl_rows.append({
                "Product":          r.get("product_group", ""),
                "Accounts Expanded": fmt_count(r.get("account_count")),
                "ARR Increase":     fmt_arr(r.get("total_arr_increase")),
            })
        tbl = render_table(tbl_rows, "tbl_upsell")

        parts.append(f"""
<div class="card">
  <h3 style="font-size:13px;font-weight:700;margin-bottom:12px;color:{DEEP_TEAL};">
    📈 Upsell — Existing customers growing ARR on products they already have
  </h3>
  {plotly_chart("upsell_arr", traces, layout, height=chart_h)}
  <div style="margin-top:16px">{tbl}</div>
  <button class="dl-btn" onclick="downloadCSV('tbl_upsell','upsell_{quarter}.csv')">⬇ Download CSV</button>
</div>""")

    return f"""
<section class="section" id="cross_upsell">
  <h2>🔄 Cross-Sell &amp; Upsell <span class="period-badge">{quarter}</span></h2>
  {"".join(parts)}
</section>"""


# ─── Main ─────────────────────────────────────────────────────────────────────
def build(data_dir: Path, quarter: str, output_dir: Path):
    churn_reason  = load_data(data_dir, "06_churn_reason")
    renewals      = load_data(data_dir, "03_detailed_renewals")
    churn_list    = load_data(data_dir, "04_churn_list")
    eo            = load_data(data_dir, "09_eo_deep_dive")
    oa            = load_data(data_dir, "08_oa_analysis")
    cms_paas      = load_data(data_dir, "10_cms_paas_saas")
    cms_port      = load_data(data_dir, "11_cms_portfolio")
    cross_upsell  = load_data(data_dir, "05_cross_upsell")

    sidebar = """
<nav class="sidebar">
  <a href="#churn_reasons">Churn Codes</a>
  <a href="#top_accounts">Accounts</a>
  <a href="#eo_deep_dive">EO Deep Dive</a>
  <a href="#oa_analysis">OA Analytics</a>
  <a href="#cms">CMS PaaS→SaaS</a>
  <a href="#cross_upsell">Cross/Upsell</a>
</nav>"""

    content = f"""
<div class="layout">
{sidebar}
<div class="main">
{section_churn_reasons(churn_reason, quarter)}
{section_top_accounts(renewals, churn_list, quarter)}
{section_eo(eo, quarter)}
{section_oa(oa, quarter)}
{section_cms(cms_paas, cms_port, quarter)}
{section_cross_upsell(cross_upsell, quarter)}
{DL_JS}
</div>
</div>"""

    html = (
        html_head(f"Deep Analyses — {quarter}")
        + html_topbar("CS Deep Analyses", quarter)
        + content
        + html_footer([
            "RAW_OPPORTUNITY_REPORT",
            "EXEC_DECK_RENEWAL_RATES_CUSTOMER",
            "SST_REPORT",
            "EXP_CUSTOMER_ADOPTION_BRAVE",
        ])
    )
    return save_html(html, output_dir, "03_deep_analyses.html")


# ─── CLI ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Build Deep Analyses Dashboard")
    ap.add_argument("--data",    required=True)
    ap.add_argument("--quarter", required=True)
    ap.add_argument("--out",     default="../output")
    args = ap.parse_args()
    build(Path(args.data), args.quarter, Path(args.out))
