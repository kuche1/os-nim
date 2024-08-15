
type
  MemoryType* = enum
    Free
    KernelCode
    KernelData
    KernelStack
    UserCode
    UserData
    UserStack
    Reserved

  MemoryMapEntry* = object
    `type`*: MemoryType
    start*: uint64
    nframes*: uint64

  MemoryMap* = object
    len*: uint
    entries*: ptr UncheckedArray[MemoryMapEntry]

  BootInfo* = object
    physicalMemoryMap*: MemoryMap
