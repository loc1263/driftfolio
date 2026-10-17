import std/[unittest, os]
import ../src/driftfolio/universes

suite "loadUniverses":
  test "usa los defaults embebidos si el archivo no existe":
    let (chile, vanguard) = loadUniverses("no_existe_este_archivo.json")
    check chile.len > 0
    check vanguard.len > 0
    check "CHILE.SN" in chile
    check "VOO" in vanguard

  test "usa las listas del archivo cuando están presentes":
    let path = getTempDir() / "driftfolio_test_universes.json"
    writeFile(path, """{"chile": ["AAA.SN", "BBB.SN"], "vanguard": ["VOO"]}""")
    defer: removeFile(path)

    let (chile, vanguard) = loadUniverses(path)
    check chile == @["AAA.SN", "BBB.SN"]
    check vanguard == @["VOO"]

  test "conserva el default de una clave si falta en el archivo":
    let path = getTempDir() / "driftfolio_test_universes_partial.json"
    writeFile(path, """{"chile": ["AAA.SN"]}""")
    defer: removeFile(path)

    let (chile, vanguard) = loadUniverses(path)
    check chile == @["AAA.SN"]
    check vanguard.len > 0  # no estaba en el archivo: queda el default embebido

  test "conserva los defaults si el JSON es inválido":
    let path = getTempDir() / "driftfolio_test_universes_broken.json"
    writeFile(path, "{esto no es json")
    defer: removeFile(path)

    let (chile, vanguard) = loadUniverses(path)
    check chile.len > 0
    check vanguard.len > 0
