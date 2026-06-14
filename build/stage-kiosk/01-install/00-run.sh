#!/bin/bash -e
# Installerar Flipperklubben Kiosk i image-rootfs.

KIOSK_DIR="${ROOTFS_DIR}/opt/flipperklubben-kiosk"

# --- Applikationsfiler ------------------------------------------------------
install -d "${KIOSK_DIR}"
cp -r files/payload/agent  "${KIOSK_DIR}/"
cp -r files/payload/bin    "${KIOSK_DIR}/"
cp -r files/payload/web    "${KIOSK_DIR}/"
chmod +x "${KIOSK_DIR}/bin/kiosk-session.sh" "${KIOSK_DIR}/agent/kiosk_agent.py"
# Källkopior i rootfsen (kiosk.txt används även av export-fasen för att lägga
# tillbaka filen på boot-partitionen; bash_profile installeras åt kiosk nedan).
install -m 644 files/payload/config/kiosk.txt "${KIOSK_DIR}/kiosk.txt"
install -m 644 files/payload/config/bash_profile "${KIOSK_DIR}/bash_profile"

# --- Autologin på tty1 ------------------------------------------------------
# getty autologgar in kiosk-användaren på tty1; .bash_profile kör sedan startx.
# Detta ersätter en egen X-tjänst och undviker konflikt om tty1.
install -d "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d"
cat > "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin kiosk --noclear %I $TERM
EOF

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

# Installera startprofilen åt kiosk-användaren (startar X på tty1).
install -m 644 -o kiosk -g kiosk /opt/flipperklubben-kiosk/bash_profile /home/kiosk/.bash_profile

# Boota till konsol (multi-user); autologin+startx tar över skärmen.
systemctl set-default multi-user.target
EOF
