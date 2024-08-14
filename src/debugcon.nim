
const
  DebugConPort = 0xE9

proc portOut8(port: uint16, data: uint8) =
  asm """
    out %0, %1
    :
    :"Nd"(`port`), "a"(`data`)
  """

proc debug*(msgs: varargs[string]) =
  ## Send messages to the debug console.
  for msg in msgs:
    for ch in msg:
      portOut8(DebugConPort, ch.uint8)

proc debugln*(msgs: varargs[string]) =
  ## Send messages to the debug console. A newline is appended at the end.
  debug(msgs)
  debug("\r\n")
