A server that never builds a TLS configuration links none of rustls: its
binary names no rustls symbol, though the serving code could run TLS.
Building one makes the HTTPS server link it.

  $ linea build "$LINEA_ROOT"/examples/http-json-echo -o echo
  $ nm echo | grep -c ' _\{0,1\}rustls_' || true
  0
  $ linea build "$LINEA_ROOT"/examples/https-greeting -o greeting
  $ if nm greeting | grep -q ' _\{0,1\}rustls_'; then echo "the HTTPS server links rustls"; fi
  the HTTPS server links rustls
