#ifndef LINEA_OP_H
#define LINEA_OP_H

/* One operation on a descriptor, which a backend completes with one result: a
 * count, a descriptor, zero, or a negated errno. The operation's bytes stay
 * lent by the caller until the backend answers. `sleep` waits for its
 * deadline and touches no descriptor. */
enum linea_op_kind { LINEA_OP_ACCEPT, LINEA_OP_CONNECT, LINEA_OP_READ, LINEA_OP_WRITE, LINEA_OP_SLEEP };

struct linea_op {
    enum linea_op_kind kind;
    int fd;                     /* the socket; -1 for a connect not yet started */
    unsigned long at, len;      /* the bytes a read fills or a write sends */
    unsigned long address;      /* connect's packed address */
    unsigned long deadline_ns;  /* monotonic; 0 for none */
};

#endif
