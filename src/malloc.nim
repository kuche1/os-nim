
{.used.}
# tell the compiler to consider the module as used
# even if none of the procs

var
  heap*: array[1*1024*1024, byte] # 1 MiB heap
  heapBumpPtr*: int = cast[int](addr heap)
  heapMaxPtr*: int = cast[int](addr heap) + heap.high

proc malloc*(size: csize_t): pointer {.exportc.} =
  if heapBumpPtr + size.int > heapMaxPtr:
    return nil

  result = cast[pointer](heapBumpPtr)
  inc heapBumpPtr, size.int

proc calloc*(num: csize_t, size: csize_t): pointer {.exportc.} =
  result = malloc(size * num)

# ne razbitam zashto tova ne go vijda no ok
proc free*(p: pointer) {.exportc.} =
  discard

proc realloc*(p: pointer, new_size: csize_t): pointer {.exportc.} =
  result = malloc(new_size)
  copyMem(result, p, new_size)
  free(p)
