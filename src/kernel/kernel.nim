
import common/[malloc, libc]
import debugcon

proc KernelMain() {.exportc.} =
  debugln "Hello, world!"
  quit()
