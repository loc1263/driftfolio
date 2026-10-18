import std/[unittest, os]
import ../src/driftfolio/config

suite "loadConfig":
  test "usa los defaults de fábrica si el archivo no existe":
    let cfg = loadConfig("no_existe_este_archivo.json")
    check cfg.ret1mDays == DefaultConfig.ret1mDays
    check cfg.markowitzTopN == DefaultConfig.markowitzTopN
    check cfg.runChile == true

  test "usa los valores del archivo cuando están presentes":
    let path = getTempDir() / "driftfolio_test_config.json"
    writeFile(path, """{
      "universos": {"chile": true, "vanguard": false, "megaCap": true},
      "score": {"ret1mDias": 10, "ret3mDias": 30, "ret6mDias": 90,
                "ret1mPeso": 0.3, "ret3mPeso": 0.3, "ret6mPeso": 0.4,
                "smaPeriodo": 20, "historiaMinimaDias": 95},
      "markowitz": {"topN": 10, "historicoAnios": 3, "ewmaLambda": 0.9,
                    "topePorPosicion": 0.25, "concentradoN": 3, "concentradoTope": 0.5}
    }""")
    defer: removeFile(path)

    let cfg = loadConfig(path)
    check cfg.runVanguard == false
    check cfg.ret1mDays == 10
    check cfg.ret6mWeight == 0.4
    check cfg.smaPeriod == 20
    check cfg.markowitzTopN == 10
    check cfg.ewmaLambda == 0.9
    check cfg.markowitzFinalN == 3

  test "conserva el default de un campo que falta en el archivo":
    let path = getTempDir() / "driftfolio_test_config_partial.json"
    writeFile(path, """{"score": {"ret1mDias": 15}}""")
    defer: removeFile(path)

    let cfg = loadConfig(path)
    check cfg.ret1mDays == 15
    check cfg.ret3mDays == DefaultConfig.ret3mDays
    check cfg.markowitzTopN == DefaultConfig.markowitzTopN

  test "conserva los defaults si el JSON es inválido":
    let path = getTempDir() / "driftfolio_test_config_broken.json"
    writeFile(path, "{esto no es json")
    defer: removeFile(path)

    let cfg = loadConfig(path)
    check cfg.ret1mDays == DefaultConfig.ret1mDays

  test "un valor fuera de rango cae en su default, el resto del archivo se respeta":
    let path = getTempDir() / "driftfolio_test_config_outofrange.json"
    writeFile(path, """{
      "score": {"ret1mDias": -5, "smaPeriodo": 20},
      "markowitz": {"ewmaLambda": 5.0}
    }""")
    defer: removeFile(path)

    let cfg = loadConfig(path)
    check cfg.ret1mDays == DefaultConfig.ret1mDays   # -5 inválido: vuelve al default
    check cfg.smaPeriod == 20                         # válido: se respeta
    check cfg.ewmaLambda == DefaultConfig.ewmaLambda  # 5.0 fuera de (0,1): vuelve al default

  test "ajusta historiaMinimaDias si es menor que ret6mDias + 1":
    let path = getTempDir() / "driftfolio_test_config_coherence.json"
    writeFile(path, """{"score": {"ret6mDias": 200, "historiaMinimaDias": 50}}""")
    defer: removeFile(path)

    let cfg = loadConfig(path)
    check cfg.ret6mDays == 200
    check cfg.minHistoryDays == 201

suite "writeDefaultConfig":
  test "escribe un archivo que loadConfig puede releer igual a los defaults":
    let path = getTempDir() / "driftfolio_test_config_roundtrip.json"
    defer: removeFile(path)

    writeDefaultConfig(path)
    let cfg = loadConfig(path)
    check cfg.ret1mDays == DefaultConfig.ret1mDays
    check cfg.ret1mWeight == DefaultConfig.ret1mWeight
    check cfg.markowitzTopN == DefaultConfig.markowitzTopN
    check cfg.ewmaLambda == DefaultConfig.ewmaLambda
