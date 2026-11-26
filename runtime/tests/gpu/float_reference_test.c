#include "float_cases.h"
#include <assert.h>
#include <fenv.h>
#include <stdio.h>
#include <string.h>

void check_float_references(void) {
    assert(fesetround(FE_TONEAREST) == 0);
    const struct float_case *tables[] = { add_cases, subtract_cases, multiply_cases, divide_cases };
    const size_t counts[] = { sizeof(add_cases) / sizeof(add_cases[0]),
        sizeof(subtract_cases) / sizeof(subtract_cases[0]),
        sizeof(multiply_cases) / sizeof(multiply_cases[0]),
        sizeof(divide_cases) / sizeof(divide_cases[0]) };
    for (unsigned operation = 0; operation < 4; ++operation) {
        for (size_t i = 0; i < counts[operation]; ++i) {
            struct float_case test = tables[operation][i];
            float l, r;
            memcpy(&l, &test.left, 4); memcpy(&r, &test.right, 4);
            volatile float left = l, right = r;
            float value;
            switch (operation) {
                case 0: value = left + right; break;
                case 1: value = left - right; break;
                case 2: value = left * right; break;
                default: value = left / right; break;
            }
            uint32_t bits;
            memcpy(&bits, &value, 4);
            if ((bits & 0x7fffffff) > 0x7f800000) bits = 0x7fc00000;
            assert(bits == test.expected);
        }
    }
    for (size_t i = 0; i < sizeof(identity_cases) / sizeof(identity_cases[0]); ++i) {
        float value;
        memcpy(&value, &identity_cases[i], 4);
        volatile float held = value;
        value = held;
        uint32_t bits;
        memcpy(&bits, &value, 4);
        assert(bits == identity_cases[i]);
        value = -held;
        memcpy(&bits, &value, 4);
        assert(bits == (identity_cases[i] ^ 0x80000000u));
    }
    puts("Authored Float32 references match strict host binary32 arithmetic");
}
