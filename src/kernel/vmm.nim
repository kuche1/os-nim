
import std/options
import kernel/pagetables
import kernel/pmm  # only needed for PhysAddr

{.experimental: "codeReordering".}
# avoid having to forward declare

type
  VirtAddr* = distinct uint64
  PhysAlloc* = proc (nframes: uint64): Option[PhysAddr]

var
  physicalMemoryVirtualBase: uint64
  pmalloc: PhysAlloc

proc vmInit*(physMemoryVirtualBase: uint64, physAlloc: PhysAlloc) =
  physicalMemoryVirtualBase = physMemoryVirtualBase
  pmalloc = physAlloc

template `+!`*(p: VirtAddr, offset: uint64): VirtAddr =
  VirtAddr(cast[uint64](p) + offset)

template `-!`*(p: VirtAddr, offset: uint64): VirtAddr =
  VirtAddr(cast[uint64](p) - offset)

proc p2v*(phys: PhysAddr): VirtAddr =
  result = cast[VirtAddr](phys +! physicalMemoryVirtualBase)

proc v2p*(virt: VirtAddr): Option[PhysAddr] =
  let pml4 = getActivePML4()

  var pml4Index = (virt.uint64 shr 39) and 0x1FF
  var pdptIndex = (virt.uint64 shr 30) and 0x1FF
  var pdIndex = (virt.uint64 shr 21) and 0x1FF
  var ptIndex = (virt.uint64 shr 12) and 0x1FF

  if pml4.entries[pml4Index].present == 0:
    result = none(PhysAddr)
    return

  let pdptPhysAddr = PhysAddr(pml4.entries[pml4Index].physAddress shl 12)
  let pdpt = cast[ptr PDPTable](p2v(pdptPhysAddr))

  if pdpt.entries[pdptIndex].present == 0:
    result = none(PhysAddr)
    return

  let pdPhysAddr = PhysAddr(pdpt.entries[pdptIndex].physAddress shl 12)
  let pd = cast[ptr PDTable](p2v(pdPhysAddr))

  if pd.entries[pdIndex].present == 0:
    result = none(PhysAddr)
    return

  let ptPhysAddr = PhysAddr(pd.entries[pdIndex].physAddress shl 12)
  let pt = cast[ptr PTable](p2v(ptPhysAddr))

  if pt.entries[ptIndex].present == 0:
    result = none(PhysAddr)
    return

  result = some PhysAddr(pt.entries[ptIndex].physAddress shl 12)

proc getActivePML4*(): ptr PML4Table =
  var cr3: uint64
  asm """
    mov %0, cr3
    : "=r"(`cr3`)
  """
  result = cast[ptr PML4Table](p2v(cr3.PhysAddr))

proc setActivePML4*(pml4: ptr PML4Table) =
  var cr3 = v2p(cast[VirtAddr](pml4)).get
  asm """
    mov cr3, %0
    :
    : "r"(`cr3`)
  """

proc getOrCreateEntry[TP, TC](parent: ptr TP, index: uint64): ptr TC =
  var physAddr: PhysAddr
  if parent[index].present == 1:
    physAddr = PhysAddr(parent[index].physAddress shl 12)
  else:
    physAddr = pmalloc(1).get # TODO: handle allocation failure
    parent[index].physAddress = physAddr.uint64 shr 12
    parent[index].present = 1
  result = cast[ptr TC](p2v(physAddr))

proc mapPage(
  pml4: ptr PML4Table,
  virtAddr: VirtAddr,
  physAddr: PhysAddr,
  pageAccess: PageAccess,
  pageMode: PageMode,
) =
  let pml4Index = (virtAddr.uint64 shr 39) and 0x1FF
  let pdptIndex = (virtAddr.uint64 shr 30) and 0x1FF
  let pdIndex = (virtAddr.uint64 shr 21) and 0x1FF
  let ptIndex = (virtAddr.uint64 shr 12) and 0x1FF

  let access = cast[uint64](pageAccess)
  let mode = cast[uint64](pageMode)

  # Page Map Level 4 Table
  pml4[pml4Index].write = access
  pml4[pml4Index].user = mode
  var pdpt = getOrCreateEntry[PML4Table, PDPTable](pml4, pml4Index)

  # Page Directory Pointer Table
  pdpt[pdptIndex].write = access
  pdpt[pdptIndex].user = mode
  var pd = getOrCreateEntry[PDPTable, PDTable](pdpt, pdptIndex)

  # Page Directory
  pd[pdIndex].write = access
  pd[pdIndex].user = mode
  var pt = getOrCreateEntry[PDTable, PTable](pd, pdIndex)

  # Page Table
  pt[ptIndex].physAddress = physAddr.uint64 shr 12
  pt[ptIndex].present = 1
  pt[ptIndex].write = access
  pt[ptIndex].user = mode

proc mapRegion*(
  pml4: ptr PML4Table,
  virtAddr: VirtAddr,
  physAddr: PhysAddr,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode,
) =
  for i in 0 ..< pageCount:
    mapPage(pml4, virtAddr +! i * PageSize, physAddr +! i * PageSize, pageAccess, pageMode)

proc identityMapRegion*(
  pml4: ptr PML4Table,
  physAddr: PhysAddr,
  pageCount: uint64,
  pageAccess: PageAccess,
  pageMode: PageMode,
) =
  mapRegion(pml4, physAddr.VirtAddr, physAddr, pageCount, pageAccess, pageMode)
