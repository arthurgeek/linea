/* A definition without a prototype states no parameter types a caller
 * passes by: C promotes each argument, `short` to `int`. */
long long scale_by(value, factor)
short value;
long long factor;
{
    return value * factor;
}
