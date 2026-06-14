# Flasha och starta en kiosk

## 1. Skaffa en image

Antingen ladda ner en färdig image från projektets releaser, eller bygg själv
(se [README](../README.md#bygga-images)). Filerna är zip-paketerade `.img` och
heter t.ex.:

- `image_<datum>-flipperklubben-kiosk-pi3.zip`
- `image_<datum>-flipperklubben-kiosk-pi4.zip`
- `image_<datum>-flipperklubben-kiosk-pi5.zip`

Välj den som matchar din Raspberry Pi. (Raspberry Pi Imager läser zip-filen
direkt – du behöver inte packa upp den.)

## 2. Skriv till SD-kort

Använd **Raspberry Pi Imager** (rekommenderas) eller **balenaEtcher**:

1. Välj "Use custom image" och peka på `.zip`-filen.
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
sudo systemctl restart getty@tty1             # starta om kiosken (autologin → startx)
sudo cat /home/kiosk/kiosk-session.log        # agentens & sessionens logg
sudo cat /home/kiosk/.local/share/xorg/Xorg.0.log  # X-serverns logg
```

Kiosken startas via konsol-autologin av användaren `kiosk` på tty1, som kör
`startx`. För att stoppa den tillfälligt: `sudo systemctl stop getty@tty1`.
