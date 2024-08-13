
import libc
import malloc
import uefi

type
  EfiStatus = uint

  EfiHandle = pointer

  EfiTableHeader = object
    signature: uint64
    revision: uint32
    headerSize: uint32
    crc32: uint32
    reserved: uint32

  # structure that is passed to the bootloader by UEFI firmware
  EfiSystemTable = object
    header: EfiTableHeader
    firmwareVendor: WideCString
    firmwareRevision: uint32
    consoleInHandle: EfiHandle
    conIn: pointer
    consoleOutHandle: EfiHandle
    conOut: ptr SimpleTextOutputProtocol
    standardErrorHandle: EfiHandle
    stdErr: SimpleTextOutputProtocol
    runtimeServices: pointer
    bootServices: pointer
    numTableEntries: uint
    configTable: pointer
  
  SimpleTextOutputProtocol = object
    reset: pointer
    outputString: proc (this: ptr SimpleTextOutputProtocol, str: WideCString): EfiStatus {.cdecl.}
    testString: pointer
    queryMode: pointer
    setMode: pointer
    setAttribute: pointer
    clearScreen: proc (this: ptr SimpleTextOutputProtocol): EfiStatus {.cdecl.}
    setCursorPos: pointer
    enableCursor: pointer
    mode: ptr pointer

const
  EfiSuccess = 0
  EfiLoadError = 1

proc NimMain() {.importc.}

proc EfiMain(imgHandle: EfiHandle, sysTable: ptr EFiSystemTable): EfiStatus {.exportc.} =

  NimMain()

  discard sysTable.conOut.clearScreen(sysTable.conOut)
  discard sysTable.conOut.outputString(sysTable.conOut, W "Hello, world!\n")

  quit() # better quit (or probably just halt) than return to efi shell
  # return EfiSuccess
