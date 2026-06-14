# Bidra till Flipperklubben Kiosk

Kul att du vill vara med! Det här repot utvecklas gemensamt av oss i
Flipperklubben. Inga bidrag är för små.

## Komma igång

1. Klona repot och läs [`docs/development.md`](docs/development.md).
2. Kör `make run-dev` och `make test` för att se att allt funkar lokalt.
3. Skapa en branch: `git checkout -b min-finess`.

> 💡 Repot är förberett för [Claude Code](https://claude.com/claude-code).
> Starta `claude` i repots rot så läser den [`CLAUDE.md`](CLAUDE.md) och får
> full kontext om kod, kommandon och API. Bra hjälp för både nya och vana.

## Innan du öppnar en PR

- `make test` ska vara grön.
- `make lint` ska vara grön (installera `shellcheck` om du rör skalskript).
- Håll agenten beroendefri (endast Pythons standardbibliotek) så att images
  förblir små och bygget enkelt.
- Skriv kortfattade commit-meddelanden, gärna på svenska.

## Idéer och buggar

Öppna en **issue** med så mycket detaljer du kan: vilken Pi-modell, vad du såg
i `journalctl -u flipperklubben-kiosk`, och vad du förväntade dig.

## Riktlinjer för kod

- Agenten ska aldrig krascha permanent – fall tillbaka till standby-sidan.
- Nya inställningar läggs i `kiosk.txt` + dokumenteras i
  [`docs/configuration.md`](docs/configuration.md).
- Modellspecifika `config.txt`-rader hör hemma i `build/models/`.
