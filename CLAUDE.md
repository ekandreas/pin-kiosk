# CLAUDE.md

Den här filen ger [Claude Code](https://claude.com/claude-code) (och andra
AI-assistenter) kontext om projektet. Läs den först – då blir hjälpen rätt.

## Vad projektet är

Flipperklubben Kiosk: en helskärms-kiosk för Raspberry Pi 3/4/5. Enheten
pollar ett publikt API (`GET /api/monitors/{id}`) och visar den `url` som
returneras i fullskärm via Chromium. Saknas konfiguration/nätverk visas en
lokal standby-sida. OS:et är Raspberry Pi OS Lite (Trixie, 64-bit) och
images byggs med pi-gen.

## Karta över koden

| Sökväg | Roll |
| --- | --- |
| `kiosk/agent/kiosk_agent.py` | **Hjärtat.** Pollar API, beslutar vad som visas, styr Chromium. Endast Python-stdlib. |
| `kiosk/bin/kiosk-session.sh` | X-session: skärmsläckare av, `matchbox`, valfri rotation, startar agenten. |
| `kiosk/web/standby.html.tmpl` | Standby-/felsida (mall med `{{PLATSHÅLLARE}}`). |
| `kiosk/systemd/flipperklubben-kiosk.service` | Startar X via `xinit` vid boot. |
| `kiosk/config/kiosk.txt` | Redigerbar boot-config (hamnar på boot-partitionen). |
| `kiosk/config/flipperklubben-kiosk.default` | Systemfallback i `/etc/default/`. |
| `build/build.sh` | Orkestrerar pi-gen-bygget per modell. |
| `build/stage-kiosk/` | pi-gen-stage som installerar allt ovan + WiFi + kiosk-användare. |
| `build/models/*.config.txt` | Modellspecifika `config.txt`-rader (pi3/pi4/pi5). |
| `build/pi-gen-config/config.tmpl` | pi-gen-config med platshållare. |
| `tests/test_agent.py` | Enhetstester (unittest). |

## Vanliga kommandon

```sh
make run-dev   # kör agenten en gång, --no-browser, loggar beslut
make test      # python3 -m unittest discover -s tests
make lint      # py_compile + shellcheck
./build/build.sh [pi3|pi4|pi5]   # bygg image (kräver Debian/Ubuntu eller USE_DOCKER=1)
```

Testa mot en specifik monitor utan Pi:

```sh
printf 'MONITOR_ID=2\n' > /tmp/k.txt
python3 kiosk/agent/kiosk_agent.py --no-browser --once -v --config /tmp/k.txt
```

## API:t (källan till sanning)

`GET {API_BASE_URL}/api/monitors/{id}` – publikt, ingen auth. Default-bas är
`https://flipperklubben.se`. Relevanta fält i `data`:

- `type` – `kiosk` eller `prototype`. Visa slide endast vid `kiosk` (tomt
  värde tolkas tillåtande som kiosk).
- `url` – adressen som öppnas i helskärm; `null` ⇒ standby.
- `ttl` – ISO-8601, styr när nästa pollning sker.
- `subheading`, `placement`, `logo_url` – visas på standby-sidan.

Okänt `id` ger `200` med defaults (`type: prototype`, `url: null`) – enheten
ska aldrig krascha utan falla tillbaka på standby.

## Konventioner och principer

- **Agenten ska aldrig dö permanent** – fånga fel och visa standby-sidan.
- **Inga pip-beroenden i agenten** – endast standardbiblioteket, så images
  förblir små och bygget enkelt.
- **Nya inställningar** läggs i `kiosk.txt`, läses i `load_config`, och
  dokumenteras i `docs/configuration.md`.
- **Modellskillnader** hör hemma i `build/models/`, inte i agenten.
- Kommentarer och commit-meddelanden på svenska (matchar klubben).
- Kör `make test` och `make lint` innan commit. CI kör samma sak.

## Att vara försiktig med

- `build/build.sh` klonar och kör pi-gen som kräver root/Debian – kör inte
  bygget oombett på en dev-maskin; föreslå det, kör det inte automatiskt.
- WiFi (`flipperklubben`/`Magnetslingan10`) och SSH (användare `flipperklubben`,
  samma lösenord) bakas in i images – behandla `dist/` som känsligt.
- `kiosk/systemd/*.service` kör X som användaren `kiosk` utan root via
  `Xwrapper.config` (`allowed_users=anybody`). Ändra inte utan att förstå seat/logind.
