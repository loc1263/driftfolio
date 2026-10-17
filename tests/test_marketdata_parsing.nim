import std/[unittest, json]
import ../src/driftfolio/marketdata

suite "parseAdjClosePrices":
  test "extrae los precios de un JSON con la forma esperada":
    let data = %*{
      "chart": {
        "result": [{
          "indicators": {
            "adjclose": [{
              "adjclose": [100.5, 101.25, 0, 99.0, -5.0]
            }]
          }
        }]
      }
    }
    let parsed = parseAdjClosePrices(data)
    check parsed.error.len == 0
    # 0 y los negativos se descartan (precios inválidos), igual que antes del refactor
    check parsed.prices == @[100.5, 101.25, 99.0]

  test "reporta error si falta chart.result":
    let data = %*{"chart": {"error": "Not Found"}}
    let parsed = parseAdjClosePrices(data)
    check parsed.prices.len == 0
    check parsed.error.len > 0

  test "reporta error si chart.result está vacío":
    let data = %*{"chart": {"result": []}}
    let parsed = parseAdjClosePrices(data)
    check parsed.prices.len == 0
    check parsed.error.len > 0

  test "reporta error si falta indicators.adjclose":
    let data = %*{"chart": {"result": [{"indicators": {}}]}}
    let parsed = parseAdjClosePrices(data)
    check parsed.prices.len == 0
    check parsed.error.len > 0

  test "reporta error si falta el campo adjclose dentro del array":
    let data = %*{
      "chart": {"result": [{"indicators": {"adjclose": [{}]}}]}
    }
    let parsed = parseAdjClosePrices(data)
    check parsed.prices.len == 0
    check parsed.error.len > 0

  test "acepta enteros además de floats":
    let data = %*{
      "chart": {"result": [{"indicators": {"adjclose": [{"adjclose": [100, 101, 102]}]}}]}
    }
    let parsed = parseAdjClosePrices(data)
    check parsed.error.len == 0
    check parsed.prices == @[100.0, 101.0, 102.0]
