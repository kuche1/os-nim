
type
  EfiStatus* = uint

  EfiHandle* = pointer

  EfiTableHeader = object
    signature: uint64
    revision: uint32
    headerSize: uint32
    crc32: uint32
    reserved: uint32

  # structure that is passed to the bootloader by UEFI firmware
  EfiSystemTable* = object
    header: EfiTableHeader
    firmwareVendor: WideCString
    firmwareRevision: uint32
    consoleInHandle: EfiHandle
    conIn: pointer
    consoleOutHandle: EfiHandle
    conOut: ptr SimpleTextOutputProtocol
    standardErrorHandle: EfiHandle
    stdErr: ptr SimpleTextOutputProtocol
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

var
  sysTable*: ptr EfiSystemTable

# wide strings shorthard
# instead of doing: newWideCString("Hello, world!\n").toWideCString
# with this you can do: W("Hello, world!\n")
# or even: W "Hello, world!\n"
# but not: W"Hello, world!\n"
# since this does not convert `\n` to a new line
proc W*(str: string): WideCString =
  newWideCString(str).toWideCString

proc consoleClear*() =
  assert not sysTable.isNil
  discard sysTable.conOut.clearScreen(sysTable.conOut)

proc consoleOut*(str: string) =
  assert not sysTable.isNil
  discard sysTable.conOut.outputString(sysTable.conOut, W(str))

proc consoleError*(str: string) =
  assert not sysTable.isNil
  discard sysTable.stdErr.outputString(sysTable.stdErr, W(str))
