#!/bin/bash -e
# Installerar Flipperklubben Kiosk i image-rootfs.

KIOSK_DIR="${ROOTFS_DIR}/opt/flipperklubben-kiosk"

# --- Applikationsfiler ------------------------------------------------------
install -d "${KIOSK_DIR}"
cp -r files/payload/agent  "${KIOSK_DIR}/"
cp -r files/payload/bin    "${KIOSK_DIR}/"
cp -r files/payload/web    "${KIOSK_DIR}/"
chmod +x "${KIOSK_DIR}/bin/kiosk-session.sh" "${KIOSK_DIR}/agent/kiosk_agent.py"

# --- systemd-tjänst ---------------------------------------------------------
install -m 644 files/payload/systemd/flipperklubben-kiosk.service \
    "${ROOTFS_DIR}/etc/systemd/system/flipperklubben-kiosk.service"

# --- Konfiguration ----------------------------------------------------------
install -m 644 files/payload/config/flipperklubben-kiosk.default \
    "${ROOTFS_DIR}/etc/default/flipperklubben-kiosk"
# Redigerbar konfiguration på boot-partitionen.
install -m 644 files/payload/config/kiosk.txt \
    "${ROOTFS_DIR}/boot/firmware/kiosk.txt"

# --- Tillåt X utan root -----------------------------------------------------
cat > "${ROOTFS_DIR}/etc/X11/Xwrapper.config" <<'EOF'
allowed_users=anybody
needs_root_rights=yes
EOF

# --- WiFi: default Flipperklubben (NetworkManager keyfile) ------------------
install -d -m 700 "${ROOTFS_DIR}/etc/NetworkManager/system-connections"
cat > "${ROOTFS_DIR}/etc/NetworkManager/system-connections/flipperklubben.nmconnection" <<'EOF'
[connection]
id=flipperklubben
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=flipperklubben

[wifi-security]
key-mgmt=wpa-psk
psk=Magnetslingan10

[ipv4]
method=auto

[ipv6]
method=auto
EOF
chmod 600 "${ROOTFS_DIR}/etc/NetworkManager/system-connections/flipperklubben.nmconnection"

# --- Systeminställningar i chroot -------------------------------------------
on_chroot << 'EOF'
# Dedikerad kiosk-användare utan lösenord.
if ! id kiosk >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" kiosk
fi
for grp in video render input tty audio; do
    adduser kiosk "$grp" || true
done

# Sätt WiFi-regulatorisk domän så att radion aktiveras.
raspi-config nonint do_wifi_country SE || true

# Boota till konsol (multi-user) – vår tjänst startar X.
systemctl set-default multi-user.target
systemctl enable flipperklubben-kiosk.service
EOF
