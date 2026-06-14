# Utveckling

Du behöver **ingen Raspberry Pi** för att utveckla agenten. Det mesta går att
köra och testa på en vanlig dator (Linux/macOS).

## Snabbstart

```sh
# Kör agenten en gång utan att starta Chromium – loggar vad den skulle visa
make run-dev
# motsvarar:
python3 kiosk/agent/kiosk_agent.py --no-browser --once -v
```

Peka mot en annan server eller monitor med en egen configfil:

```sh
printf 'MONITOR_ID=2\nAPI_BASE_URL=https://flipperklubben.se\n' > /tmp/kiosk.txt
python3 kiosk/agent/kiosk_agent.py --no-browser --once -v --config /tmp/kiosk.txt
```

## Tester

```sh
make test          # python3 -m unittest discover -s tests -v
make lint          # py_compile + shellcheck
```

CI kör samma sak på varje push och pull request (se `.github/workflows/ci.yml`).

## Köra med riktig webbläsare lokalt

På en Linux-desktop med Chromium installerad kan du köra hela loopen (utan
`--no-browser`). Den öppnar Chromium i kioskläge mot den URL API:t returnerar.
Avsluta med `Ctrl+C`.

## Projektets delar

| Sökväg | Roll |
| --- | --- |
| `kiosk/agent/kiosk_agent.py` | Agenten: pollar API, beslutar, styr Chromium. Endast stdlib. |
| `kiosk/bin/kiosk-session.sh` | X-session: skärmsläckare av, fönsterhanterare, startar agenten. |
| `kiosk/web/standby.html.tmpl` | Standby-/felsida som visas när ingen slide finns. |
| `kiosk/systemd/*.service` | systemd-tjänst som startar X vid boot. |
| `kiosk/config/*` | Default- och boot-konfiguration. |
| `build/` | pi-gen-bygget (stage, config, modell-config, `build.sh`). |
| `tests/` | Enhetstester. |

## Bygga images

Kräver Debian/Ubuntu eller Docker – se [README](../README.md#bygga-images).
Snabbast att iterera på agenten är att köra `make run-dev`; bygg image först
när on-device-beteendet ska verifieras.
