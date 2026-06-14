# Flasha och starta en kiosk

## 1. Skaffa en image

Antingen ladda ner en färdig `.img`/`.img.xz` från projektets releaser, eller
bygg själv (se [README](../README.md#bygga-images)). Filerna heter t.ex.:

- `flipperklubben-kiosk-pi3-*.img.xz`
- `flipperklubben-kiosk-pi4-*.img.xz`
- `flipperklubben-kiosk-pi5-*.img.xz`

Välj den som matchar din Raspberry Pi.

## 2. Skriv till SD-kort

Använd **Raspberry Pi Imager** (rekommenderas) eller **balenaEtcher**:

1. Välj "Use custom image" och peka på `.img.xz`-filen.
2. Välj ditt SD-kort.
3. Skriv. (Hoppa över Imagerns OS-anpassningar – allt är redan inbakat.)

## 3. Sätt monitor-ID

Efter skrivning dyker boot-partitionen upp som en enhet (`bootfs`). Öppna
**`kiosk.txt`** och sätt rätt `MONITOR_ID`:

```ini
MONITOR_ID=2
```

Spara och mata ut kortet säkert.

## 4. Starta

Sätt i kortet i din Pi, koppla in HDMI och ström. Enheten:

1. Ansluter till WiFi **flipperklubben** automatiskt (förinställt).
2. Startar i konsolläge och drar igång kiosk-tjänsten.
3. Hämtar `https://flipperklubben.se/api/monitors/2` och visar sidan i helskärm.

Är `MONITOR_ID` inte satt, eller går servern inte att nå, visas en lokal
standby-sida med instruktioner i stället för en svart skärm.

## Underhåll via SSH

Inloggning är aktiverad. Standardanvändare: **`flipperklubben`** / lösenord
**`Magnetslingan10`** (samma som WiFi). **Byt lösenordet** (`passwd`) på enheter
som inte står säkert.

```sh
ssh flipperklubben@<pi-ip>
sudo systemctl restart flipperklubben-kiosk   # starta om kiosken
journalctl -u flipperklubben-kiosk -f         # se loggar
```
