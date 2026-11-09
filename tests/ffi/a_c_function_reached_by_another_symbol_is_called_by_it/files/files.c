/* With 64-bit file offsets asked for, C code calling `lseek` may call
 * another symbol, such as `lseek64`, and so does the declaration below. */
#define _FILE_OFFSET_BITS 64
#include <unistd.h>

long long files_offset_bits(void) { return (long long)sizeof(off_t) * 8; }
