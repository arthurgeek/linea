#ifndef LINEA_UNFORTIFIED_H
#define LINEA_UNFORTIFIED_H

/* Included first, with -include, in a fault test's build of a runtime file
 * whose system calls the test renames with -D. glibc's fortified poll and read
 * are inline wrappers that call the library's own symbols, past the renames, so
 * with _FORTIFY_SOURCE the file would make the real calls instead of the
 * scripted ones. A compiler driver may define it after every flag the build
 * passes, so it is undefined here rather than on the command line. */
#undef _FORTIFY_SOURCE

#endif
