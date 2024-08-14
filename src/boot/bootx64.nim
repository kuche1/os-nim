
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

proc EfiMainInner(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus =

  uefi.sysTable = sysTable

  echo "LigmaOS3 Bootloader"

  var status: EfiStatus

  # get the LoadedImage protocol from the image handle
  var loadedImage: ptr EfiLoadedImageProtocol

  consoleOut "boot: Acquiring LoadedImage protocol"
  checkStatus uefi.sysTable.bootServices.handleProtocol(
    imgHandle, EfiLoadedImageProtocolGuid, cast[ptr pointer](addr loadedImage)
  )

  # consoleClear()

  # echo "Hello"

  # # force an IndexDefect exception
  # let a = [1, 2, 3]
  # let n = 5
  # discard a[n]

  quit()
  # better quit (or probably just halt) than return to efi shell
  # return EfiSuccess

proc EfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =

  NimMain()

  try:
    return EfiMainInner(imgHandle, sysTable)
  except Exception as e:
    unhandledException(e)
