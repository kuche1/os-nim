
import common/bootinfo

const
  FrameSize = 4096

type
  PhysAddr = distinct uint64

  PMNode = object
    nframes: uint64
    next: ptr PMNode

  PMRegion* = object
    start*: PhysAddr
    nframes*: uint64

var
  head: ptr PMNode
  maxPhysAddr: PhysAddr # exclusive
  reservedRegions: seq[PMRegion]

proc toPMNodePtr*(paddr: PhysAddr): ptr PMNode {.inline.} = cast[ptr PMNode](paddr)
proc toPhysAddr*(node: ptr PMNode): PhysAddr {.inline.} = cast[PhysAddr](node)

proc `==`*(a, b: PhysAddr): bool {.inline.} = a.uint64 == b.uint64
proc `<`(p1, p2: PhysAddr): bool {.inline.} = p1.uint64 < p2.uint64
proc `-`(p1, p2: PhysAddr): uint64 {.inline.} = p1.uint64 - p2.uint64

proc `+!`*(paddr: PhysAddr, offset: uint64): PhysAddr {.inline.} =
  PhysAddr(cast[uint64](paddr) + offset)

proc `+!`*(node: ptr PMNode, offset: uint64): ptr PMNode {.inline.} =
  cast[ptr PMNode](cast[uint64](node) + offset)

proc endAddr(paddr: PhysAddr, nframes: uint64): PhysAddr =
  result = paddr +! nframes * FrameSize

proc adjacent(node: ptr PMNode, paddr: PhysAddr): bool {.inline.} =
  result = (
    not node.isNil and
    node.toPhysAddr +! node.nframes * FrameSize == paddr
  )

proc adjacent(paddr: PhysAddr, nframes: uint64, node: ptr PMNode): bool {.inline.} =
  result = (
    not node.isNil and
    paddr +! nframes * FrameSize == node.toPhysAddr
  )

proc overlaps(region1, region2: PMRegion): bool =
  var r1 = region1
  var r2 = region2
  if r1.start > r2.start:
    r1 = region2
    r2 = region1
  result = (
    r1.start.PhysAddr < endAddr(r2.start.PhysAddr, r2.nframes) and
    r2.start.PhysAddr < endAddr(r1.start.PhysAddr, r1.nframes)
  )

proc pmInit*(memoryMap: MemoryMap) =
  var prev: ptr PMNode

  for i in 0 ..< memoryMap.len:
    let entry = memoryMap.entries[i]
    if entry.type == MemoryType.Free:
      maxPhysAddr = endAddr(entry.start.PhysAddr, entry.nframes)
      if not prev.isNil and adjacent(prev, entry.start.PhysAddr):
        # merge contiguous regions
        prev.nframes += entry.nframes
      else:
        # create a new node
        var node: ptr PMNode = entry.start.PhysAddr.toPMNodePtr
        node.nframes = entry.nframes
        node.next = nil

        if not prev.isNil:
          prev.next = node
        else:
          head = node

        prev = node

    elif entry.type == MemoryType.Reserved:
      reservedRegions.add(PMRegion(start: entry.start.PhysAddr, nframes: entry.nframes))
    
    elif i > 0:
      # check if there's a gap between the previous entry and the current entry
      let prevEntry = memoryMap.entries[i - 1]
      let gap = entry.start.PhysAddr - endAddr(prevEntry.start.PhysAddr, prevEntry.nframes)
      if gap > 0:
        reservedRegions.add(PMRegion(
          start: endAddr(prevEntry.start.PhysAddr, prevEntry.nframes),
          nframes: gap div FrameSize
        ))

iterator pmFreeRegions*(): tuple[paddr: PhysAddr, nframes: uint64] =
  var node = head
  while not node.isNil:
    yield (node.toPhysAddr, node.nframes)
    node = node.next
