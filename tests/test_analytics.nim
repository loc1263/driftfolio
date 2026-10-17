import std/unittest
import ../src/driftfolio/analytics

suite "calcReturn":
  test "retorna 0 si no hay suficientes precios para la ventana":
    check calcReturn(@[], 21) == 0.0
    check calcReturn(@[100.0, 101.0], 21) == 0.0

  test "calcula el retorno porcentual entre el precio base y el último":
    let prices = @[100.0, 90.0, 110.0]
    check abs(calcReturn(prices, 2) - 10.0) < 1e-9

  test "retorna 0 si el precio base es 0 (evita división por cero)":
    check calcReturn(@[0.0, 50.0], 1) == 0.0

  test "funciona justo en el borde (prices.len == days + 1)":
    check calcReturn(@[50.0, 100.0], 1) == 100.0

suite "calcSMA":
  test "retorna 0 si no hay suficientes precios para el período":
    check calcSMA(@[1.0, 2.0], 5) == 0.0

  test "calcula el promedio simple de los últimos N precios":
    check calcSMA(@[10.0, 20.0, 30.0, 40.0], 2) == 35.0

  test "funciona justo en el borde (prices.len == period)":
    check calcSMA(@[10.0, 20.0], 2) == 15.0

suite "momentumScore":
  test "pondera 20% / 40% / 40%":
    check momentumScore(10.0, 10.0, 10.0) == 10.0
    check momentumScore(100.0, 0.0, 0.0) == 20.0
    check momentumScore(0.0, 100.0, 0.0) == 40.0

suite "buildQuote":
  test "arma un Quote consistente con los retornos y la SMA de los precios":
    var prices: seq[float]
    for i in 0 ..< 130:
      prices.add(100.0 + i.float)  # tendencia alcista constante

    let q = buildQuote("TEST", "https://example.com", prices)
    check q.ticker == "TEST"
    check q.price == prices[^1]
    check q.aboveSma50 == (q.price > q.sma50)
    check q.score == momentumScore(q.ret1m, q.ret3m, q.ret6m)
