
import std/strformat
import common/[bootinfo, libc, malloc]
import debugcon

proc NimMain() {.importc.}

proc KernelMain(bootInfo: ptr BootInfo) {.exportc.} =

  NimMain()

  debugln "kernel: Ligma Kernel"
  debugln &"kernel: Memory map length: {bootinfo.physicalMemoryMap.len}"

  debugln ""
  debugln &"Memory Map ({bootInfo.physicalMemoryMap.len} entries):"
  debug &"""   {"Entry"}"""
  debug &"""   {"Type":12}"""
  debug &"""   {"Start":>12}"""
  debug &"""   {"Start (KB)":>15}"""
  debug &"""   {"#Pages":>10}"""
  debugln ""

  var totalFreePages:uint64 = 0
  for i in 0 ..< bootInfo.physicalMemoryMap.len:
    let entry = bootInfo.physicalMemoryMap.entries[i]
    debug &"   {i:>5}"
    debug &"   {entry.type:12}"
    debug &"   {entry.start:>#12x}"
    debug &"   {entry.start div 1024:>#15}"
    debug &"   {entry.nframes:>#10}"
    debugln ""
    if entry.type == MemoryType.Free:
      totalFreePages += entry.nframes

  debugln ""
  debugln &"Total free: {totalFreePages * 4} KiB ({totalFreePages * 4 div 1024} MiB)"

  quit()
