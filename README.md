
UEFI x64

based on https://0xc0ffee.netlify.app/osdev/01-intro.html

to run use `./run.sh`

to flash to USB, say `/dev/sda`, use `sudo mkfs.fat -F32 /dev/sda && sudo mount /dev/sda /mnt && sudo mkdir -p /mnt/efi/boot && sudo cp diskimg/efi/boot/bootx64.efi /mnt/efi/boot/ && sudo umount /mnt && sync`
