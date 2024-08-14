
type

  EfiStatus* = uint

  EfiHandle* = pointer

  EfiTableHeader = object
    signature*: uint64
    revision*: uint32
    headerSize*: uint32
    crc32*: uint32
    reserved*: uint32

  # structure that is passed to the bootloader by UEFI firmware
  EfiSystemTable* = object
    header*: EfiTableHeader
    firmwareVendor*: WideCString
    firmwareRevision*: uint32
    consoleInHandle*: EfiHandle
    conIn*: pointer
    consoleOutHandle*: EfiHandle
    conOut*: ptr SimpleTextOutputProtocol
    standardErrorHandle*: EfiHandle
    stdErr*: ptr SimpleTextOutputProtocol
    runtimeServices*: pointer
    bootServices*: ptr EfiBootServices
    numTableEntries*: uint
    configTable*: pointer
  
  SimpleTextOutputProtocol* = object
    reset*: pointer
    outputString*: proc (this: ptr SimpleTextOutputProtocol, str: WideCString): EfiStatus {.cdecl.}
    testString*: pointer
    queryMode*: pointer
    setMode*: pointer
    setAttribute*: pointer
    clearScreen*: proc (this: ptr SimpleTextOutputProtocol): EfiStatus {.cdecl.}
    setCursorPos*: pointer
    enableCursor*: pointer
    mode*: ptr pointer

  EfiLoadedImageProtocol* = object
    revision*: uint32
    parentHandle*: EfiHandle
    systemTable*: ptr EfiSystemTable
    # Source location of the image
    deviceHandle*: EfiHandle
    filePath*: pointer
    reserved*: pointer
    # Image's load options
    loadOptionsSize*: uint32
    loadOptions*: pointer
    # Location where image was loaded
    imageBase*: pointer
    imageSize*: uint64
    imageCodeType*: EfiMemoryType
    imageDataType*: EfiMemoryType
    unload*: pointer

  EfiMemoryType* = enum
    EfiReservedMemory
    EfiLoaderCode
    EfiLoaderData
    EfiBootServicesCode
    EfiBootServicesData
    EfiRuntimeServicesCode
    EfiRuntimeServicesData
    EfiConventionalMemory
    EfiUnusableMemory
    EfiACPIReclaimMemory
    EfiACPIMemoryNVS
    EfiMemoryMappedIO
    EfiMemoryMappedIOPortSpace
    EfiPalCode
    EfiPersistentMemory
    EfiUnacceptedMemory
    OsvKernelCode = 0x80000000
    OsvKernelData = 0x80000001
    OsvKernelStack = 0x80000002
    EfiMaxMemoryType

  EfiBootServices* = object
    hdr*: EfiTableHeader
    # task priority services
    raiseTpl*: pointer
    restoreTpl*: pointer
    # memory services
    allocatePages*: proc (
        allocateType: EfiAllocateType,
        memoryType: EfiMemoryType,
        pages: uint,
        memory: ptr EfiPhysicalAddress
      ): EfiStatus {.cdecl.}
    freePages*: pointer
    getMemoryMap*: proc (
        memoryMapSize: ptr uint,
        memoryMap: ptr EfiMemoryDescriptor,
        mapKey: ptr uint,
        descriptorSize: ptr uint,
        descriptorVersion: ptr uint32
      ): EfiStatus {.cdecl.}
    allocatePool*: proc (
        poolType: EfiMemoryType,
        size: uint,
        buffer: ptr pointer
      ): EfiStatus {.cdecl.}
    freePool*: pointer
    # event & timer services
    createEvent*: pointer
    setTimer*: pointer
    waitForEvent*: pointer
    signalEvent*: pointer
    closeEvent*: pointer
    checkEvent*: pointer
    # protocol handler services
    installProtocolInterface*: pointer
    reinstallProtocolInterface*: pointer
    uninstallProtocolInterface*: pointer
    handleProtocol*: proc (handle: EfiHandle, protocol: EfiGuid, `interface`: ptr pointer): EfiStatus {.cdecl.}
    reserved*: pointer
    registerProtocolNotify*: pointer
    locateHandle*: pointer
    locateDevicePath*: pointer
    installConfigurationTable*: pointer
    # image services
    loadImage*: pointer
    startImage*: pointer
    exit*: pointer
    unloadImage*: pointer
    exitBootServices*: proc (
        imageHandle: EfiHandle,
        mapKey: uint
      ): EfiStatus {.cdecl.}
    # misc services
    getNextMonotonicCount*: pointer
    stall*: pointer
    setWatchdogTimer*: pointer
    # driver support services
    connectController*: pointer
    disconnectController*: pointer
    # open and close protocol services
    openProtocol*: pointer
    closeProtocol*: pointer
    openProtocolInformation*: pointer
    # library services
    protocolsPerHandle*: pointer
    locateHandleBuffer*: pointer
    locateProtocol*: pointer
    installMultipleProtocolInterfaces*: pointer
    uninstallMultipleProtocolInterfaces*: pointer
    # 32-bit CRC services
    calculateCrc32*: pointer
    # misc services
    copyMem*: pointer
    setMem*: pointer
    createEventEx*: pointer

  EfiGuid* = object
    data1: uint32
    data2: uint16
    data3: uint16
    data4: array[8, uint8]

  EfiSimpleFileSystemProtocol* = object
    revision*: uint64
    openVolume*: proc (this: ptr EfiSimpleFileSystemProtocol, root: ptr ptr EfiFileProtocol):
      EfiStatus {.cdecl.}

  EfiFileProtocol* = object
    revision*: uint64
    open*: proc (
        this: ptr EfiFileProtocol,
        newHandle: ptr ptr EfiFileProtocol,
        fileName: WideCString,
        openMode: uint64,
        attributes: uint64
      ): EfiStatus {.cdecl.}
    close*: proc (this: ptr EfiFileProtocol): EfiStatus {.cdecl.}
    delete*: pointer
    read*: proc (
        this: ptr EfiFileProtocol,
        bufferSize: ptr uint,
        buffer: pointer
      ): EfiStatus {.cdecl.}
    write*: pointer
    getPosition*: pointer
    setPosition*: pointer
    getInfo*: proc (
        this: ptr EfiFileProtocol,
        infoType: ptr EfiGuid,
        infoSize: ptr uint,
        info: pointer
      ): EfiStatus {.cdecl.}
    setInfo*: pointer
    flush*: pointer
    openEx*: pointer
    readEx*: pointer
    writeEx*: pointer
    flushEx*: pointer

  EfiFileInfo* = object
    size*: uint64
    fileSize*: uint64
    physicalSize*: uint64
    createTime*: EfiTime
    lastAccessTime*: EfiTime
    modificationTime*: EfiTime
    attribute*: uint64
    fileName*: array[256, Utf16Char] # this is a flexible array member (https://en.wikipedia.org/wiki/Flexible_array_member) but that's not supported in nim so fixed size array is used instead

  EfiTime* = object
    year*: uint16
    month*: uint8
    day*: uint8
    hour*: uint8
    minute*: uint8
    second*: uint8
    pad1*: uint8
    nanosecond*: uint32
    timeZone*: int16
    daylight*: uint8
    pad2*: uint8

  EfiAllocateType* = enum
    AllocateAnyPages,
    AllocateMaxAddress,
    AllocateAddress,
    MaxAllocateType

  EfiMemoryDescriptor* = object
    `type`*: EfiMemoryType
    physicalStart*: EfiPhysicalAddress
    virtualStart*: EfiVirtualAddress
    numberOfPages*: uint64
    attribute*: uint64

  EfiPhysicalAddress* = uint64
  EfiVirtualAddress* = uint64

const

  EfiSuccess* = 0
  EfiLoadError* = 1

  EfiLoadedImageProtocolGuid* = EfiGuid(
    data1: 0x5B1B31A1, data2: 0x9562, data3: 0x11d2,
    data4: [0x8e, 0x3f, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]
  )

  EfiSimpleFileSystemProtocolGuid* = EfiGuid(
    data1: 0x964e5b22'u32, data2: 0x6459, data3: 0x11d2,
    data4: [0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]
  )

  EfiFileInfoGuid* = EfiGuid(
    data1: 0x09576e92'u32, data2: 0x6d3f, data3: 0x11d2,
    data4: [0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b]
  )

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

proc consoleOut*(str: WideCString) =
  assert not sysTable.isNil
  discard sysTable.conOut.outputString(sysTable.conOut, str)

proc consoleError*(str: string) =
  assert not sysTable.isNil
  discard sysTable.stdErr.outputString(sysTable.stdErr, W(str))
