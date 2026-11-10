
"""Tiled INT8 matrix multiplication and quantization reference."""

from reference import matmul_int8


def validate_matrix(matrix, name):
    if not isinstance(matrix, (list, tuple)) or not matrix:
        raise ValueError(f"{name} must be a nonempty matrix")

    if not isinstance(matrix[0], (list, tuple)) or not matrix[0]:
        raise ValueError(f"{name} must be 2D and nonempty")

    cols = len(matrix[0])

    if any(len(row) != cols for row in matrix):
        raise ValueError(f"{name} must be rectangular")

    if any(
        not isinstance(value, int) or not -128 <= value <= 127
        for row in matrix
        for value in row
    ):
        raise ValueError(f"{name} must contain signed INT8 values")

    return len(matrix), cols


def tiled_gemm_int8(A, B, tile=4):
    """Compute C = A @ B using 4x4 matrix multiplication tiles."""

    M, K = validate_matrix(A, "A")
    Kb, N = validate_matrix(B, "B")

    if K != Kb:
        raise ValueError("Incompatible matrix dimensions")

    if not isinstance(tile, int) or tile < 2:
        raise ValueError("Tile size must be an integer >= 2")

    C = [[0 for _ in range(N)] for _ in range(M)]

    for i in range(0, M, tile):
        for j in range(0, N, tile):
            for k in range(0, K, tile):

                A_tile = [
                    [
                        A[i+r][k+c]
                        if i+r < M and k+c < K else 0
                        for c in range(tile)
                    ]
                    for r in range(tile)
                ]

                B_tile = [
                    [
                        B[k+r][j+c]
                        if k+r < K and j+c < N else 0
                        for c in range(tile)
                    ]
                    for r in range(tile)
                ]

                partial = matmul_int8(A_tile, B_tile)

                for r in range(min(tile, M-i)):
                    for c in range(min(tile, N-j)):
                        C[i+r][j+c] += partial[r][c]

    return C


def quantize_symmetric_int8(matrix):
    """Convert floating-point inputs to signed INT8."""

    if not matrix or not matrix[0]:
        raise ValueError("Matrix cannot be empty")

    if any(len(row) != len(matrix[0]) for row in matrix):
        raise ValueError("Matrix must be rectangular")

    max_value = max(
        abs(float(value))
        for row in matrix
        for value in row
    )

    scale = max_value / 127 if max_value else 1.0

    quantized = [
        [
            max(-127, min(127, round(float(value) / scale)))
            for value in row
        ]
        for row in matrix
    ]

    return quantized, scale


def quantized_matmul(A, B, tile=4):
    """Quantize inputs, multiply, and dequantize the output."""

    A_int8, scale_A = quantize_symmetric_int8(A)
    B_int8, scale_B = quantize_symmetric_int8(B)

    C_int = tiled_gemm_int8(A_int8, B_int8, tile)

    C_float = [
        [
            value * scale_A * scale_B
            for value in row
        ]
        for row in C_int
    ]

    return C_float, C_int, (scale_A, scale_B)


if __name__ == "__main__":

    A = [
        [1, -2, 3, 4, 5],
        [0, 7, -8, 9, 1],
        [3, 4, 5, 6, 7]
    ]

    B = [
        [r-c for c in range(7)]
        for r in range(5)
    ]

    C = tiled_gemm_int8(A, B)

    print("Tiled INT8 matrix multiplication result:")

    for row in C:
        print(row)
