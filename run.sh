#! /usr/bin/env bash

set -euo pipefail

nim c --os:any src/bootx64.nim

rm -rf diskimg
mkdir -p diskimg/efi/boot

mv src/bootx64 diskimg/efi/boot/bootx64.efi

echo "Running eqmu..."

qemu-system-x86_64 \
    -drive if=pflash,format=raw,file=ovmf/OVMF_CODE.fd,readonly=on \
    -drive if=pflash,format=raw,file=ovmf/OVMF_VARS.fd \
    -drive format=raw,file=fat:rw:diskimg \
    -machine q35 \
    -net none
# `-machine q35` to use the Q35 + ICH9 chipsets (2009), instead of the default i440FX + PIIX chipsets (1996); this gives a more modern environment, with support for PCI Express, AHCI, and better UEFI, ACPI, and USB support
# `-net none` to disable the default network card, to prevent the firmware from trying to use PXE network boot
