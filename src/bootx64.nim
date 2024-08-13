
import libc
import malloc
import uefi

proc NimMain() {.importc.}

proc EfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =

  NimMain()

  uefi.sysTable = sysTable

  consoleClear()
  echo "Hello, world! adsfcergce"

  quit()
  # better quit (or probably just halt) than return to efi shell
  # return EfiSuccess
