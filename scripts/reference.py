"""Pure Python signed-INT8 model, independent of EDA/simulator packages."""


def matmul_int8(a, b):
    n = len(a)
    if n < 2 or len(b) != n or any(len(row) != n for row in a + b):
        raise ValueError("Expected two square N x N matrices, N >= 2")
    if any(not (-128 <= item <= 127) for row in a + b for item in row):
        raise ValueError("Matrix elements must be signed INT8")
    return [[sum(a[i][k] * b[k][j] for k in range(n))
             for j in range(n)] for i in range(n)]


def systolic_cycle_model(a, b):
    """Cycle-faithful mathematical schedule of the RTL datapath.

    At compute cycle t, A[i,k] and B[k,j] meet at PE(i,j)
    when t == k+i+j. This is NOT an HDL simulation.
    """
    n = len(a)
    if len(b) != n or any(len(row) != n for row in a + b):
        raise ValueError("Expected equal square matrices")
    a_delay = [[0] * n for _ in range(n)]
    b_delay = [[0] * n for _ in range(n)]
    accum = [[0] * n for _ in range(n)]
    for t in range(3*n - 2):
        new_a = [[0] * n for _ in range(n)]
        new_b = [[0] * n for _ in range(n)]
        for i in range(n):
            for j in range(n):
                a_in = (a[i][t-i] if j == 0 and 0 <= t-i < n
                        else a_delay[i][j-1] if j > 0 else 0)
                b_in = (b[t-j][j] if i == 0 and 0 <= t-j < n
                        else b_delay[i-1][j] if i > 0 else 0)
                new_a[i][j] = a_in
                new_b[i][j] = b_in
                accum[i][j] += a_in * b_in
        a_delay = new_a
        b_delay = new_b
    return accum


if __name__ == "__main__":
    a = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]]
    b = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    result = matmul_int8(a, b)
    print("Example A x I:")
    for row in result:
        print(row)
    assert result == systolic_cycle_model(a, b)
