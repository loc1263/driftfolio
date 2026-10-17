import std/unittest
import ../src/driftfolio/linalg

suite "solveLinearSystem":
  test "resuelve un sistema diagonal simple":
    let a = @[@[2.0, 0.0], @[0.0, 2.0]]
    let b = @[4.0, 6.0]
    let x = solveLinearSystem(a, b)
    check x.len == 2
    check abs(x[0] - 2.0) < 1e-9
    check abs(x[1] - 3.0) < 1e-9

  test "resuelve un sistema que requiere pivoteo parcial":
    let a = @[@[0.0, 1.0], @[1.0, 1.0]]
    let b = @[2.0, 3.0]
    let x = solveLinearSystem(a, b)
    check abs(x[0] - 1.0) < 1e-9
    check abs(x[1] - 2.0) < 1e-9

  test "retorna seq vacío si la matriz es (casi) singular":
    let a = @[@[1.0, 1.0], @[1.0, 1.0]]
    let b = @[1.0, 2.0]
    check solveLinearSystem(a, b).len == 0

suite "projectCappedSimplex":
  test "el resultado suma 1 y respeta el tope por posición":
    let v = @[0.9, 0.05, 0.05]
    let w = projectCappedSimplex(v, 0.5)
    var total = 0.0
    for x in w:
      check x >= -1e-9
      check x <= 0.5 + 1e-9
      total += x
    check abs(total - 1.0) < 1e-6

  test "con cap holgado y valores ya balanceados, se acerca a la entrada":
    let v = @[0.34, 0.33, 0.33]
    let w = projectCappedSimplex(v, 1.0)
    for i in 0 ..< v.len:
      check abs(w[i] - v[i]) < 1e-6

suite "subMatrix":
  test "extrae la submatriz N×N superior izquierda":
    let cov = @[
      @[1.0, 2.0, 3.0],
      @[4.0, 5.0, 6.0],
      @[7.0, 8.0, 9.0]
    ]
    let sub = subMatrix(cov, 2)
    check sub == @[@[1.0, 2.0], @[4.0, 5.0]]
