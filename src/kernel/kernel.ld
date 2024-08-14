
SECTIONS
{
  . = 0x100000;
  .text     : {
    *main*.o(.text.KernelMain)
    *main*.o(.text.*)
    *(.text.*)
  }
  .rodata   : { *(.rodata*) }
  .data     : { *(.data) *(.bss) }
  .shstrtab : { *(.shstrtab) }

  /DISCARD/ : { *(*) }
}
