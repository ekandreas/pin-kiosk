# Konfiguration

Kiosken konfigureras via filen **`kiosk.txt`** som ligger på SD-kortets
**boot-partition** (FAT32). Den kan redigeras från vilken dator som helst –
sätt i kortet, öppna filen, spara och mata ut. Inställningarna gäller efter
omstart (eller inom någon minut, eftersom agenten läser om filen löpande).

## Inställningar

| Nyckel | Default | Beskrivning |
| --- | --- | --- |
| `MONITOR_ID` | `2` | Skärmens ID i admin. Avgör vilken info som hämtas. |
| `API_BASE_URL` | `https://flipperklubben.se` | Bas-URL. Anropar `{API_BASE_URL}/api/monitors/{MONITOR_ID}`. |
| `POLL_INTERVAL` | `300` | Sekunder mellan pollningar i normalfallet. |
| `MIN_POLL_INTERVAL` | `15` | Snabbaste pollning (t.ex. vid nätverksfel). |
| `MAX_POLL_INTERVAL` | `3600` | Långsammaste pollning. |
| `HTTP_TIMEOUT` | `15` | Timeout för API-anrop (sekunder). |
| `ROTATE` | _(tom)_ | Skärmrotation: tom, `normal`, `left`, `right` eller `inverted`. |
| `EXTRA_CHROMIUM_FLAGS` | _(tom)_ | Extra Chromium-flaggor, mellanslagsseparerade. |

## Prioritetsordning

Värden läses i denna ordning, där **senare källa vinner**:

1. Inbyggda standardvärden (i `kiosk_agent.py`)
2. `/etc/default/flipperklubben-kiosk` (systemfallback)
3. `/boot/kiosk.txt` _eller_ `/boot/firmware/kiosk.txt` ← **redigera denna**

## Exempel

```ini
MONITOR_ID=2
API_BASE_URL=https://flipperklubben.se
POLL_INTERVAL=300
ROTATE=right
```

## ttl-styrning

Om API-svaret innehåller `ttl` (giltig till) pollar enheten igen strax efter
att tiden passerat – så att en ny slide syns snabbt utan att vänta ut hela
`POLL_INTERVAL`. Pollningen hålls alltid inom `MIN_POLL_INTERVAL` och
`MAX_POLL_INTERVAL`.
