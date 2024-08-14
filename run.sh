#! /usr/bin/env bash

set -euo pipefail

NIM_FLAGS='--os:any'

echo 'Cleaning temporary folders...'

rm -rf build
rm -rf diskimg

echo 'Compiling boot...'

nim c $NIM_FLAGS src/boot/bootx64.nim

echo 'Compiling kernel...'

nim c $NIM_FLAGS src/kernel/main.nim

echo 'Copying files to disk image...'

mkdir -p diskimg/efi
mkdir diskimg/efi/boot
mkdir diskimg/efi/fusion

cp build/bootx64 diskimg/efi/boot/bootx64.efi
cp build/main diskimg/efi/fusion/kernel.bin

echo 'Running eqmu...'

qemu-system-x86_64 \
    -drive if=pflash,format=raw,file=ovmf/OVMF_CODE.fd,readonly=on \
    -drive if=pflash,format=raw,file=ovmf/OVMF_VARS.fd \
    -drive format=raw,file=fat:rw:diskimg \
    -machine q35 \
    -net none \
    -debugcon stdio
    # -nographic
# `-machine q35` to use the Q35 + ICH9 chipsets (2009), instead of the default i440FX + PIIX chipsets (1996); this gives a more modern environment, with support for PCI Express, AHCI, and better UEFI, ACPI, and USB support
# `-net none` to disable the default network card, to prevent the firmware from trying to use PXE network boot
# `-nographic` to make qemu run in the terminal
