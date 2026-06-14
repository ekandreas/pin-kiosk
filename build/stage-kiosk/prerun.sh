#!/bin/bash -e
# Kopierar föregående stages rootfs som utgångspunkt för kiosk-stagen.
if [ ! -d "${ROOTFS_DIR}" ]; then
    copy_previous
fi
