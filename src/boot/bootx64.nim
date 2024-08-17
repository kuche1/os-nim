
import std/[strformat, sets, options]
import common/[libc, malloc, uefi, bootinfo]
import kernel/[pmm, vmm, pagetables]
import debugcon

proc NimMain() {.importc.}

type
  KernelEntryPoint = proc (bootInfo: ptr BootInfo) {.cdecl.} # must be the same as `KernelMain`

const
  PageSize = 4096

type
  AlignedPage = object
    data {.align(PageSize).}: array[PageSize, uint8]

const
  KernelPhysicalBase = 0x10_0000'u64
  KernelVirtualBase = 0xFFFF_8000_0000_0000'u64 + KernelPhysicalBase

  KernelStackVirtualBase = 0xFFFF_8001_0000_0000'u64 # KernelVirtualBase + 4 GiB
  KernelStackSize = 16 * 1024'u64
  KernelStackPages = KernelStackSize div PageSize

  BootInfoVirtualBase = KernelStackVirtualBase + KernelStackSize # after kernel stack

  PhysicalMemoryVirtualBase = 0xFFFF_8002_0000_0000'u64 # KernelVirtualBase + 8 GiB

# We use a HashSet here because the `EfiMemoryType` has values greater than 64K,
# which is the maximum value supported by Nim sets.
const
  FreeMemoryTypes = [
    EfiConventionalMemory,
    EfiBootServicesCode,
    EfiBootServicesData,
    EfiLoaderCode,
    EfiLoaderData,
  ].toHashSet

proc createPageTable(
  bootloaderBase: uint64,
  bootloaderPages: uint64,
  kernelImageBase: uint64,
  kernelImagePages: uint64,
  kernelStackBase: uint64,
  kernelStackPages: uint64,
  bootInfoBase: uint64,
  bootInfoPages: uint64,
  physMemoryPages: uint64,
): ptr PML4Table =

  proc bootAlloc(nframes: uint64): Option[PhysAddr] =
    result = some(cast[PhysAddr](new AlignedPage))

  # initialize vmm using identity-mapped physical memory
  vmInit(physMemoryVirtualBase = 0'u64, physAlloc = bootAlloc)

  debugln &"boot: Creating new page tables"
  var pml4 = cast[ptr PML4Table](bootAlloc(1).get)

  # identity-map bootloader image
  debugln &"""boot:   {"Identity-mapping bootloader\:":<30} base={bootloaderBase:#010x}, pages={bootloaderPages}"""
  identityMapRegion(pml4, bootloaderBase.PhysAddr, bootloaderPages.uint64, paReadWrite, pmSupervisor)

  # identity-map boot info
  debugln &"""boot:   {"Identity-mapping BootInfo\:":<30} base={bootInfoBase:#010x}, pages={bootInfoPages}"""
  identityMapRegion(pml4, bootInfoBase.PhysAddr, bootInfoPages, paReadWrite, pmSupervisor)

  # map kernel to higher half
  debugln &"""boot:   {"Mapping kernel to higher half\:":<30} base={KernelVirtualBase:#010x}, pages={kernelImagePages}"""
  mapRegion(pml4, KernelVirtualBase.VirtAddr, kernelImageBase.PhysAddr, kernelImagePages, paReadWrite, pmSupervisor)

  # map kernel stack
  debugln &"""boot:   {"Mapping kernel stack\:":<30} base={KernelStackVirtualBase:#010x}, pages={kernelStackPages}"""
  mapRegion(pml4, KernelStackVirtualBase.VirtAddr, kernelStackBase.PhysAddr, kernelStackPages, paReadWrite, pmSupervisor)

  # map all physical memory; assume 128 MiB of physical memory
  debugln &"""boot:   {"Mapping physical memory\:":<30} base={PhysicalMemoryVirtualBase:#010x}, pages={physMemoryPages}"""
  mapRegion(pml4, PhysicalMemoryVirtualBase.VirtAddr, 0.PhysAddr, physMemoryPages, paReadWrite, pmSupervisor)

  result = pml4

proc convertUefiMemoryMap(
  uefiMemoryMap: ptr UncheckedArray[EfiMemoryDescriptor],
  uefiMemoryMapSize: uint,
  uefiMemoryMapDescriptorSize: uint,
): seq[MemoryMapEntry] =
  let uefiNumMemoryMapEntries = uefiMemoryMapSize div uefiMemoryMapDescriptorSize

  for i in 0 ..< uefiNumMemoryMapEntries:
    let uefiEntry = cast[ptr EfiMemoryDescriptor](
      cast[uint64](uefiMemoryMap) + i * uefiMemoryMapDescriptorSize
    )
    let memoryType =
      if uefiEntry.type in FreeMemoryTypes:
        Free
      elif uefiEntry.type == OsvKernelCode:
        KernelCode
      elif uefiEntry.type == OsvKernelData:
        KernelData
      elif uefiEntry.type == OsvKernelStack:
        KernelStack
      else:
        Reserved
    result.add(MemoryMapEntry(
      type: memoryType,
      start: uefiEntry.physicalStart,
      nframes: uefiEntry.numberOfPages
    ))

proc createVirtualMemoryMap(
  kernelImagePages: uint64,
  physMemoryPages: uint64,
): seq[MemoryMapEntry] =

  result.add(MemoryMapEntry(
    type: KernelCode,
    start: KernelVirtualBase,
    nframes: kernelImagePages
  ))
  result.add(MemoryMapEntry(
    type: KernelStack,
    start: KernelStackVirtualBase,
    nframes: KernelStackPages
  ))
  result.add(MemoryMapEntry(
    type: KernelData,
    start: BootInfoVirtualBase,
    nframes: 1
  ))
  result.add(MemoryMapEntry(
    type: KernelData,
    start: PhysicalMemoryVirtualBase,
    nframes: physMemoryPages
  ))

proc createBootInfo(
  bootInfoBase: uint64,
  kernelImagePages: uint64,
  physMemoryPages: uint64,
  physMemoryMap: seq[MemoryMapEntry],
  virtMemoryMap: seq[MemoryMapEntry],
): ptr BootInfo =
  var bootInfo = cast[ptr BootInfo](bootInfoBase)
  bootInfo.physicalMemoryVirtualBase = PhysicalMemoryVirtualBase

  # copy physical memory map entries to boot info
  bootInfo.physicalMemoryMap.len = physMemoryMap.len.uint
  bootInfo.physicalMemoryMap.entries =
    cast[ptr UncheckedArray[MemoryMapEntry]](bootInfoBase + sizeof(BootInfo).uint64)
  for i in 0 ..< physMemoryMap.len:
    bootInfo.physicalMemoryMap.entries[i] = physMemoryMap[i]
  let physMemoryMapSize = physMemoryMap.len.uint64 * sizeof(MemoryMapEntry).uint64

  # copy virtual memory map entries to boot info
  bootInfo.virtualMemoryMap.len = virtMemoryMap.len.uint
  bootInfo.virtualMemoryMap.entries =
    cast[ptr UncheckedArray[MemoryMapEntry]](bootInfoBase + sizeof(BootInfo).uint64 + physMemoryMapSize)
  for i in 0 ..< virtMemoryMap.len:
    bootInfo.virtualMemoryMap.entries[i] = virtMemoryMap[i]
  
  result = bootInfo

proc unhandledException*(e: ref Exception) =
  echo "Unhandled exception: " & e.msg & " [" & $e.name & "]"
  if e.trace.len > 0:
    echo "Stack trace:"
    echo getStackTrace(e)
  quit()

proc checkStatus*(status: EfiStatus) =
  if status != EfiSuccess:
    consoleOut &" [failed, status = {status:#x}]"
    quit()
  consoleOut " [success]\r\n"

proc EfiMainInner(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus =

  uefi.sysTable = sysTable

  # consoleClear()

  echo "LigmaOS3 Bootloader"

  var status: EfiStatus

  # get the LoadedImage protocol from the image handle
  var loadedImage: ptr EfiLoadedImageProtocol

  consoleOut "boot: Acquiring LoadedImage protocol"
  checkStatus uefi.sysTable.bootServices.handleProtocol(
    imgHandle, EfiLoadedImageProtocolGuid, cast[ptr pointer](addr loadedImage)
  )

  # get the FileSystem protocol from the device handle
  var fileSystem: ptr EfiSimpleFileSystemProtocol

  consoleOut "boot: Acquiring SimpleFileSystem protocol"
  checkStatus uefi.sysTable.bootServices.handleProtocol(
    loadedImage.deviceHandle, EfiSimpleFileSystemProtocolGuid, cast[ptr pointer](addr fileSystem)
  )

  # open the root directory
  var rootDir: ptr EfiFileProtocol

  consoleOut "boot: Opening root directory"
  checkStatus fileSystem.openVolume(fileSystem, addr rootDir)

  # open the kernel file
  var kernelFile: ptr EfiFileProtocol
  let kernelPath = W"efi\fusion\kernel.bin"

  consoleOut "boot: Opening kernel file: "
  consoleOut kernelPath
  checkStatus rootDir.open(rootDir, addr kernelFile, kernelPath, 1, 1)

  # get kernel file size
  var kernelInfo: EfiFileInfo
  var kernelInfoSize = sizeof(EfiFileInfo).uint

  consoleOut "boot: Getting kernel file info"
  checkStatus kernelFile.getInfo(kernelFile, addr EfiFileInfoGuid, addr kernelInfoSize, addr kernelInfo)
  echo &"boot: Kernel file size: {kernelInfo.fileSize} bytes"

  consoleOut &"boot: Allocating memory for kernel image "
  let kernelImageBase = cast[pointer](KernelPhysicalBase)
  let kernelImagePages = (kernelInfo.fileSize + 0xFFF).uint div PageSize.uint # round up to nearest page
  checkStatus uefi.sysTable.bootServices.allocatePages(
    AllocateAddress,
    OsvKernelCode,
    kernelImagePages,
    cast[ptr EfiPhysicalAddress](addr kernelImageBase)
  )

  consoleOut &"boot: Allocating memory for kernel stack (16 KiB) "
  var kernelStackBase: uint64
  let kernelStackPages = KernelStackSize div PageSize
  checkStatus uefi.sysTable.bootServices.allocatePages(
    AllocateAnyPages,
    OsvKernelStack,
    kernelStackPages,
    kernelStackBase.addr,
  )

  consoleOut &"boot: Allocating memory for BootInfo"
  var bootInfoBase: uint64
  checkStatus uefi.sysTable.bootServices.allocatePages(
    AllocateAnyPages,
    OsvKernelData,
    1,
    bootInfoBase.addr,
  )

  # read the kernel into memory
  consoleOut "boot: Reading kernel into memory"
  checkStatus kernelFile.read(kernelFile, cast[ptr uint](addr kernelInfo.fileSize), kernelImageBase)

  # close the kernel file
  consoleOut "boot: Closing kernel file"
  checkStatus kernelFile.close(kernelFile)

  # close the root directory
  consoleOut "boot: Closing root directory"
  checkStatus rootDir.close(rootDir)

  # memory map
  var memoryMapSize = 0.uint
  var memoryMap: ptr UncheckedArray[EfiMemoryDescriptor]
  var memoryMapKey: uint
  var memoryMapDescriptorSize: uint
  var memoryMapDescriptorVersion: uint32

  # get memory map size
  status = uefi.sysTable.bootServices.getMemoryMap(
    addr memoryMapSize,
    cast[ptr EfiMemoryDescriptor](nil),
    cast[ptr uint](nil),
    cast[ptr uint](addr memoryMapDescriptorSize),
    cast[ptr uint32](nil)
  )
  # increase memory map size to account for the next call to allocatePool
  inc memoryMapSize, memoryMapDescriptorSize

  # allocate pool for memory map (this changes the memory map size, hence the previous step)
  consoleOut "boot: Allocating pool for memory map"
  checkStatus uefi.sysTable.bootServices.allocatePool(
    EfiLoaderData, memoryMapSize, cast[ptr pointer](addr memoryMap)
  )

  # now get the memory map
  consoleOut "boot: Getting memory map and exiting boot services\n"
  status = uefi.sysTable.bootServices.getMemoryMap(
    addr memoryMapSize,
    cast[ptr EfiMemoryDescriptor](memoryMap),
    addr memoryMapKey,
    addr memoryMapDescriptorSize,
    addr memoryMapDescriptorVersion
  )

  # IMPORTANT: After this point we cannot output anything to the console, since doing
  # so may allocate memory and change the memory map, invalidating our map key. We can
  # only output to the console in case of an error (since we quit anyway).

  if status != EfiSuccess:
    echo &"boot: Failed to get memory map: {status:#x}"
    quit()

  status = uefi.sysTable.bootServices.exitBootServices(imgHandle, memoryMapKey)
  if status != EfiSuccess:
    echo &"boot: Failed to exit boot services: {status:#x}"
    quit()
  
  # ======= NO MORE UEFI BOOT SERVICES =======


  let physMemoryMap = convertUefiMemoryMap(memoryMap, memoryMapSize, memoryMapDescriptorSize)

  # get max free physical memory address
  var maxPhysAddr: PhysAddr
  for i in 0 ..< physMemoryMap.len:
    if physMemoryMap[i].type == Free:
      maxPhysAddr = physMemoryMap[i].start.PhysAddr +! physMemoryMap[i].nframes * PageSize

  let physMemoryPages: uint64 = maxPhysAddr.uint64 div PageSize

  let virtMemoryMap = createVirtualMemoryMap(kernelImagePages, physMemoryPages)

  debugln &"boot: Preparing BootInfo"
  let bootInfo = createBootInfo(
    bootInfoBase,
    kernelImagePages,
    physMemoryPages,
    physMemoryMap,
    virtMemoryMap,
  )

  let bootloaderPages = (loadedImage.imageSize.uint + 0xFFF) div 0x1000.uint

  let pml4 = createPageTable(
    cast[uint64](loadedImage.imageBase),
    bootloaderPages,
    cast[uint64](kernelImageBase),
    kernelImagePages,
    kernelStackBase,
    kernelStackPages,
    bootInfoBase,
    1, # bootInfoPages
    physMemoryPages,
  )

  # jump to kernel
  let kernelStackTop = KernelStackVirtualBase + KernelStackSize
  let cr3 = cast[uint64](pml4)
  debugln &"boot: Jumping to kernel at {cast[uint64](KernelVirtualBase):#010x}"
  asm """
    mov rdi, %0  # bootInfo
    mov cr3, %2  # PML4
    mov rsp, %1  # kernel stack top
    jmp %3       # kernel entry point
    :
    : "r"(`bootInfoBase`),
      "r"(`kernelStackTop`),
      "r"(`cr3`),
      "r"(`KernelVirtualBase`)
  """

  # we should never get here
  quit()

proc EfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =

  NimMain()

  try:
    return EfiMainInner(imgHandle, sysTable)
  except Exception as e:
    unhandledException(e)
