
import std/strformat
import std/options
import common/[bootinfo, libc, malloc]
import kernel/[pmm, vmm, gdt]
import debugcon

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

proc printVMRegions(memoryMap: MemoryMap) =
  debug &"""   {"Start":>20}"""
  debug &"""   {"Type":12}"""
  debug &"""   {"VM Size (KB)":>12}"""
  debug &"""   {"#Pages":>9}"""
  debugln ""
  for i in 0 ..< memoryMap.len:
    let entry = memoryMap.entries[i]
    debug &"   {entry.start:>#20x}"
    debug &"   {entry.type:#12}"
    debug &"   {entry.nframes * 4:>#12}"
    debug &"   {entry.nframes:>#9}"
    debugln ""

proc KernelMainInner(bootInfo: ptr BootInfo) =
  debugln ""
  debugln "kernel: Fusion Kernel"

  debug "kernel: Initializing physical memory manager "
  pmInit(bootInfo.physicalMemoryVirtualBase, bootInfo.physicalMemoryMap)
  debugln "[success]"

  debug "kernel: Initializing virtual memory manager "
  vmInit(bootInfo.physicalMemoryVirtualBase, pmm.pmAlloc)
  debugln "[success]"

  debugln "kernel: Physical memory free regions "
  printFreeRegions()

  debugln "kernel: Virtual memory regions "
  printVMRegions(bootInfo.virtualMemoryMap)

  debug "kernel: Initializing GDT "
  gdtInit()
  debugln "[success]"

  quit()
