"""
run_dashboards.py — Orchestrator
=================================
Full workflow:
  1. Reads JSON data files from the /data directory
     (populated by the cs-portfolio-analytics skill via Snowflake MCP)
  2. Calls 01, 02, 03 dashboard scripts to produce HTML files
  3. Saves output HTML to /output directory
  4. Optionally opens output in the browser

Usage (after data is saved by the cs-portfolio-analytics skill):

  cd dashboards/scripts
  python run_dashboards.py --quarter 2026-Q1

  # Run only specific dashboards:
  python run_dashboards.py --quarter 2026-Q1 --only global
  python run_dashboards.py --quarter 2026-Q1 --only breakdowns
  python run_dashboards.py --quarter 2026-Q1 --only deep

  # Custom data and output directories:
  python run_dashboards.py --quarter 2026-Q1 --data /path/to/data --out /path/to/output

  # Open in browser after generation:
  python run_dashboards.py --quarter 2026-Q1 --open

─────────────────────────────────────────────────────────────────────────────
HOW DATA FILES ARE PRODUCED (via cs-portfolio-analytics skill + Snowflake MCP)
─────────────────────────────────────────────────────────────────────────────
The cs-portfolio-analytics skill runs SQL queries via mcp__snowflake__run_snowflake_query
and returns row dicts. Claude saves those results as JSON using save_query_result() below.

Filename convention:
  data/01_scorecard_totals.json       ← query 01
  data/01_scorecard_trend.json        ← optional: global multi-quarter trend
  data/01_regional_trend.json         ← NA & EMEA trend (sql/01_regional_trend.sql)
  data/02_scorecard_dimensions.json   ← query 02
  data/03_detailed_renewals.json      ← query 03
  data/04_churn_list.json             ← query 04
  data/05_cross_upsell.json           ← query 05
  data/06_churn_reason.json           ← query 06
  data/07_opal_analysis.json          ← query 07 (tagged with _section key)
  data/08_oa_analysis.json            ← query 08 (tagged with _section key)
  data/09_eo_deep_dive.json           ← query 09 (tagged with _section key)
  data/10_cms_paas_saas.json          ← query 10 (tagged with _section key)
  data/11_cms_portfolio.json          ← query 11

Multi-query files (07–10) return multiple result sets. Claude should merge them
into a single JSON list, tagging each row with a "_section" key:
  "pipeline"  → 07_opal_analysis pipeline rows
  "attach"    → 07_opal_analysis attach rate rows
  "renewals"  → 07_opal_analysis renewal rows
  "trend"     → 08/09/10 trend rows
  "region"    → 08/09 regional rows
  "customers" → 08 customer list
  "regional"  → 09 EO regional comparison
  "opal_corr" → 09 Opal attach correlation
  "tester"    → 09 high/low tester
  "next_prod" → 09 next product probability
  "trend"     → 10 PaaS/SaaS trend
  "upcoming"  → 10 upcoming PaaS renewals

─────────────────────────────────────────────────────────────────────────────
"""

import argparse
import importlib.util
import json
import os
import subprocess
import sys
import webbrowser
from pathlib import Path
from datetime import datetime

# Resolve directories relative to this script
SCRIPT_DIR  = Path(__file__).parent
DATA_DIR    = SCRIPT_DIR.parent / "data"
OUTPUT_DIR  = SCRIPT_DIR.parent / "output"


# ─── Save helper (used by Claude/cs-portfolio-analytics skill) ────────────────
def save_query_result(rows: list[dict], query_name: str,
                      data_dir: Path = DATA_DIR,
                      section_tag: str = None) -> Path:
    """
    Saves Snowflake query result rows to a JSON file.
    If section_tag is given, adds a '_section' key to every row (for multi-query files).

    Call this from Claude after running each Snowflake query:
      save_query_result(rows, "07_opal_analysis", section_tag="pipeline")

    For multi-query files, call once per result set with different section_tag.
    The function APPENDS to existing file if it exists (for merging multi-query results).
    """
    data_dir.mkdir(parents=True, exist_ok=True)
    path = data_dir / f"{query_name}.json"

    if section_tag:
        for row in rows:
            row["_section"] = section_tag

    existing = []
    if path.exists():
        try:
            existing = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            pass

    combined = existing + rows
    path.write_text(json.dumps(combined, indent=2, default=str), encoding="utf-8")
    print(f"[SAVED] {path.name} — {len(rows)} rows (total {len(combined)})")
    return path


def overwrite_query_result(rows: list[dict], query_name: str,
                            data_dir: Path = DATA_DIR,
                            section_tag: str = None) -> Path:
    """Like save_query_result but always overwrites existing file."""
    data_dir.mkdir(parents=True, exist_ok=True)
    path = data_dir / f"{query_name}.json"
    if section_tag:
        for row in rows:
            row["_section"] = section_tag
    path.write_text(json.dumps(rows, indent=2, default=str), encoding="utf-8")
    print(f"[SAVED] {path.name} — {len(rows)} rows")
    return path


# ─── Main orchestrator ────────────────────────────────────────────────────────
def run(quarter: str, data_dir: Path, output_dir: Path,
        only: str = None, open_browser: bool = False):

    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"\n{'='*60}")
    print(f"CS Leadership Dashboards — {quarter}")
    print(f"Data:   {data_dir}")
    print(f"Output: {output_dir}")
    print(f"{'='*60}\n")

    generated = []

    # ── 01 Global Snapshot ────────────────────────────────────────────────────
    if only in (None, "global", "01"):
        print("[1/3] Building Global Snapshot...")
        try:
            spec = importlib.util.spec_from_file_location(
                "gs", SCRIPT_DIR / "01_global_snapshot.py")
            mod  = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            out  = mod.build(data_dir, quarter, output_dir)
            if out:
                generated.append(out)
        except Exception as e:
            print(f"  [ERROR] Global Snapshot failed: {e}")

    # ── 02 Breakdowns ─────────────────────────────────────────────────────────
    if only in (None, "breakdowns", "02"):
        print("[2/3] Building Dimension Breakdowns...")
        try:
            spec = importlib.util.spec_from_file_location(
                "bd", SCRIPT_DIR / "02_breakdowns.py")
            mod  = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            out  = mod.build(data_dir, quarter, output_dir)
            if out:
                generated.append(out)
        except Exception as e:
            print(f"  [ERROR] Breakdowns failed: {e}")

    # ── 03 Deep Analyses ──────────────────────────────────────────────────────
    if only in (None, "deep", "03"):
        print("[3/3] Building Deep Analyses...")
        try:
            spec = importlib.util.spec_from_file_location(
                "da", SCRIPT_DIR / "03_deep_analyses.py")
            mod  = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            out  = mod.build(data_dir, quarter, output_dir)
            if out:
                generated.append(out)
        except Exception as e:
            print(f"  [ERROR] Deep Analyses failed: {e}")

    # ── Summary ───────────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f"Done. {len(generated)} dashboard(s) generated:")
    for p in generated:
        print(f"  → {p}")
    print(f"{'='*60}\n")

    if open_browser and generated:
        for p in generated:
            webbrowser.open(p.as_uri())

    return generated


# ─── CLI ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    ap = argparse.ArgumentParser(
        description="Generate CS Leadership Dashboards from Snowflake data",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument("--quarter", required=True,
                    help="Target quarter, e.g. 2026-Q1")
    ap.add_argument("--data",    default=str(DATA_DIR),
                    help="Directory containing JSON data files (default: ../data)")
    ap.add_argument("--out",     default=str(OUTPUT_DIR),
                    help="Output directory for HTML files (default: ../output)")
    ap.add_argument("--only",    choices=["global","01","breakdowns","02","deep","03"],
                    help="Build only one dashboard")
    ap.add_argument("--open",    action="store_true",
                    help="Open generated HTML files in the browser")
    args = ap.parse_args()

    run(
        quarter=args.quarter,
        data_dir=Path(args.data),
        output_dir=Path(args.out),
        only=args.only,
        open_browser=args.open,
    )
