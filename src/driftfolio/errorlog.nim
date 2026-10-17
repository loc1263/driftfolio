import std/times

const ErrorLogFile* = "driftfolio_errors.log"

proc logError*(msg: string) =
  let timestamp = now().format("yyyy-MM-dd HH:mm:ss")
  var f: File
  if open(f, ErrorLogFile, fmAppend):
    f.writeLine("[" & timestamp & "] " & msg)
    f.close()
  echo msg
