
import libc
import malloc

type
  EfiStatus = uint
  EfiHandle = pointer
  EFiSystemTable = object # to be defined later

const
  EfiSuccess = 0

proc NimMain() {.importc.}

proc EfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =
  NimMain()
  return EfiSuccess
