# Package

version       = "0.2.0"
author        = "loc1263"
description   = "DriftFolio: ranking de momentum y portafolio Markowitz sobre acciones chilenas, ETFs Vanguard y mega-cap EEUU"
license       = "MIT"
srcDir        = "src"
bin           = @["driftfolio"]

# Dependencies

requires "nim >= 2.0.0"

task test, "Corre los tests unitarios":
  exec "nim c -r tests/test_analytics.nim"
  exec "nim c -r tests/test_linalg.nim"
