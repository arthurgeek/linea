#ifndef LINEA_FOREIGN_H
#define LINEA_FOREIGN_H

/* A live user C frame forbids a fiber switch, even on the same carrier:
 * C may hold a thread-local lock across a callback into Linea. Runtime task
 * entry and release callbacks do not introduce user C frames. */
void linea_foreign_enter(void);
void linea_foreign_leave(void);
unsigned long linea_foreign_depth(void);

#endif
