#!/bin/bash -e
# Lägger till modellspecifika rader i config.txt.
# Filen files/model-config.txt skrivs av build/build.sh innan bygget.

CONFIG_TXT="${ROOTFS_DIR}/boot/firmware/config.txt"

if [ -f files/model-config.txt ]; then
    {
        echo ""
        echo "# === Flipperklubben Kiosk ==="
        cat files/model-config.txt
    } >> "${CONFIG_TXT}"
fi
