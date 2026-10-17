"""Testes offline do ferramental F0-07 (sem rede). Executar: python3 -m unittest discover -s tests/python"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import gen_source_review_sql as gen  # noqa: E402
import review_sources as rs  # noqa: E402

ROBOTS = """
User-agent: *
Disallow: /checkout
Disallow: /busca
Crawl-delay: 5
Sitemap: https://loja.test/sitemap.xml

User-agent: GPTBot
Disallow: /
"""


class ParseRobotsTest(unittest.TestCase):
    def test_permissions_sitemaps_and_delay(self):
        allowed, sitemaps, delay = rs.parse_robots(ROBOTS, "https://loja.test", ["/", "/produto/p", "/busca?q=x", "/checkout"])
        self.assertTrue(allowed["/"])
        self.assertTrue(allowed["/produto/p"])
        self.assertFalse(allowed["/busca?q=x"])
        self.assertFalse(allowed["/checkout"])
        self.assertEqual(sitemaps, ["https://loja.test/sitemap.xml"])
        self.assertEqual(delay, 5.0)

    def test_disallow_all(self):
        allowed, _, _ = rs.parse_robots("User-agent: *\nDisallow: /\n", "https://x.test", ["/"])
        self.assertFalse(allowed["/"])


class DetectPlatformTest(unittest.TestCase):
    def test_vtex_header(self):
        self.assertEqual(rs.detect_platform({"x-vtex-cache-status": "HIT"}, "<html></html>"), "vtex")

    def test_shopify_html(self):
        self.assertEqual(rs.detect_platform({}, '<script src="https://cdn.shopify.com/s/x.js"></script>'), "shopify")

    def test_unknown(self):
        self.assertIsNone(rs.detect_platform({"server": "nginx"}, "<html>loja</html>"))


class FindTosTest(unittest.TestCase):
    def test_finds_terms_links(self):
        html = '<a href="/institucional/termos-de-uso">Termos de Uso</a><a href="/sobre">Sobre</a>' \
               '<a href="https://loja.test/legal">Condições gerais de uso</a>'
        links = rs.find_tos_links(html, "https://loja.test/")
        self.assertIn("https://loja.test/institucional/termos-de-uso", links)
        self.assertIn("https://loja.test/legal", links)
        self.assertNotIn("https://loja.test/sobre", links)


class ClassifyTest(unittest.TestCase):
    def _r(self, **kw):
        r = rs.ReviewResult(1, "M", "https://m.test", "2026-10-17T00:00:00+00:00")
        for k, v in kw.items():
            setattr(r, k, v)
        return r

    def test_captcha_is_blocked(self):
        self.assertEqual(rs.classify_preliminary(self._r(home_outcome="captcha")), "blocked")

    def test_root_disallowed_is_blocked(self):
        self.assertEqual(rs.classify_preliminary(self._r(robots_allowed_paths={"/": False})), "blocked")

    def test_ok_is_crawler_candidate(self):
        self.assertEqual(rs.classify_preliminary(self._r(robots_allowed_paths={"/": True}, home_status=200)), "crawler")


class BuildSqlTest(unittest.TestCase):
    REVIEW = {"master_list_no": 1, "brand": "Ollie", "base_url": "https://meuollie.com.br",
              "reviewed_at": "2026-10-17T00:00:00+00:00", "robots_status": 200,
              "robots_allowed_paths": {"/": True}, "sitemaps": ["https://meuollie.com.br/sitemap.xml"],
              "crawl_delay": 5, "ecommerce_platform": "vtex", "tos_candidates": ["https://meuollie.com.br/termos"],
              "preliminary_access_method": "crawler", "notes": []}

    def test_preliminary_without_decision(self):
        sql = gen.build_sql([self.REVIEW], {})
        self.assertIn("review_status = 'preliminary'", sql)
        self.assertNotIn("tos_reviewed_at", sql)
        self.assertIn("rate_limit_rps = least(coalesce(rate_limit_rps, 1), 0.2)", sql)

    def test_approved_with_decision(self):
        d = {"access_method": "crawler", "approved_by": "Iago", "approved_at": "2026-10-20", "tos_url": "https://meuollie.com.br/termos",
             "tos_findings": "Sem vedação a coleta automatizada de páginas públicas"}
        sql = gen.build_sql([self.REVIEW], {1: d})
        self.assertIn("review_status = 'approved'", sql)
        self.assertIn("tos_reviewed_by = 'Iago'", sql)
        self.assertNotIn("active", sql)

    def test_blocked_decision_is_rejected(self):
        d = {"access_method": "blocked", "approved_by": "Iago", "approved_at": "2026-10-20"}
        self.assertIn("review_status = 'rejected'", gen.build_sql([self.REVIEW], {1: d}))

    def test_decision_requires_approver(self):
        with self.assertRaises(ValueError):
            gen.build_sql([self.REVIEW], {1: {"access_method": "crawler", "approved_by": "", "approved_at": ""}})


if __name__ == "__main__":
    unittest.main()
