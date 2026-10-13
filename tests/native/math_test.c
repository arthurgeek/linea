/* Test checks and environment setup execute in every optimization mode. */
#undef NDEBUG
#include <assert.h>
#include <errno.h>
#include <fenv.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#pragma STDC FENV_ACCESS ON

#include "math_runtime.h"


static uint64_t bits(double value) {
    uint64_t result;
    memcpy(&result, &value, sizeof result);
    return result;
}

static double value(uint64_t encoding) {
    double result;
    memcpy(&result, &encoding, sizeof result);
    return result;
}

static void exact(double (*operation)(double), uint64_t input, uint64_t expected) {
    uint64_t actual = bits(operation(value(input)));
    if (actual != expected) {
        fprintf(stderr, "input=%016llx expected=%016llx actual=%016llx\n",
                (unsigned long long)input, (unsigned long long)expected,
                (unsigned long long)actual);
        assert(actual == expected);
    }
}

static uint64_t control(void) {
#if defined(__aarch64__)
    uint64_t result;
    __asm__ volatile("mrs %0, fpcr" : "=r"(result));
    return result;
#elif defined(__x86_64__)
    unsigned result;
    __asm__ volatile("stmxcsr %0" : "=m"(result));
    return result;
#else
#error "native math requires a verified floating environment"
#endif
}

static void set_control(uint64_t setting) {
#if defined(__aarch64__)
    __asm__ volatile("msr fpcr, %0" : : "r"(setting));
#elif defined(__x86_64__)
    unsigned narrowed = (unsigned)setting;
    __asm__ volatile("ldmxcsr %0" : : "m"(narrowed));
#endif
}

static void special_values(void) {
    const uint64_t negative_zero = UINT64_C(0x8000000000000000);
    const uint64_t infinity = UINT64_C(0x7ff0000000000000);
    const uint64_t nan = UINT64_C(0x7ff8000000000000);
    double (*operations[])(double) = {
        linea_math_sqrt, linea_math_floor, linea_math_ceil, linea_math_trunc,
        linea_math_round, linea_math_sin, linea_math_cos, linea_math_ln,
        linea_math_exp,
    };
    for (unsigned i = 0; i < sizeof operations / sizeof operations[0]; ++i) {
        exact(operations[i], nan, nan);
        exact(operations[i], infinity | 1, nan);
    }
    exact(linea_math_sqrt, negative_zero, negative_zero);
    exact(linea_math_sqrt, infinity, infinity);
    exact(linea_math_sqrt, UINT64_C(0xbff0000000000000), nan);
    exact(linea_math_sqrt, infinity | negative_zero, nan);
    exact(linea_math_sin, negative_zero, negative_zero);
    exact(linea_math_cos, negative_zero, UINT64_C(0x3ff0000000000000));
    exact(linea_math_sin, infinity, nan);
    exact(linea_math_cos, infinity | negative_zero, nan);
    exact(linea_math_ln, negative_zero, infinity | negative_zero);
    exact(linea_math_ln, 0, infinity | negative_zero);
    exact(linea_math_ln, UINT64_C(0xbff0000000000000), nan);
    exact(linea_math_ln, UINT64_C(0x3ff0000000000000), 0);
    exact(linea_math_ln, infinity, infinity);
    exact(linea_math_exp, negative_zero, UINT64_C(0x3ff0000000000000));
    exact(linea_math_exp, infinity, infinity);
    exact(linea_math_exp, infinity | negative_zero, 0);
}

static void rounding(void) {
    const uint64_t negative_zero = UINT64_C(0x8000000000000000);
    exact(linea_math_floor, UINT64_C(0xbff4000000000000), UINT64_C(0xc000000000000000));
    exact(linea_math_ceil, UINT64_C(0xbff4000000000000), UINT64_C(0xbff0000000000000));
    exact(linea_math_trunc, UINT64_C(0xbff4000000000000), UINT64_C(0xbff0000000000000));
    exact(linea_math_round, UINT64_C(0x4004000000000000), UINT64_C(0x4000000000000000));
    exact(linea_math_round, UINT64_C(0x400c000000000000), UINT64_C(0x4010000000000000));
    exact(linea_math_round, UINT64_C(0xc004000000000000), UINT64_C(0xc000000000000000));
    exact(linea_math_round, UINT64_C(0xc00c000000000000), UINT64_C(0xc010000000000000));
    exact(linea_math_round, UINT64_C(0xbfe0000000000000), negative_zero);
    exact(linea_math_round, UINT64_C(0xbfe0000000000001), UINT64_C(0xbff0000000000000));
    exact(linea_math_ceil, negative_zero | 1, negative_zero);
    exact(linea_math_floor, negative_zero | 1, UINT64_C(0xbff0000000000000));
    exact(linea_math_trunc, negative_zero | 1, negative_zero);
    exact(linea_math_round, negative_zero | 1, negative_zero);
    exact(linea_math_ceil, 1, UINT64_C(0x3ff0000000000000));
    exact(linea_math_floor, 1, 0);
    exact(linea_math_round, UINT64_C(0x4330000000000001), UINT64_C(0x4330000000000001));
    exact(linea_math_floor, UINT64_C(0x7fefffffffffffff), UINT64_C(0x7fefffffffffffff));
}

static void environment(void) {
    const int modes[] = {FE_TONEAREST, FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO};
    fenv_t saved;
    assert(fegetenv(&saved) == 0);
    const uint64_t original_control = control();
    const uint64_t cos_one = bits(linea_math_cos(1.0));
    const uint64_t ln_two = bits(linea_math_ln(2.0));
    const uint64_t exp_one = bits(linea_math_exp(1.0));
    const uint64_t pow_half = bits(linea_math_pow(2.0, 0.5));
    for (unsigned i = 0; i < sizeof modes / sizeof modes[0]; ++i) {
        assert(fesetround(modes[i]) == 0);
        assert(feclearexcept(FE_ALL_EXCEPT) == 0);
        assert(feraiseexcept(FE_DIVBYZERO) == 0);
        uint64_t hostile = control();
#if defined(__aarch64__)
        hostile |= UINT64_C(1) << 24; /* Flush subnormal results. */
#elif defined(__x86_64__)
        /* DAZ is optional; FXSAVE reports writable MXCSR bits at byte 28. */
        _Alignas(16) unsigned char state[512];
        __asm__ volatile("fxsave %0" : "=m"(state));
        uint32_t mask;
        memcpy(&mask, state + 28, sizeof mask);
        if (mask == 0) mask = UINT32_C(0xffbf);
        hostile |= UINT64_C(0x8040) & mask; /* Available FTZ and DAZ. */
#endif
        set_control(hostile);
        /* Emulators may ignore optional controls even when their mask lists them. */
        hostile = control();
        errno = ERANGE;
        exact(linea_math_sqrt, UINT64_C(0x4000000000000000), UINT64_C(0x3ff6a09e667f3bcd));
        exact(linea_math_sqrt, 1, UINT64_C(0x1e60000000000000));
        exact(linea_math_sin, 1, 1);
        exact(linea_math_cos, 0, UINT64_C(0x3ff0000000000000));
        exact(linea_math_ln, UINT64_C(0x3ff0000000000000), 0);
        exact(linea_math_exp, 0, UINT64_C(0x3ff0000000000000));
        exact(linea_math_cos, UINT64_C(0x3ff0000000000000), cos_one);
        exact(linea_math_ln, UINT64_C(0x4000000000000000), ln_two);
        exact(linea_math_exp, UINT64_C(0x3ff0000000000000), exp_one);
        assert(bits(linea_math_pow(2.0, 0.5)) == pow_half);
        assert(bits(linea_math_pow(value(1), 1.0)) == 1);
        rounding();
        special_values();
        assert(errno == ERANGE);
        assert(fegetround() == modes[i]);
        assert(fetestexcept(FE_ALL_EXCEPT) == FE_DIVBYZERO);
        assert(control() == hostile);
    }
    assert(fesetenv(&saved) == 0);
    set_control(original_control);
}

struct math_vector {
    unsigned operation;
    uint64_t input;
    uint64_t exponent;
    uint64_t expected;
};

#include "math_vectors.h"

static uint64_t ordered(uint64_t bits) {
    const uint64_t sign = UINT64_C(0x8000000000000000);
    uint64_t magnitude = bits & ~sign;
    return (bits & sign) != 0 ? sign - magnitude : sign + magnitude;
}

/* This sample-quality threshold is not a language accuracy guarantee. */
static int reference_matches(const struct math_vector *sample, uint64_t actual) {
    const uint64_t actual_magnitude = actual & UINT64_C(0x7fffffffffffffff);
    const uint64_t expected_magnitude = sample->expected & UINT64_C(0x7fffffffffffffff);
    /* Power parity fixes the sign independently of finite magnitude accuracy. */
    if (sample->operation == 9 && actual_magnitude <= UINT64_C(0x7ff0000000000000) &&
        expected_magnitude <= UINT64_C(0x7ff0000000000000) &&
        ((actual ^ sample->expected) & UINT64_C(0x8000000000000000)) != 0)
        return 0;
    const uint64_t input_magnitude = sample->input & UINT64_C(0x7fffffffffffffff);
    const uint64_t exponent_magnitude = sample->exponent & UINT64_C(0x7fffffffffffffff);
    const int exact_power = sample->operation == 9 &&
        (input_magnitude == 0 || input_magnitude == UINT64_C(0x3ff0000000000000) ||
         input_magnitude >= UINT64_C(0x7ff0000000000000) || exponent_magnitude == 0 ||
         exponent_magnitude >= UINT64_C(0x7ff0000000000000));
    if (sample->operation < 5 || exact_power ||
        expected_magnitude > UINT64_C(0x7ff0000000000000) ||
        actual_magnitude > UINT64_C(0x7ff0000000000000))
        return actual == sample->expected;
    const uint64_t sample_tolerance = 64;
    uint64_t a = ordered(actual), e = ordered(sample->expected);
    return (a > e ? a - e : e - a) <= sample_tolerance;
}

static void reference_comparison(void) {
    const struct math_vector odd_subnormal = {
        9, UINT64_C(0x8000000000000001), UINT64_C(0x3ff0000000000000),
        UINT64_C(0x8000000000000001),
    };
    assert(reference_matches(&odd_subnormal, UINT64_C(0x8000000000000001)));
    assert(!reference_matches(&odd_subnormal, UINT64_C(0x0000000000000001)));
    assert(reference_matches(&odd_subnormal, UINT64_C(0x8000000000000000)));
    assert(!reference_matches(&odd_subnormal, UINT64_C(0x0000000000000000)));
}

static void reference_vectors(void) {
    uint64_t maximum_steps[10] = {0};
    double (*operations[])(double) = {
        linea_math_sqrt, linea_math_floor, linea_math_ceil, linea_math_trunc,
        linea_math_round, linea_math_sin, linea_math_cos, linea_math_ln,
        linea_math_exp,
    };
    for (unsigned i = 0; i < sizeof math_vectors / sizeof math_vectors[0]; ++i) {
        const struct math_vector *sample = &math_vectors[i];
        uint64_t actual = bits(sample->operation == 9
            ? linea_math_pow(value(sample->input), value(sample->exponent))
            : operations[sample->operation](value(sample->input)));
        if (!reference_matches(sample, actual)) {
            fprintf(stderr, "reference operation %u vector %u expected %016llx actual %016llx\n",
                    sample->operation, i, (unsigned long long)sample->expected,
                    (unsigned long long)actual);
            assert(reference_matches(sample, actual));
        }
        if (sample->operation >= 5 &&
            (actual & UINT64_C(0x7fffffffffffffff)) <= UINT64_C(0x7ff0000000000000) &&
            (sample->expected & UINT64_C(0x7fffffffffffffff)) <= UINT64_C(0x7ff0000000000000)) {
            uint64_t a = ordered(actual), e = ordered(sample->expected);
            uint64_t distance = a > e ? a - e : e - a;
            if (distance > maximum_steps[sample->operation])
                maximum_steps[sample->operation] = distance;
        }
    }
    printf("reference maximum steps: sin=%llu cos=%llu ln=%llu exp=%llu pow=%llu\n",
           (unsigned long long)maximum_steps[5], (unsigned long long)maximum_steps[6],
           (unsigned long long)maximum_steps[7], (unsigned long long)maximum_steps[8],
           (unsigned long long)maximum_steps[9]);
}

static void power(void) {
    const uint64_t sign = UINT64_C(0x8000000000000000);
    const uint64_t inf = UINT64_C(0x7ff0000000000000);
    const uint64_t nan = UINT64_C(0x7ff8000000000000);
    const uint64_t snan = inf | 1;
    assert(bits(linea_math_pow(value(snan), 0.0)) == UINT64_C(0x3ff0000000000000));
    assert(bits(linea_math_pow(1.0, value(snan))) == UINT64_C(0x3ff0000000000000));
    assert(bits(linea_math_pow(-1.0, value(inf))) == UINT64_C(0x3ff0000000000000));
    assert(bits(linea_math_pow(value(nan), 2.0)) == nan);
    assert(bits(linea_math_pow(-2.0, 0.5)) == nan);
    assert(linea_math_pow(-2.0, 3.0) == -8.0);
    assert(linea_math_pow(-2.0, 4.0) == 16.0);
    assert(bits(linea_math_pow(value(sign), 3.0)) == sign);
    assert(bits(linea_math_pow(value(sign), -3.0)) == (sign | inf));
    assert(bits(linea_math_pow(value(sign), 0.5)) == 0);
    assert(bits(linea_math_pow(value(sign | inf), -3.0)) == sign);
    assert(bits(linea_math_pow(value(sign | inf), 0.5)) == inf);
    assert(bits(linea_math_pow(-1.0, 0x1p53)) == UINT64_C(0x3ff0000000000000));
    assert(bits(linea_math_pow(-1.0, 0x1.fffffffffffffp52)) == UINT64_C(0xbff0000000000000));
    assert(bits(linea_math_pow(0.5, value(inf))) == 0);
    assert(bits(linea_math_pow(2.0, value(inf | sign))) == 0);
}

int main(void) {
    reference_comparison();
    special_values();
    rounding();
    environment();
    reference_vectors();
    power();
    return 0;
}
