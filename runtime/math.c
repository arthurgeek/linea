#include "math_runtime.h"

#include <errno.h>
#include <fenv.h>
#include <float.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#pragma STDC FENV_ACCESS ON

_Static_assert(sizeof(double) == sizeof(uint64_t), "binary64 storage required");
_Static_assert(FLT_RADIX == 2 && DBL_MANT_DIG == 53 && DBL_MAX_EXP == 1024 &&
               DBL_MIN_EXP == -1021 && FLT_EVAL_METHOD == 0,
               "binary64 evaluation required");

#define SIGN UINT64_C(0x8000000000000000)
#define MAGNITUDE UINT64_C(0x7fffffffffffffff)
#define INFINITY_BITS UINT64_C(0x7ff0000000000000)
#define NAN_BITS UINT64_C(0x7ff8000000000000)
#define ONE_BITS UINT64_C(0x3ff0000000000000)

static uint64_t encoding(double value) {
    uint64_t result;
    memcpy(&result, &value, sizeof result);
    return result;
}

static double number(uint64_t bits) {
    double result;
    memcpy(&result, &bits, sizeof result);
    return result;
}

/* fenv saves exception masks/status and rounding. Save the architecture's
   control word too: gradual underflow must not depend on incoming FTZ/DAZ. */
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
#error "Linea math needs a verified floating environment on this target"
#endif
}

static void set_control(uint64_t setting) {
#if defined(__aarch64__)
    __asm__ volatile("msr fpcr, %0" : : "r"(setting) : "memory");
#elif defined(__x86_64__)
    unsigned narrowed = (unsigned)setting;
    __asm__ volatile("ldmxcsr %0" : : "m"(narrowed) : "memory");
#endif
}

struct math_environment {
    int error;
    uint64_t control;
    fenv_t environment;
};

static struct math_environment enter(void) {
    struct math_environment saved;
    saved.error = errno;
    saved.control = control();
    if (fegetenv(&saved.environment) != 0 || fesetenv(FE_DFL_ENV) != 0) abort();
    uint64_t current = control();
#if defined(__aarch64__)
    /* FPCR: rounding 23:22, FZ24, DN25, FZ16=19, optional FIZ0/AH1. */
    current &= ~((UINT64_C(3) << 22) | (UINT64_C(3) << 24) |
                 (UINT64_C(1) << 19) | UINT64_C(3));
#elif defined(__x86_64__)
    /* MXCSR: rounding 14:13, FTZ15, DAZ6. */
    current &= ~UINT64_C(0xe040);
#endif
    set_control(current);
    return saved;
}

static void leave(const struct math_environment *saved) {
    if (fesetenv(&saved->environment) != 0) abort();
    set_control(saved->control);
    errno = saved->error;
}

static double nearest(double (*operation)(double), double input) {
    const struct math_environment saved = enter();
    const double result = operation(input);
    leave(&saved);
    return result;
}

enum rounding { DOWN, UP, ZERO, EVEN };

/* Clear fractional significand bits and, when required, add one integral unit.
   This also preserves signed zero without doing floating-point arithmetic. */
static double integral(double input, enum rounding mode) {
    uint64_t bits = encoding(input);
    uint64_t magnitude = bits & MAGNITUDE;
    uint64_t sign = bits & SIGN;
    if (magnitude > INFINITY_BITS) return number(NAN_BITS);
    int exponent = (int)(magnitude >> 52) - 1023;
    if (exponent >= 52 || magnitude == 0) return input;
    if (exponent < 0) {
        int increment = (mode == DOWN && sign != 0) || (mode == UP && sign == 0) ||
                        (mode == EVEN && magnitude > UINT64_C(0x3fe0000000000000));
        return number(sign | (increment ? ONE_BITS : 0));
    }
    const unsigned fractional_bits = (unsigned)(52 - exponent);
    const uint64_t unit = UINT64_C(1) << fractional_bits;
    const uint64_t mask = unit - 1;
    const uint64_t fraction = magnitude & mask;
    if (fraction == 0) return input;
    magnitude &= ~mask;
    int increment = (mode == DOWN && sign != 0) || (mode == UP && sign == 0);
    if (mode == EVEN) {
        const uint64_t half = unit >> 1;
        increment = fraction > half || (fraction == half && (magnitude & unit) != 0);
    }
    if (increment) magnitude += unit;
    return number(sign | magnitude);
}

double linea_math_floor(double value) { return integral(value, DOWN); }
double linea_math_ceil(double value) { return integral(value, UP); }
double linea_math_trunc(double value) { return integral(value, ZERO); }
double linea_math_round(double value) { return integral(value, EVEN); }

static double square_root(double input) { return __builtin_sqrt(input); }

double linea_math_sqrt(double value) {
    uint64_t bits = encoding(value);
    uint64_t magnitude = bits & MAGNITUDE;
    if (magnitude > INFINITY_BITS || ((bits & SIGN) != 0 && magnitude != 0))
        return number(NAN_BITS);
    if (magnitude == 0 || magnitude == INFINITY_BITS) return value;
    return nearest(square_root, value);
}

double linea_math_sin(double value) {
    uint64_t magnitude = encoding(value) & MAGNITUDE;
    if (magnitude >= INFINITY_BITS) return number(NAN_BITS);
    if (magnitude == 0) return value;
    return nearest(sin, value);
}

double linea_math_cos(double value) {
    uint64_t magnitude = encoding(value) & MAGNITUDE;
    if (magnitude >= INFINITY_BITS) return number(NAN_BITS);
    if (magnitude == 0) return number(ONE_BITS);
    return nearest(cos, value);
}

double linea_math_ln(double value) {
    uint64_t bits = encoding(value);
    uint64_t magnitude = bits & MAGNITUDE;
    if (magnitude == 0) return number(SIGN | INFINITY_BITS);
    if ((bits & SIGN) != 0 || magnitude > INFINITY_BITS) return number(NAN_BITS);
    if (magnitude == ONE_BITS) return number(0);
    if (magnitude == INFINITY_BITS) return value;
    return nearest(log, value);
}

double linea_math_exp(double value) {
    uint64_t bits = encoding(value);
    uint64_t magnitude = bits & MAGNITUDE;
    if (magnitude > INFINITY_BITS) return number(NAN_BITS);
    if (magnitude == INFINITY_BITS) return (bits & SIGN) != 0 ? number(0) : value;
    if (magnitude == 0) return number(ONE_BITS);
    return nearest(exp, value);
}

/* An exponent is fractional, even, or odd based on its binary64 encoding.
   All representable integers with magnitude >= 2^53 are even. */
enum exponent_kind { FRACTIONAL, EVEN_INTEGER, ODD_INTEGER };

static enum exponent_kind classify_exponent(uint64_t magnitude) {
    int exponent = (int)(magnitude >> 52) - 1023;
    if (exponent < 0) return FRACTIONAL;
    if (exponent > 52) return EVEN_INTEGER;
    unsigned fraction = (unsigned)(52 - exponent);
    if ((magnitude & ((UINT64_C(1) << fraction) - 1)) != 0) return FRACTIONAL;
    return ((magnitude >> fraction) & 1) != 0 ? ODD_INTEGER : EVEN_INTEGER;
}

double linea_math_pow(double value, double exponent) {
    const uint64_t base = encoding(value);
    const uint64_t power = encoding(exponent);
    const uint64_t magnitude = base & MAGNITUDE;
    const uint64_t exponent_magnitude = power & MAGNITUDE;
    /* Identities precede NaN propagation, including signaling NaNs. */
    if (exponent_magnitude == 0 || base == ONE_BITS) return number(ONE_BITS);
    if (magnitude == ONE_BITS && exponent_magnitude == INFINITY_BITS)
        return number(ONE_BITS);
    if (magnitude > INFINITY_BITS || exponent_magnitude > INFINITY_BITS)
        return number(NAN_BITS);
    if (exponent_magnitude == INFINITY_BITS) {
        int grows = magnitude > ONE_BITS;
        if ((power & SIGN) != 0) grows = !grows;
        return number(grows ? INFINITY_BITS : 0);
    }
    const enum exponent_kind kind = classify_exponent(exponent_magnitude);
    const uint64_t sign = (base & SIGN) != 0 && kind == ODD_INTEGER ? SIGN : 0;
    if (magnitude == 0 || magnitude == INFINITY_BITS) {
        int infinite = magnitude == INFINITY_BITS;
        if ((power & SIGN) != 0) infinite = !infinite;
        return number(sign | (infinite ? INFINITY_BITS : 0));
    }
    if ((base & SIGN) != 0 && kind == FRACTIONAL) return number(NAN_BITS);
    if (magnitude == ONE_BITS) return number(sign | ONE_BITS);
    const struct math_environment saved = enter();
    const double result = pow(number(magnitude), exponent);
    leave(&saved);
    return number(encoding(result) | sign);
}
