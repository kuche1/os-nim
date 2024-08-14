
import common/[malloc, libc]
import debugcon

proc NimMain() {.importc.}

proc KernelMain() {.exportc.} =
  NimMain()
  debugln "Hello, world!"
  quit()
