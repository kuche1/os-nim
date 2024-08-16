
import std/strformat
import std/options
import common/[bootinfo, libc, malloc]
import debugcon
import pmm

# forward declarations
proc NimMain() {.importc.}
proc KernelMainInner(bootInfo: ptr BootInfo)

proc unhandledException*(e: ref Exception) =
  debugln ""
  debugln &"Unhandled exception: {e.msg} [{e.name}]"
  if e.trace.len > 0:
    debugln ""
    debugln "Stack trace:"
    debugln getStackTrace(e)
  quit()

proc KernelMain(bootInfo: ptr BootInfo) {.exportc.} =

  NimMain()

  try:
    KernelMainInner(bootInfo)
  except Exception as e:
    unhandledException(e)

  quit()

proc printFreeRegions() =
  debugln "kernel: Physical memory free regions "
  debug &"""   {"Start":>16}"""
  debug &"""   {"Start (KB)":>12}"""
  debug &"""   {"Size (KB)":>11}"""
  debug &"""   {"#Pages":>9}"""
  debugln ""
  var totalFreePages: uint64 = 0
  for (start, nframes) in pmFreeRegions():
    debug &"   {cast[uint64](start):>#16x}"
    debug &"   {cast[uint64](start) div 1024:>#12}"
    debug &"   {nframes * 4:>#11}"
    debug &"   {nframes:>#9}"
    debugln ""
    totalFreePages += nframes
  debugln &"kernel: Total free: {totalFreePages * 4} KiB ({totalFreePages * 4 div 1024} MiB)"

proc KernelMainInner(bootInfo: ptr BootInfo) =
  debugln ""
  debugln "kernel: Fusion Kernel"

  debug "kernel: Initializing physical memory manager "
  pmInit(bootInfo.physicalMemoryMap)
  debugln "[success]"

  printFreeRegions()
  debugln ""

  debugln "kernel: Allocating 8 frames"
  let paddr = pmAlloc(8)
  if paddr.isNone:
    debugln "kernel: Allocation failed"
  printFreeRegions()
  debugln ""

  debugln &"kernel: Freeing 2 frames at 0x2000"
  pmFree(0x2000.PhysAddr, 2)
  printFreeRegions()
  debugln ""

  debugln &"kernel: Freeing 4 frames at 0x4000"
  pmFree(0x4000.PhysAddr, 4)
  printFreeRegions()
  debugln ""

  debugln &"kernel: Freeing 2 frames at 0xa0000"
  pmFree(0xa0000.PhysAddr, 2)
  printFreeRegions()
  debugln ""

  quit()
