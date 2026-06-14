#!/bin/sh
# X-session för Flipperklubben Kiosk.
# Startas av startx (se /home/kiosk/.bash_profile) när kiosk-användaren
# autologgas in på tty1. Sätter upp en ren helskärmsmiljö och lämnar sedan
# över till kiosk-agenten som styr Chromium.
#
# Medvetet utan "set -e": en enskild valfri komponent (t.ex. unclutter) ska
# aldrig kunna stoppa hela sessionen.
set -u

KIOSK_HOME="/opt/flipperklubben-kiosk"

# Läs valfri ROTATE-inställning från konfigurationen.
ROTATE=""
for f in /etc/default/flipperklubben-kiosk /boot/kiosk.txt /boot/firmware/kiosk.txt; do
    [ -f "$f" ] || continue
    val="$(sed -n 's/^ROTATE=//p' "$f" | tail -n1 | tr -d '"'"'"' ')"
    [ -n "$val" ] && ROTATE="$val"
done

# Inga skärmsläckare, ingen energisparning, ingen blankning.
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Dölj muspekaren när den är stilla (om unclutter finns).
if command -v unclutter >/dev/null 2>&1; then
    unclutter -idle 0.5 -root >/dev/null 2>&1 &
fi

# Minimal fönsterhanterare (om matchbox finns).
if command -v matchbox-window-manager >/dev/null 2>&1; then
    matchbox-window-manager -use_titlebar no -use_cursor no >/dev/null 2>&1 &
fi

# Valfri skärmrotation (normal | left | right | inverted).
if [ -n "$ROTATE" ]; then
    OUTPUT="$(xrandr 2>/dev/null | awk '/ connected/{print $1; exit}')"
    [ -n "$OUTPUT" ] && xrandr --output "$OUTPUT" --rotate "$ROTATE" 2>/dev/null || true
fi

# Lämna över till agenten (blir sessionens huvudprocess; håller X vid liv).
exec python3 "$KIOSK_HOME/agent/kiosk_agent.py"
