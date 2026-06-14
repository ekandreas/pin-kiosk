# Flipperklubben Kiosk

Helskärms-kiosk för Raspberry Pi som visar en sida från Flipperklubbens
slide-system. Enheten hämtar sin konfiguration från ett publikt API utifrån
ett **monitor-ID** och öppnar rätt URL i helskärm – perfekt för infoskärmar i
lokalen.

> Byggt för att utvecklas gemensamt i Flipperklubben. Pull requests välkomnas –
> se [CONTRIBUTING.md](CONTRIBUTING.md).

## Innehåll

- [Vad är detta?](#vad-är-detta)
- [Operativsystem](#operativsystem)
- [Images för Pi 3, 4 och 5](#images-för-pi-3-4-och-5)
- [Snabbstart](#snabbstart)
- [Konfiguration](#konfiguration)
- [API:t](#apit)
- [Så fungerar enheten](#så-fungerar-enheten)
- [Bygga images](#bygga-images)
- [Utveckling](#utveckling)
- [Säkerhet](#säkerhet)

## Vad är detta?

En liten, robust kiosk-distribution. Vid start ansluter Pi:n till WiFi, frågar
API:t `GET /api/monitors/{id}` och visar den `url` som returneras i fullskärm
(Chromium kiosk). Saknas konfiguration eller nätverk visas en lokal
**standby-sida** i stället för en svart skärm – enheten "kraschar" aldrig.

**Funktioner**

- En enda redigerbar inställning på boot-partitionen: `MONITOR_ID`.
- Pollar API:t och respekterar `ttl` (byter slide snabbt när admin ändrar).
- Standby-/felsida vid saknad URL, `prototype`-läge eller nätverksfel.
- Förinställt WiFi och svensk lokal/tidszon.
- Agenten är beroendefri (enbart Pythons standardbibliotek).

## Operativsystem

**Raspberry Pi OS Lite (Bookworm, 64-bit).** Valt för att det är:

- **Lätt** – ingen skrivbordsmiljö, bara det vi själva lägger till
  (X.Org, en minimal fönsterhanterare `matchbox` och Chromium).
- **Officiellt och välunderhållet** – samma arm64-bas fungerar på Pi 3, 4 och 5.
- **Enkelt att bygga reproducerbart** med Raspberry Pis officiella verktyg
  [pi-gen](https://github.com/RPi-Distro/pi-gen).

Visningsstacken är den beprövade **X11 + matchbox + Chromium `--kiosk`**, som
är stabil och identisk över alla tre modellerna.

## Images för Pi 3, 4 och 5

Bygget producerar tre images med modellspecifika `config.txt`-justeringar:

| Modell | Image | Anmärkning |
| --- | --- | --- |
| Raspberry Pi 3 (A+/B/B+) | `flipperklubben-kiosk-pi3` | `gpu_mem=128`, HDMI hotplug |
| Raspberry Pi 4 (B/400) | `flipperklubben-kiosk-pi4` | KMS, HDMI hotplug |
| Raspberry Pi 5 | `flipperklubben-kiosk-pi5` | KMS |

De modellspecifika raderna ligger i [`build/models/`](build/models/).

## Snabbstart

1. Skaffa en image (release eller egen build – se [Bygga images](#bygga-images)).
2. Flasha till SD-kort med **Raspberry Pi Imager** (custom image).
3. Öppna **`kiosk.txt`** på boot-partitionen och sätt `MONITOR_ID`.
4. Sätt i kortet, koppla HDMI + ström.

Detaljerad guide: [docs/flashing.md](docs/flashing.md).

## Konfiguration

All konfiguration sker i **`kiosk.txt`** på boot-partitionen (FAT32) – läsbar
från valfri dator. Viktigaste raden:

```ini
# Skärmens ID i admin – avgör vilken info som visas
MONITOR_ID=2
```

Default-värden: `MONITOR_ID=2`, `API_BASE_URL=https://flipperklubben.se`.
Fullständig lista med inställningar: [docs/configuration.md](docs/configuration.md).

## API:t

Enheten använder ett **publikt** endpoint (ingen autentisering):

```
GET {API_BASE_URL}/api/monitors/{id}
```

Med standardvärden blir det `https://flipperklubben.se/api/monitors/2`.

### Exempelsvar

```json
{
  "data": {
    "id": 1,
    "subheading": "Varmt välkommen till oss!",
    "logo_url": "https://flipperklubben.se/assets/img/flipperklubben-3.7.png",
    "internal_logo_url": "https://flipperklubben.se/assets/img/flipperklubben-3.7.png",
    "url": "https://flipperklubben.se/slide/midsommar",
    "ttl": "2026-06-15T08:00:00+02:00"
  }
}
```

### Fält som kiosken bryr sig om

| Fält | Betydelse |
| --- | --- |
| `type` | `prototype` eller `kiosk`. En kiosk-enhet går i helskärm endast när typen är `kiosk` (saknat/tomt värde tolkas tillåtande som kiosk). |
| `url` | Adressen som öppnas i helskärm (t.ex. `/slide/{slug}`). Relativa sökvägar görs absoluta i svaret; fulla `http(s)`-URL:er passerar oförändrade. `null` om ej satt. |
| `ttl` | Giltig till (ISO-8601). Enheten pollar och uppdaterar strax efter denna tid. |
| `subheading`, `logo_url`, `internal_logo_url` | Visas på standby-sidan när ingen slide finns. |

### Beteende

- **Okänt `id`** ger `200` med default-värden
  (`placement: "Ej konfigurerad"`, `type: prototype`, `url: null`) – en
  nyutrullad enhet kraschar alltså aldrig, utan visar en standby-sida.
- **`url: null` eller `type: prototype`** → enheten visar standby-sidan
  (med `subheading`/logga) i stället för en slide.
- **Nätverks-/serverfel** → enheten behåller nuvarande sida och försöker igen;
  har inget visats ännu syns en "Kan inte nå servern"-sida.

## Så fungerar enheten

```
   Boot (Raspberry Pi OS Lite)
        │
        ▼
   systemd-tjänst ──► xinit ──► kiosk-session.sh
                                   │  (skärmsläckare av, matchbox, ev. rotation)
                                   ▼
                            kiosk_agent.py  ──poll──►  /api/monitors/{id}
                                   │                        │
                                   │   type/url/ttl ◄───────┘
                                   ▼
                      Chromium --kiosk  (slide-URL  eller  standby.html)
```

Agenten startar bara om Chromium när mål-URL:en faktiskt ändras (eller om
webbläsaren skulle dö), så skärmen är lugn mellan pollningar.

Källfilernas roller listas i [docs/development.md](docs/development.md#projektets-delar).

## Bygga images

Bygget använder pi-gen och kräver en **Debian/Ubuntu-host** (eller Docker).

```sh
# Alla tre modellerna
./build/build.sh
# eller en specifik modell
./build/build.sh pi4
# i Docker (kräver inte Debian-host)
USE_DOCKER=1 ./build/build.sh pi4
```

Färdiga images hamnar i `dist/`. Byt standardlösenordet vid behov:

```sh
FIRST_USER_PASS='ett-bra-lösenord' ./build/build.sh
```

Mer detaljer och felsökning: [docs/development.md](docs/development.md).

## Utveckling

Ingen Pi behövs för att jobba på agenten:

```sh
make run-dev   # kör agenten en gång, loggar beslut, startar inte Chromium
make test      # enhetstester
make lint      # py_compile + shellcheck
```

Se [docs/development.md](docs/development.md) och [CONTRIBUTING.md](CONTRIBUTING.md).

### Tips: utveckla med Claude Code

Det här repot är förberett för [Claude Code](https://claude.com/claude-code).
Filen [`CLAUDE.md`](CLAUDE.md) ger AI-assistenten rätt kontext direkt – karta
över koden, kommandon, API-beskrivning och projektets principer. Starta
`claude` i repots rot så plockas den upp automatiskt. Bra första frågor:

> "Läs CLAUDE.md och förklara hur agenten beslutar vad som visas."

> "Lägg till en ny inställning i kiosk.txt för X och uppdatera tester och docs."

## Säkerhet

- Enheterna är **internt nätverk**-tänkta. SSH är aktiverat med användaren
  `flipper` (default-lösenord `flipper`). **Byt lösenordet** på enheter som
  inte står säkert (`passwd`), eller bygg med `FIRST_USER_PASS=…`.
- WiFi-nyckeln bakas in i imagen (`flipperklubben` / `Magnetslingan10`).
  Behandla färdiga images som känsliga och lägg dem inte publikt.
- API:t som enheten anropar är publikt och kräver ingen autentisering.

## Licens

MIT – se [LICENSE](LICENSE).
