## Logging de errores. Los mensajes se acumulan en memoria (M-019) en vez de
## abrir/cerrar el archivo en cada llamada: eso es lo que permite que varias
## descargas concurrentes (M-009) llamen a `logError` sin pisarse ni
## entrelazar líneas — Nim's async es cooperativo de un solo hilo, así que
## un `seq` compartido sin lock es seguro mientras no haya un `await` entre
## leerlo y escribirlo, que es justo lo que hace `logError` acá.

import std/times

const ErrorLogFile* = "driftfolio_errors.log"

var buffer: seq[string] = @[]

proc logError*(msg: string) =
  # Milisegundos (M-021): con descargas concurrentes, dos errores del mismo
  # segundo son normales — sin milisegundos no se puede saber cuál pasó
  # primero ni calcular cuánto tardó una descarga entre el log y el error.
  let timestamp = now().format("yyyy-MM-dd HH:mm:ss'.'fff")
  buffer.add("[" & timestamp & "] " & msg)
  echo msg

proc flushErrorLog*() =
  ## Vuelca el buffer a disco en una sola pasada. Se debe llamar una vez al
  ## final de main() (en un try/finally para que corra incluso si algo falla
  ## a mitad de la corrida).
  if buffer.len == 0:
    return

  var f: File
  if open(f, ErrorLogFile, fmAppend):
    for line in buffer:
      f.writeLine(line)
    f.close()
  else:
    echo "No se pudo escribir ", ErrorLogFile, ", se pierden ", buffer.len, " líneas de log"

  buffer.setLen(0)
