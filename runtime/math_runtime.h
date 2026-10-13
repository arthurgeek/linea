#ifndef LINEA_MATH_RUNTIME_H
#define LINEA_MATH_RUNTIME_H

/* Internal binary64 ABI for checked scalar intrinsics. Each operation uses
   nearest-even arithmetic and gradual underflow, preserves the caller's
   floating environment and errno, and performs no allocation. */
double linea_math_sqrt(double value);
double linea_math_floor(double value);
double linea_math_ceil(double value);
double linea_math_trunc(double value);
double linea_math_round(double value);
double linea_math_sin(double value);
double linea_math_cos(double value);
double linea_math_ln(double value);
double linea_math_exp(double value);
double linea_math_pow(double value, double exponent);

#endif
