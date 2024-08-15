
import std/strformat
import std/sets
import common/[libc, malloc, uefi, bootinfo]

proc NimMain() {.importc.}

type
  KernelEntryPoint = proc (bootInfo: ptr BootInfo) {.cdecl.} # must be the same as `KernelMain`

const
  PageSize = 4096
  KernelPhysicalBase = 0x100000
  KernelStackSize = 128 * 1024'u64

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

  var bootInfo = cast[ptr BootInfo](bootInfoBase)

  # copy physical memory map entries to boot info
  bootInfo.physicalMemoryMap.len = physMemoryMap.len.uint
  bootInfo.physicalMemoryMap.entries =
    cast[ptr UncheckedArray[MemoryMapEntry]](bootInfoBase + sizeof(BootInfo).uint64)
  for i in 0 ..< physMemoryMap.len:
    bootInfo.physicalMemoryMap.entries[i] = physMemoryMap[i]

  # jump to kernel
  let kernelMain = cast[KernelEntryPoint](kernelImageBase)
  kernelMain(bootInfo)

  quit()

proc EfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =

  NimMain()

  try:
    return EfiMainInner(imgHandle, sysTable)
  except Exception as e:
    unhandledException(e)
