#!/usr/bin/env python3
"""Revisão preliminar de compliance das fontes (F0-07).

Para cada marca informada (por master_list_no em supabase/seed/brands.csv):
- lê o robots.txt e verifica se o User-Agent do NEXA pode acessar caminhos de produto;
- coleta os Sitemaps declarados;
- identifica a plataforma de e-commerce pela resposta da home (cabeçalhos e HTML);
- localiza links candidatos para os termos de uso.

A leitura jurídica dos termos de uso NÃO é automatizada: o resultado é
review_status = 'preliminary'. A aprovação (review_status = 'approved',
tos_reviewed_at, tos_reviewed_by, access_method) é registrada por Iago.

Respeita C-01/C-02/C-05: User-Agent identificável, uma requisição por recurso,
intervalo mínimo entre requisições ao mesmo domínio, sem contornar bloqueio
(403/429/CAPTCHA são registrados como resultado).

Uso:
  python3 scripts/review_sources.py --brands 1,5,7 [--out docs/coverage-reports/f0-07]
  python3 scripts/review_sources.py --mvp-candidates
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import urllib.robotparser
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlparse

ROOT = Path(__file__).resolve().parent.parent
BRANDS_CSV = ROOT / "supabase" / "seed" / "brands.csv"
DEFAULT_OUT = ROOT / "docs" / "coverage-reports" / "f0-07"
USER_AGENT = os.environ.get("NEXA_USER_AGENT", "NexaLabBot/0.1 (+https://github.com/iagoxcs/Nexa)")
UA_TOKEN = "NexaLabBot"
DOMAIN_DELAY_S = float(os.environ.get("NEXA_REVIEW_DELAY_S", "3"))
TIMEOUT_S = 20

# Candidatos ao MVP (F1-01): P1-A + P1 com site brasileiro. Seleção final de 20
# após esta revisão, com validação da Thaís.
MVP_CANDIDATES = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]

# Caminhos típicos de produto/categoria por plataforma, usados para testar o robots.txt.
PROBE_PATHS = ["/", "/sitemap.xml", "/produtos", "/products/exemplo", "/p", "/exemplo/p", "/collections/all", "/busca?q=protetor"]

PLATFORM_SIGNS = {
    "vtex": [r"x-vtex-", r"vtexassets\.com", r"vteximg\.com\.br", r"vtex\.com"],
    "shopify": [r"x-shopid", r"cdn\.shopify\.com", r"shopify-digital-wallet", r"myshopify\.com"],
    "nuvemshop": [r"nuvemshop", r"tiendanube", r"d26lpennugtm8s\.cloudfront\.net"],
    "magento": [r"mage/cookies", r"magento", r"x-magento-"],
    "salesforce_commerce": [r"demandware", r"dwanonymous_", r"/on/demandware\.store/"],
    "wake_commerce": [r"fbits", r"wake\.tech", r"traycorp"],
    "loja_integrada": [r"lojaintegrada"],
}
TOS_PATTERN = re.compile(r"termos|terms|condi[cç][oõ]es\s+(gerais\s+)?de\s+uso|pol[ií]tica\s+de\s+uso|legal", re.I)
BLOCK_PATTERN = re.compile(r"captcha|cf-chl|challenge-platform|access denied|attention required", re.I)


@dataclass
class ReviewResult:
    master_list_no: int
    brand: str
    base_url: str
    reviewed_at: str
    robots_url: str = ""
    robots_status: int | None = None
    robots_outcome: str = ""
    robots_allowed_paths: dict[str, bool] = field(default_factory=dict)
    crawl_delay: float | None = None
    sitemaps: list[str] = field(default_factory=list)
    home_status: int | None = None
    home_outcome: str = ""
    ecommerce_platform: str | None = None
    tos_candidates: list[str] = field(default_factory=list)
    preliminary_access_method: str = "pending_review"
    notes: list[str] = field(default_factory=list)


class _LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str]] = []
        self._href: str | None = None
        self._text: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self._href = dict(attrs).get("href")
            self._text = []

    def handle_data(self, data):
        if self._href is not None:
            self._text.append(data)

    def handle_endtag(self, tag):
        if tag == "a" and self._href is not None:
            self.links.append((self._href, " ".join("".join(self._text).split())))
            self._href = None


def parse_robots(text: str, base_url: str, paths: list[str]) -> tuple[dict[str, bool], list[str], float | None]:
    """Avalia o robots.txt para o UA do NEXA. Retorna (permissões por caminho, sitemaps, crawl-delay)."""
    rp = urllib.robotparser.RobotFileParser()
    rp.parse(text.splitlines())
    origin = f"{urlparse(base_url).scheme}://{urlparse(base_url).netloc}"
    allowed = {p: rp.can_fetch(UA_TOKEN, urljoin(origin, p)) for p in paths}
    sitemaps = rp.site_maps() or []
    delay = rp.crawl_delay(UA_TOKEN)
    return allowed, list(sitemaps), float(delay) if delay is not None else None


def detect_platform(headers: dict[str, str], html: str) -> str | None:
    blob = "\n".join(f"{k}: {v}" for k, v in headers.items()).lower() + "\n" + html[:300_000].lower()
    for platform, signs in PLATFORM_SIGNS.items():
        if any(re.search(s, blob) for s in signs):
            return platform
    return None


def find_tos_links(html: str, page_url: str) -> list[str]:
    parser = _LinkParser()
    parser.feed(html)
    found: list[str] = []
    for href, text in parser.links:
        if href and (TOS_PATTERN.search(text) or TOS_PATTERN.search(href)):
            url = urljoin(page_url, href)
            if url not in found and urlparse(url).scheme in ("http", "https"):
                found.append(url)
    return found[:5]


def classify_preliminary(result: ReviewResult) -> str:
    """Método de acesso preliminar. Nunca 'approved': depende da leitura dos termos."""
    if result.robots_outcome in ("blocked", "captcha") or result.home_outcome in ("blocked", "captcha"):
        return "blocked"
    if result.robots_allowed_paths and not result.robots_allowed_paths.get("/", True):
        return "blocked"
    if result.home_status and result.home_status < 400:
        return "crawler"
    return "pending_review"


def _fetch(url: str) -> tuple[int | None, dict[str, str], str, str]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept-Language": "pt-BR,pt;q=0.9"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
            body = resp.read(2_000_000).decode(resp.headers.get_content_charset() or "utf-8", "replace")
            return resp.status, {k.lower(): v for k, v in resp.headers.items()}, body, "ok"
    except urllib.error.HTTPError as e:
        body = e.read(200_000).decode("utf-8", "replace") if e.fp else ""
        outcome = "rate_limited" if e.code == 429 else "blocked" if e.code in (401, 403) else "not_found" if e.code == 404 else "error"
        if BLOCK_PATTERN.search(body):
            outcome = "captcha"
        return e.code, {k.lower(): v for k, v in (e.headers or {}).items()}, body, outcome
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        return None, {}, "", f"network_error: {e}"


def review(row: dict[str, str], out_dir: Path) -> ReviewResult:
    base = row["source_base_url"]
    origin = f"{urlparse(base).scheme}://{urlparse(base).netloc}"
    res = ReviewResult(int(row["master_list_no"]), row["name"], base, datetime.now(timezone.utc).isoformat())

    res.robots_url = origin + "/robots.txt"
    status, _, body, outcome = _fetch(res.robots_url)
    res.robots_status, res.robots_outcome = status, outcome
    if status == 200:
        (out_dir / "robots").mkdir(parents=True, exist_ok=True)
        (out_dir / "robots" / f"{urlparse(base).netloc}.txt").write_text(body, encoding="utf-8")
        res.robots_allowed_paths, res.sitemaps, res.crawl_delay = parse_robots(body, base, PROBE_PATHS)
    elif status == 404:
        res.notes.append("robots.txt inexistente (404): sem restrições declaradas; termos de uso decidem.")
    time.sleep(max(DOMAIN_DELAY_S, res.crawl_delay or 0))

    if res.robots_allowed_paths.get("/", True):
        status, headers, html, outcome = _fetch(base)
        res.home_status, res.home_outcome = status, outcome
        if html:
            res.ecommerce_platform = detect_platform(headers, html)
            res.tos_candidates = find_tos_links(html, base)
        if status and status < 400 and BLOCK_PATTERN.search(html or ""):
            res.home_outcome = "captcha"
    else:
        res.notes.append("Home não acessada: robots.txt não permite '/' para o UA do NEXA.")

    res.preliminary_access_method = classify_preliminary(res)
    if not res.tos_candidates:
        res.notes.append("Link de termos de uso não localizado na home: localizar manualmente.")
    return res


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--brands", help="master_list_no separados por vírgula")
    ap.add_argument("--mvp-candidates", action="store_true", help="revisa os 23 candidatos ao MVP")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()

    ids = MVP_CANDIDATES if args.mvp_candidates else [int(x) for x in (args.brands or "").split(",") if x]
    if not ids:
        ap.error("informe --brands ou --mvp-candidates")
    with BRANDS_CSV.open(encoding="utf-8") as f:
        rows = {int(r["master_list_no"]): r for r in csv.DictReader(f)}

    args.out.mkdir(parents=True, exist_ok=True)
    seen: set[str] = set()
    results = []
    for i in ids:
        row = rows[i]
        if row["source_base_url"] in seen:
            continue
        seen.add(row["source_base_url"])
        print(f"[{i:>3}] {row['name']} — {row['source_base_url']}", file=sys.stderr)
        results.append(review(row, args.out))

    (args.out / "review.json").write_text(json.dumps([asdict(r) for r in results], ensure_ascii=False, indent=2), encoding="utf-8")
    with (args.out / "review.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["master_list_no", "brand", "base_url", "robots_status", "robots_outcome", "root_allowed",
                    "sitemaps", "crawl_delay", "home_status", "home_outcome", "ecommerce_platform",
                    "tos_candidates", "preliminary_access_method", "notes", "reviewed_at"])
        for r in results:
            w.writerow([r.master_list_no, r.brand, r.base_url, r.robots_status, r.robots_outcome,
                        r.robots_allowed_paths.get("/", ""), " ".join(r.sitemaps), r.crawl_delay, r.home_status,
                        r.home_outcome, r.ecommerce_platform or "", " ".join(r.tos_candidates),
                        r.preliminary_access_method, " | ".join(r.notes), r.reviewed_at])
    print(f"escrito: {args.out / 'review.csv'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
