
import common/[libc, malloc, uefi]
import std/strformat

proc NimMain() {.importc.}

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

const
  PageSize = 4096
  KernelPhysicalBase = 0x100000
  KernelStackSize = 128 * 1024'u64

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

  # read the kernel into memory
  consoleOut "boot: Reading kernel into memory"
  checkStatus kernelFile.read(kernelFile, cast[ptr uint](addr kernelInfo.fileSize), kernelImageBase)

  # close the kernel file
  consoleOut "boot: Closing kernel file"
  checkStatus kernelFile.close(kernelFile)

  # close the root directory
  consoleOut "boot: Closing root directory"
  checkStatus rootDir.close(rootDir)

  quit()
  # better quit (or probably just halt) than return to efi shell
  # return EfiSuccess

proc EfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =

  NimMain()

  try:
    return EfiMainInner(imgHandle, sysTable)
  except Exception as e:
    unhandledException(e)
