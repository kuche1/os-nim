
# wide strings shorthard
# instead of doing: newWideCString("Hello, world!\n").toWideCString
# with this you can do: W("Hello, world!\n")
# or even: W "Hello, world!\n"
# but not: W"Hello, world!\n"
# since this does not convert `\n` to a new line
proc W*(str: string): WideCString =
  newWideCString(str).toWideCString
