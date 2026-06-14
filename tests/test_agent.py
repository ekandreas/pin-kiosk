"""Enhetstester för kiosk-agenten. Kör: python3 -m unittest -v"""
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "kiosk" / "agent"))

import kiosk_agent as ka  # noqa: E402


class ConfigTests(unittest.TestCase):
    def test_defaults_have_monitor_id_2(self):
        self.assertEqual(ka.DEFAULTS["MONITOR_ID"], "2")

    def test_load_config_overrides(self, ):
        import tempfile, os
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as fh:
            fh.write("# kommentar\nMONITOR_ID=7\nAPI_BASE_URL='https://x.test'\n\n")
            path = fh.name
        try:
            cfg = ka.load_config([path])
            self.assertEqual(cfg["MONITOR_ID"], "7")
            self.assertEqual(cfg["API_BASE_URL"], "https://x.test")
            # Värden som inte angavs faller tillbaka på default.
            self.assertEqual(cfg["POLL_INTERVAL"], "300")
        finally:
            os.unlink(path)

    def test_cfg_int_fallback(self):
        self.assertEqual(ka.cfg_int({"X": "abc"}, "X", 42), 42)
        self.assertEqual(ka.cfg_int({"X": "10"}, "X", 42), 10)


class TtlTests(unittest.TestCase):
    def test_parse_ttl_with_offset(self):
        dt = ka.parse_ttl("2026-06-15T08:00:00+02:00")
        self.assertIsNotNone(dt)
        self.assertEqual(dt.utcoffset(), timedelta(hours=2))

    def test_parse_ttl_invalid(self):
        self.assertIsNone(ka.parse_ttl("inte-ett-datum"))
        self.assertIsNone(ka.parse_ttl(None))

    def test_seconds_until_future(self):
        future = datetime.now(timezone.utc) + timedelta(seconds=120)
        self.assertGreater(ka.seconds_until(future), 60)


class ClampTests(unittest.TestCase):
    def test_clamp(self):
        self.assertEqual(ka.clamp(5, 10, 20), 10)
        self.assertEqual(ka.clamp(25, 10, 20), 20)
        self.assertEqual(ka.clamp(15, 10, 20), 15)


class DecisionTests(unittest.TestCase):
    """Verifierar vad agenten väljer att visa, utan att starta Chromium."""

    def setUp(self):
        args = ka.build_parser().parse_args(["--no-browser", "--once"])
        self.agent = ka.KioskAgent(args)
        self.shown = []
        self.agent.browser.ensure = self.shown.append  # type: ignore
        self.cfg = dict(ka.DEFAULTS)

    def test_kiosk_url_is_shown(self):
        data = {"type": "kiosk", "url": "https://flipperklubben.se/slide/midsommar",
                "ttl": None, "subheading": "Hej"}
        self.agent.apply(data, self.cfg, 300, 15, 3600)
        self.assertEqual(self.shown[-1], "https://flipperklubben.se/slide/midsommar")

    def test_prototype_shows_standby(self):
        data = {"type": "prototype", "url": None, "placement": "Ej konfigurerad"}
        self.agent.apply(data, self.cfg, 300, 15, 3600)
        self.assertTrue(self.shown[-1].startswith("file://"))

    def test_null_url_shows_standby(self):
        data = {"type": "kiosk", "url": None, "subheading": "Standby"}
        self.agent.apply(data, self.cfg, 300, 15, 3600)
        self.assertTrue(self.shown[-1].startswith("file://"))

    def test_ttl_shortens_next_poll(self):
        soon = (datetime.now(timezone.utc) + timedelta(seconds=30)).isoformat()
        data = {"type": "kiosk", "url": "https://x.test/s", "ttl": soon}
        nxt = self.agent.apply(data, self.cfg, 300, 15, 3600)
        self.assertLessEqual(nxt, 36)


if __name__ == "__main__":
    unittest.main()
