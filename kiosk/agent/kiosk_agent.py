#!/usr/bin/env python3
"""Flipperklubben Kiosk-agent.

Hämtar konfiguration för en monitor från Flipperklubbens API och visar
rätt sida i helskärm (Chromium kiosk). Om enheten inte är konfigurerad,
saknar URL eller är av typen ``prototype`` visas en lokal standby-sida.

Agenten är medvetet skriven med enbart Python-standardbiblioteket så att
images blir små och bygget enkelt — inga pip-beroenden krävs.

Körs normalt som en systemd-tjänst inuti X-sessionen (se
``bin/kiosk-session.sh``). Kan även köras på en vanlig dator för utveckling,
se ``--help``.
"""
from __future__ import annotations

import argparse
import html
import json
import logging
import os
import shutil
import signal
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

LOG = logging.getLogger("kiosk")

# --- Standardvärden ---------------------------------------------------------
# Kan överskridas via kiosk.txt på boot-partitionen eller /etc/default-filen.
DEFAULTS = {
    "MONITOR_ID": "2",
    "API_BASE_URL": "https://flipperklubben.se",
    "POLL_INTERVAL": "300",       # sekunder mellan pollningar (normalfall)
    "MIN_POLL_INTERVAL": "15",    # snabbaste pollning (t.ex. vid fel)
    "MAX_POLL_INTERVAL": "3600",  # långsammaste pollning
    "HTTP_TIMEOUT": "15",         # sekunder för API-anrop
    "ROTATE": "",                 # normal | left | right | inverted (valfritt)
    "EXTRA_CHROMIUM_FLAGS": "",   # extra flaggor till Chromium, mellanslagsseparerade
}

# Filer där konfigurationen läses ifrån. Senare källa vinner över tidigare,
# så boot-partitionen (som användaren redigerar) har högst prioritet.
CONFIG_PATHS = [
    "/etc/default/flipperklubben-kiosk",
    "/boot/kiosk.txt",
    "/boot/firmware/kiosk.txt",
]

# Var standby-sidan renderas (tmpfs i drift, /tmp som fallback).
RUNTIME_DIR = Path(os.environ.get("KIOSK_RUNTIME_DIR", "/run/flipperklubben-kiosk"))


# --- Konfiguration ----------------------------------------------------------
def load_config(extra_paths=None) -> dict:
    """Läs konfiguration från standardvärden + KEY=VALUE-filer."""
    cfg = dict(DEFAULTS)
    paths = list(CONFIG_PATHS)
    if extra_paths:
        paths.extend(extra_paths)
    for path in paths:
        try:
            with open(path, "r", encoding="utf-8") as fh:
                for raw in fh:
                    line = raw.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    key, value = line.split("=", 1)
                    key = key.strip()
                    # Tillåt enkla citattecken runt värdet.
                    value = value.strip().strip('"').strip("'")
                    if key:
                        cfg[key] = value
        except FileNotFoundError:
            continue
        except OSError as exc:
            LOG.warning("Kunde inte läsa %s: %s", path, exc)
    return cfg


def cfg_int(cfg: dict, key: str, fallback: int) -> int:
    try:
        return int(str(cfg.get(key, fallback)).strip())
    except (TypeError, ValueError):
        return fallback


# --- API --------------------------------------------------------------------
def fetch_monitor(base_url: str, monitor_id: str, timeout: int) -> dict:
    """Hämta monitor-data från API:t. Returnerar ``data``-objektet."""
    url = f"{base_url.rstrip('/')}/api/monitors/{monitor_id}"
    LOG.debug("Hämtar %s", url)
    req = urllib.request.Request(url, headers={"User-Agent": "flipperklubben-kiosk/1.0"})
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    data = payload.get("data", payload) if isinstance(payload, dict) else {}
    if not isinstance(data, dict):
        raise ValueError("Oväntat API-svar (saknar 'data'-objekt)")
    return data


def parse_ttl(ttl: str | None):
    """Tolka ISO-8601-ttl till en timezone-medveten datetime, eller None."""
    if not ttl:
        return None
    try:
        dt = datetime.fromisoformat(ttl)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except (ValueError, TypeError):
        LOG.warning("Kunde inte tolka ttl: %r", ttl)
        return None


def seconds_until(dt) -> float | None:
    if dt is None:
        return None
    return (dt - datetime.now(timezone.utc)).total_seconds()


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


# --- Standby-sida -----------------------------------------------------------
def render_standby(template: Path, *, heading: str, subheading: str,
                   message: str, detail: str, logo_url: str) -> str:
    """Rendera standby-HTML till runtime-katalogen och returnera en file://-URL."""
    try:
        tmpl = template.read_text(encoding="utf-8")
    except OSError:
        tmpl = _FALLBACK_TEMPLATE

    logo_block = ""
    if logo_url:
        logo_block = f'<img class="logo" src="{html.escape(logo_url, quote=True)}" alt="">'

    rendered = (
        tmpl.replace("{{HEADING}}", html.escape(heading))
        .replace("{{SUBHEADING}}", html.escape(subheading))
        .replace("{{MESSAGE}}", html.escape(message))
        .replace("{{DETAIL}}", html.escape(detail))
        .replace("{{LOGO}}", logo_block)
    )

    out = _runtime_dir() / "standby.html"
    out.write_text(rendered, encoding="utf-8")
    return out.as_uri()


def _runtime_dir() -> Path:
    """Returnera en skrivbar runtime-katalog (tmpfs i drift, temp annars)."""
    try:
        RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
        return RUNTIME_DIR
    except OSError:
        fallback = Path(tempfile.gettempdir()) / "flipperklubben-kiosk"
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback


_FALLBACK_TEMPLATE = (
    "<!doctype html><html><head><meta charset='utf-8'>"
    "<style>body{background:#0b0b12;color:#fff;font-family:sans-serif;"
    "display:flex;flex-direction:column;align-items:center;justify-content:center;"
    "height:100vh;margin:0;text-align:center}</style></head><body>"
    "{{LOGO}}<h1>{{HEADING}}</h1><h2>{{SUBHEADING}}</h2>"
    "<p>{{MESSAGE}}</p><p>{{DETAIL}}</p></body></html>"
)


# --- Webbläsarhantering -----------------------------------------------------
def find_browser() -> str | None:
    for name in ("chromium-browser", "chromium", "chromium-browser-stable"):
        path = shutil.which(name)
        if path:
            return path
    return None


class BrowserManager:
    """Startar och styr en Chromium-process i kioskläge.

    Webbläsaren startas om endast när mål-URL:en ändras eller om processen
    har dött (kraschåterhämtning). Det ger en lugn skärm som inte blinkar
    i onödan mellan pollningar.
    """

    BASE_FLAGS = [
        "--kiosk",
        "--noerrdialogs",
        "--disable-infobars",
        "--no-first-run",
        "--fast",
        "--fast-start",
        "--disable-translate",
        "--disable-features=Translate,TranslateUI",
        "--disable-session-crashed-bubble",
        "--disable-pinch",
        "--overscroll-history-navigation=0",
        "--autoplay-policy=no-user-gesture-required",
        "--check-for-update-interval=31536000",
        "--disable-component-update",
        "--password-store=basic",
        "--hide-scrollbars",
        "--start-fullscreen",
    ]

    def __init__(self, browser: str | None, profile_dir: Path, extra_flags=None,
                 dry_run: bool = False):
        self.browser = browser
        self.profile_dir = profile_dir
        self.extra_flags = extra_flags or []
        self.dry_run = dry_run
        self.proc: subprocess.Popen | None = None
        self.current_url: str | None = None
        self._last_launch = 0.0

    def ensure(self, url: str) -> None:
        alive = self.proc is not None and self.proc.poll() is None
        if alive and url == self.current_url:
            return
        if alive and self.proc is not None and url != self.current_url:
            LOG.info("Byter sida: %s", url)
            self._terminate()
        elif not alive and self.current_url is not None:
            LOG.warning("Webbläsaren dog — startar om")
        self._launch(url)

    def _launch(self, url: str) -> None:
        # Enkel skydd mot kraschloop: vänta minst lite mellan starter.
        since = time.monotonic() - self._last_launch
        if since < 3:
            time.sleep(3 - since)

        self.current_url = url
        self._last_launch = time.monotonic()

        if self.dry_run or not self.browser:
            LOG.info("[dry-run] skulle visa: %s", url)
            return

        self.profile_dir.mkdir(parents=True, exist_ok=True)
        cmd = [self.browser, *self.BASE_FLAGS,
               f"--user-data-dir={self.profile_dir}", *self.extra_flags, url]
        LOG.info("Startar webbläsare: %s", url)
        LOG.debug("Kommando: %s", " ".join(cmd))
        self.proc = subprocess.Popen(cmd)

    def _terminate(self) -> None:
        if self.proc is None:
            return
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                LOG.error("Kunde inte avsluta webbläsaren")
        self.proc = None

    def shutdown(self) -> None:
        self._terminate()


# --- Huvudlogik -------------------------------------------------------------
class KioskAgent:
    def __init__(self, args):
        self.args = args
        self.template = Path(args.template)
        cfg = load_config(args.config)
        browser = None if args.no_browser else find_browser()
        if not args.no_browser and not browser:
            LOG.warning("Hittade ingen Chromium — kör i dry-run-läge")
        profile = Path(os.environ.get(
            "KIOSK_PROFILE_DIR",
            os.path.expanduser("~/.cache/flipperklubben-kiosk/profile")))
        self.browser = BrowserManager(
            browser, profile,
            extra_flags=cfg.get("EXTRA_CHROMIUM_FLAGS", "").split(),
            dry_run=args.no_browser or not browser)
        self._stop = False

    def stop(self, *_):
        LOG.info("Stoppar …")
        self._stop = True

    def run(self) -> int:
        signal.signal(signal.SIGTERM, self.stop)
        signal.signal(signal.SIGINT, self.stop)
        while not self._stop:
            sleep_for = self.tick()
            if self.args.once:
                break
            self._sleep(sleep_for)
        self.browser.shutdown()
        return 0

    def _sleep(self, seconds: float) -> None:
        # Sov i korta steg så att SIGTERM tas emot snabbt.
        end = time.monotonic() + seconds
        while not self._stop and time.monotonic() < end:
            time.sleep(min(1.0, end - time.monotonic()))

    def tick(self) -> float:
        """En iteration: läs config, polla API, uppdatera skärmen.

        Returnerar antal sekunder att sova innan nästa iteration.
        """
        cfg = load_config(self.args.config)
        min_poll = cfg_int(cfg, "MIN_POLL_INTERVAL", 15)
        max_poll = cfg_int(cfg, "MAX_POLL_INTERVAL", 3600)
        poll = cfg_int(cfg, "POLL_INTERVAL", 300)
        timeout = cfg_int(cfg, "HTTP_TIMEOUT", 15)
        monitor_id = str(cfg.get("MONITOR_ID", "")).strip()
        base_url = cfg.get("API_BASE_URL", DEFAULTS["API_BASE_URL"]).strip()

        # Inte konfigurerad: visa instruktioner och kolla igen snart.
        if not monitor_id:
            self.browser.ensure(render_standby(
                self.template,
                heading="Flipperklubben Kiosk",
                subheading="Ej konfigurerad",
                message="Sätt MONITOR_ID i kiosk.txt på boot-partitionen.",
                detail="Öppna SD-kortet på en dator och redigera kiosk.txt.",
                logo_url=""))
            return clamp(min_poll, min_poll, max_poll)

        # Hämta från API.
        try:
            data = fetch_monitor(base_url, monitor_id, timeout)
        except (urllib.error.URLError, OSError, ValueError, json.JSONDecodeError) as exc:
            LOG.warning("API-fel: %s", exc)
            # Behåll nuvarande sida om vi redan visar något, annars felsida.
            if self.browser.current_url is None:
                self.browser.ensure(render_standby(
                    self.template,
                    heading="Flipperklubben Kiosk",
                    subheading="Kan inte nå servern",
                    message="Försöker igen automatiskt.",
                    detail=f"Monitor {monitor_id} · {base_url}",
                    logo_url=""))
            return clamp(min_poll, min_poll, max_poll)

        return self.apply(data, cfg, poll, min_poll, max_poll)

    def apply(self, data: dict, cfg: dict, poll: int, min_poll: int,
              max_poll: int) -> float:
        url = data.get("url")
        mtype = (data.get("type") or "").strip().lower()
        subheading = data.get("subheading") or ""
        placement = data.get("placement") or ""
        logo = data.get("logo_url") or data.get("internal_logo_url") or ""
        ttl_dt = parse_ttl(data.get("ttl"))

        # Visa slide-URL endast om enheten ska vara i kioskläge och har en URL.
        is_kiosk = mtype in ("", "kiosk")  # tom typ tolkas tillåtande som kiosk
        if url and is_kiosk:
            LOG.info("Monitor %s → %s (typ=%s)", cfg.get("MONITOR_ID"), url,
                     mtype or "okänd")
            self.browser.ensure(url)
        else:
            reason = "Ingen sida konfigurerad" if not url else "Prototypläge"
            self.browser.ensure(render_standby(
                self.template,
                heading="Flipperklubben",
                subheading=subheading or placement or "Standby",
                message=reason,
                detail=placement,
                logo_url=logo))

        # Beräkna nästa pollning: senast vid ttl, annars normalintervall.
        next_poll = float(poll)
        secs = seconds_until(ttl_dt)
        if secs is not None:
            if secs <= 0:
                next_poll = min(next_poll, min_poll)
            else:
                next_poll = min(next_poll, secs + 5)
        return clamp(next_poll, min_poll, max_poll)


# --- CLI --------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    here = Path(__file__).resolve().parent
    default_template = here.parent / "web" / "standby.html.tmpl"
    p = argparse.ArgumentParser(description="Flipperklubben Kiosk-agent")
    p.add_argument("--config", action="append", default=[],
                   help="Extra konfigurationsfil (kan anges flera gånger)")
    p.add_argument("--template", default=str(default_template),
                   help="Sökväg till standby-mall")
    p.add_argument("--once", action="store_true",
                   help="Kör endast en iteration (för test)")
    p.add_argument("--no-browser", action="store_true",
                   help="Starta inte Chromium, logga bara beslut (för utveckling)")
    p.add_argument("-v", "--verbose", action="store_true", help="Mer loggning")
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s")
    return KioskAgent(args).run()


if __name__ == "__main__":
    sys.exit(main())
