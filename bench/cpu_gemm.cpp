// Single-threaded, exact signed INT8 -> INT32 GEMM with reusable packed weights.
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>
#if defined(__aarch64__) || defined(__arm64__)
#include <arm_neon.h>
#define HAS_NEON 1
#else
#define HAS_NEON 0
#endif

struct Job {
    std::string name;
    int m, k, n, multiplier, shift, relu;
    std::vector<int8_t> a, b, packed, output;
    std::vector<int32_t> c, golden;
    std::vector<int8_t> expected;
};

static void pack(Job& j) {
    for (int k = 0; k < j.k; ++k)
        for (int n = 0; n < j.n; ++n) j.packed[n*j.k+k] = j.b[k*j.n+n];
}

__attribute__((noinline)) static void scalar(Job& j) {
    for (int m = 0; m < j.m; ++m) for (int n = 0; n < j.n; ++n) {
        int32_t sum = 0;
#if defined(__clang__)
#pragma clang loop vectorize(disable) interleave(disable)
#endif
        for (int k = 0; k < j.k; ++k)
            sum += int32_t(j.a[m*j.k+k]) * int32_t(j.packed[n*j.k+k]);
        j.c[m*j.n+n] = sum;
    }
}

__attribute__((noinline)) static void neon(Job& j) {
#if HAS_NEON
    for (int m = 0; m < j.m; ++m) for (int n = 0; n < j.n; ++n) {
        const auto* a = j.a.data()+m*j.k;
        const auto* b = j.packed.data()+n*j.k;
        int32x4_t sums = vdupq_n_s32(0);
        int k = 0;
        for (; k+16 <= j.k; k += 16) {
            int8x16_t av = vld1q_s8(a+k), bv = vld1q_s8(b+k);
            sums = vpadalq_s16(sums, vmull_s8(vget_low_s8(av), vget_low_s8(bv)));
            sums = vpadalq_s16(sums, vmull_s8(vget_high_s8(av), vget_high_s8(bv)));
        }
        int32_t sum = vaddvq_s32(sums);
        for (; k < j.k; ++k) sum += int32_t(a[k])*int32_t(b[k]);
        j.c[m*j.n+n] = sum;
    }
#else
    scalar(j);
#endif
}

static int8_t requantize(int32_t value, int multiplier, int shift, bool relu) {
    int64_t product = int64_t(value)*multiplier;
    // Export contract: nonnegative multiplier, shift <= 62, half away from zero.
    int64_t magnitude = product < 0 ? -product : product;
    int64_t rounded = shift ? (magnitude+(int64_t(1)<<(shift-1)))>>shift : magnitude;
    if (product < 0) rounded = -rounded;
    if (relu) rounded = std::max(int64_t(0), rounded);
    return int8_t(std::clamp(rounded, int64_t(-128), int64_t(127)));
}

static void postprocess(Job& j) {
    for (size_t i = 0; i < j.c.size(); ++i)
        j.output[i] = requantize(j.c[i], j.multiplier, j.shift, j.relu);
}

using Clock = std::chrono::steady_clock;
static volatile int64_t sink = 0;
static double batch(Job& j, void (*kernel)(Job&), bool include_pack, size_t iterations) {
    auto start = Clock::now();
    for (size_t i = 0; i < iterations; ++i) {
        if (include_pack) pack(j);
        kernel(j);
        if (include_pack) postprocess(j);
        // Compiler barrier makes every complete output observable without
        // adding a checksum reduction inside the timed kernel.
        asm volatile("" : : "r"(j.c.data()), "r"(j.output.data()) : "memory");
    }
    double ns = std::chrono::duration<double, std::nano>(Clock::now()-start).count();
    sink = std::accumulate(j.c.begin(), j.c.end(), int64_t(0));
    return ns;
}

int main(int argc, char** argv) {
  try {
    if (argc != 2 && argc != 3) throw std::runtime_error("Usage: cpu_gemm workload.txt [--check-only]");
    bool check_only = argc == 3;
    if (check_only && std::string(argv[2]) != "--check-only") throw std::runtime_error("Unknown option");
    std::ifstream input(argv[1]);
    int count = 0;
    input >> count;
    if (!input || count < 1 || count > 100) throw std::runtime_error("Invalid workload count");
    std::cout << "{\"neon_available\":" << (HAS_NEON ? "true" : "false") << ",\"results\":[";
    bool first = true;
    for (int index = 0; index < count; ++index) {
        Job j;
        input >> j.name >> j.m >> j.k >> j.n >> j.multiplier >> j.shift >> j.relu;
        if (!input || j.m < 1 || j.m > 256 || j.n < 1 || j.n > 256 || j.k < 1 || j.k > 4096 ||
            j.multiplier < 0 || j.shift < 0 || j.shift > 62)
            throw std::runtime_error("Invalid workload header");
        j.a.resize(j.m*j.k); j.b.resize(j.k*j.n); j.packed.resize(j.k*j.n);
        j.c.resize(j.m*j.n); j.golden.resize(j.c.size());
        j.output.resize(j.c.size()); j.expected.resize(j.c.size());
        for (auto* values : {&j.a, &j.b, &j.expected}) {
            // Golden INT32 values precede the final INT8 outputs in the file.
            if (values == &j.expected) for (auto& x : j.golden) input >> x;
            for (auto& x : *values) {
                int value = 0; input >> value;
                if (!input || value < -128 || value > 127) throw std::runtime_error("Invalid INT8 payload");
                x = int8_t(value);
            }
        }
        pack(j);
        for (auto kernel : {scalar, neon}) {
            kernel(j); postprocess(j);
            if (j.c != j.golden || j.output != j.expected) throw std::runtime_error("Reference mismatch: "+j.name);
        }
        for (int backend = 0; !check_only && backend < (HAS_NEON ? 2 : 1); ++backend)
          for (bool full : {false, true}) {
            auto kernel = backend ? neon : scalar;
            batch(j, kernel, full, 1000); // Warm cache and code.
            size_t iterations = 1;
            while (batch(j, kernel, full, iterations) < 20000000.0 && iterations < (1u<<25)) iterations *= 2;
            std::vector<double> samples;
            for (int r = 0; r < 9; ++r) samples.push_back(batch(j, kernel, full, iterations)/iterations);
            if (j.c != j.golden || (full && j.output != j.expected)) throw std::runtime_error("Timed output mismatch");
            std::sort(samples.begin(), samples.end());
            if (!first) std::cout << ',';
            first = false;
            std::cout << "{\"workload\":\"" << j.name << "\",\"backend\":\"" << (backend ? "neon" : "scalar")
                      << "\",\"scope\":\"" << (full ? "pack_gemm_requantize" : "gemm_prepacked")
                      << "\",\"shape_M_K_N\":[" << j.m << ',' << j.k << ',' << j.n
                      << "],\"useful_macs\":" << j.m*j.k*j.n << ",\"iterations_per_sample\":" << iterations
                      << ",\"samples\":9,\"median_ns\":" << samples[4]
                      << ",\"min_ns\":" << samples.front() << ",\"max_ns\":" << samples.back()
                      << ",\"gmac_s\":" << j.m*j.k*j.n/samples[4] << ",\"mismatches\":0}";
          }
    }
    std::cout << "],\"validated_jobs\":" << count << "}\n";
    return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
