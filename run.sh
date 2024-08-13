#! /usr/bin/env bash

set -euo pipefail

# compile:
# nim c --os:any src/main.nim
#
# verify:
# file src/main
# result:
# src/main: PE32+ executable (EFI application) x86-64, for MS Windows, 4 sections
#
# compile:
# nim c --os:any src/bootx64.nim
# verify:
# file src/bootx64
# result:
# src/bootx64: PE32+ executable (EFI application) x86-64, for MS Windows, 4 sections

# https://0xc0ffee.netlify.app/osdev/01-intro.html

nim c --os:any src/bootx64.nim

rm -rf diskimg
mkdir -p diskimg/efi/boot

mv src/bootx64 diskimg/efi/boot/bootx64.efi

qemu-system-x86_64 \
    -drive if=pflash,format=raw,file=ovmf/OVMF_CODE.fd,readonly=on \
    -drive if=pflash,format=raw,file=ovmf/OVMF_VARS.fd \
    -drive format=raw,file=fat:rw:diskimg \
    -machine q35 \
    -net none
