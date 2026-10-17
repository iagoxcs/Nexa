#!/usr/bin/env python3
"""Gera supabase/seed/source_review.sql a partir da revisão F0-07.

Entradas:
- docs/coverage-reports/f0-07/review.json   (saída de scripts/review_sources.py; preliminar)
- docs/coverage-reports/f0-07/decisions.csv (decisão humana após leitura dos termos de uso)

decisions.csv — uma linha por fonte revisada por Iago:
  master_list_no, tos_url, tos_findings, access_method, approved_by, approved_at (AAAA-MM-DD)
  access_method ∈ crawler | browser | api | manual | blocked

Regras:
- sem linha em decisions.csv → review_status = 'preliminary', fonte inativa;
- com linha → review_status = 'approved' (ou 'rejected' se access_method = blocked),
  tos_reviewed_at/by preenchidos. A ativação (active = true) continua manual.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REVIEW_DIR = ROOT / "docs" / "coverage-reports" / "f0-07"
OUT = ROOT / "supabase" / "seed" / "source_review.sql"
ALLOWED_METHODS = {"crawler", "browser", "api", "manual", "blocked"}


def q(v) -> str:
    if v is None or v == "":
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    return "'" + str(v).replace("'", "''") + "'"


def arr(values: list[str]) -> str:
    return "array[" + ", ".join(q(v) for v in values) + "]::text[]" if values else "'{}'::text[]"


def build_sql(reviews: list[dict], decisions: dict[int, dict]) -> str:
    out = [
        "-- =============================================================================",
        "-- NEXA LAB — F0-07 — Revisão de compliance das fontes",
        "-- GERADO por scripts/gen_source_review_sql.py. Não editar à mão.",
        "-- =============================================================================",
        "",
    ]
    for r in reviews:
        d = decisions.get(int(r["master_list_no"]))
        root_allowed = r.get("robots_allowed_paths", {}).get("/")
        robots_allowed = None if r.get("robots_status") not in (200, 404) else (True if r.get("robots_status") == 404 else bool(root_allowed))
        notes = " | ".join(r.get("notes", []))
        sets = [
            f"robots_allowed = {q(robots_allowed)}",
            f"robots_checked_at = {q(r['reviewed_at'])}",
            f"sitemap_urls = {arr(r.get('sitemaps', []))}",
            f"ecommerce_platform = coalesce({q(r.get('ecommerce_platform'))}, ecommerce_platform)",
        ]
        if r.get("crawl_delay"):
            sets.append(f"rate_limit_rps = least(coalesce(rate_limit_rps, 1), {round(1 / float(r['crawl_delay']), 3)})")
        if d:
            method = d["access_method"].strip()
            if method not in ALLOWED_METHODS:
                raise ValueError(f"access_method inválido para {r['master_list_no']}: {method}")
            if not d.get("approved_by") or not d.get("approved_at"):
                raise ValueError(f"decisão sem approved_by/approved_at para {r['master_list_no']}")
            sets += [
                f"access_method = {q(method)}",
                f"review_status = {q('rejected' if method == 'blocked' else 'approved')}",
                f"tos_url = {q(d.get('tos_url'))}",
                f"tos_reviewed_at = {q(d['approved_at'])}",
                f"tos_reviewed_by = {q(d['approved_by'])}",
                f"tos_review_notes = {q(d.get('tos_findings'))}",
            ]
        else:
            sets += [
                "review_status = 'preliminary'",
                f"tos_url = coalesce(tos_url, {q((r.get('tos_candidates') or [None])[0])})",
                f"tos_review_notes = {q('Preliminar (automática): acesso sugerido ' + r['preliminary_access_method'] + ('. ' + notes if notes else ''))}",
            ]
        out.append(f"-- [{r['master_list_no']}] {r['brand']}")
        out.append(f"update ops.source set\n  " + ",\n  ".join(sets) + f"\nwhere base_url = {q(r['base_url'])};\n")
    return "\n".join(out) + "\n"


def main() -> int:
    reviews = json.loads((REVIEW_DIR / "review.json").read_text(encoding="utf-8"))
    decisions: dict[int, dict] = {}
    dpath = REVIEW_DIR / "decisions.csv"
    if dpath.exists():
        with dpath.open(encoding="utf-8") as f:
            decisions = {int(row["master_list_no"]): row for row in csv.DictReader(f) if row.get("master_list_no")}
    OUT.write_text(build_sql(reviews, decisions), encoding="utf-8")
    print(f"escrito: {OUT.relative_to(ROOT)} ({len(reviews)} fontes, {len(decisions)} decisões)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
