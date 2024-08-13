
import libc
import malloc
import uefi

proc NimMain() {.importc.}

proc unhandledException*(e: ref Exception) =
  echo "Unhandled exception: " & e.msg & " [" & $e.name & "]"
  if e.trace.len > 0:
    echo "Stack trace:"
    echo getStackTrace(e)
  quit()

proc EfiMainInner(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus =

  uefi.sysTable = sysTable

  consoleClear()

  echo "Hello"

  # force an IndexDefect exception
  let a = [1, 2, 3]
  let n = 5
  discard a[n]

  quit()
  # better quit (or probably just halt) than return to efi shell
  # return EfiSuccess

proc EfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =
  NimMain()

  try:
    return EfiMainInner(imgHandle, sysTable)
  except Exception as e:
    unhandledException(e)
