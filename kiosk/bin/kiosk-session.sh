#!/bin/sh
# X-session för Flipperklubben Kiosk.
# Startas av xinit (se systemd-tjänsten). Sätter upp en ren helskärmsmiljö
# och lämnar sedan över till kiosk-agenten som styr Chromium.
set -eu

KIOSK_HOME="/opt/flipperklubben-kiosk"

# Läs valfri ROTATE-inställning från konfigurationen.
ROTATE=""
for f in /etc/default/flipperklubben-kiosk /boot/kiosk.txt /boot/firmware/kiosk.txt; do
    [ -f "$f" ] || continue
    val="$(sed -n 's/^ROTATE=//p' "$f" | tail -n1 | tr -d '"'"'"' ')"
    [ -n "$val" ] && ROTATE="$val"
done

# Inga skärmsläckare, ingen energisparning, ingen blankning.
xset s off || true
xset -dpms || true
xset s noblank || true

# Dölj muspekaren när den är stilla.
unclutter -idle 0.5 -root >/dev/null 2>&1 &

# Minimal fönsterhanterare (ingen titelrad).
matchbox-window-manager -use_titlebar no -use_cursor no >/dev/null 2>&1 &

# Valfri skärmrotation (normal | left | right | inverted).
if [ -n "$ROTATE" ]; then
    OUTPUT="$(xrandr | awk '/ connected/{print $1; exit}')"
    [ -n "$OUTPUT" ] && xrandr --output "$OUTPUT" --rotate "$ROTATE" || true
fi

# Lämna över till agenten (blir sessionens huvudprocess).
exec python3 "$KIOSK_HOME/agent/kiosk_agent.py"
