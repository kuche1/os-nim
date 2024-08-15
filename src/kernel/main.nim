
import std/strformat
import common/[bootinfo, libc, malloc]
import debugcon

proc NimMain() {.importc.}

proc KernelMain(bootInfo: ptr BootInfo) {.exportc.} =

  NimMain()

  debugln "kernel: Ligma Kernel"
  debugln &"kernel: Memory map length: {bootinfo.physicalMemoryMap.len}"

  quit()
