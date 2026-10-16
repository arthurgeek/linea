The site icon program answers one CGI request each time it runs, from the page
and the icon it embeds. `env -i` starts each run with only the variables
written here, as a web server would.

  $ linea build "$LINEA_ROOT"/examples/site-icon -o site

GET / answers the page, which names the icon in its head.

  $ env -i REQUEST_METHOD=GET PATH_INFO=/ ./site 2> /dev/null | tr -d '\r'
  Status: 200 OK
  Content-Type: text/html; charset=utf-8
  
  <!doctype html>
  <title>Lighthouse café</title>
  <link rel="icon" href="favicon.ico" type="image/x-icon">
  <p>Open every day from eight.</p>

GET /favicon.ico answers the icon's bytes as `image/x-icon`. The answer is its
46-byte head, two header lines and a blank line each ending in CRLF, and then
the 1150 bytes of `favicon.ico`, byte for byte.

  $ env -i REQUEST_METHOD=GET PATH_INFO=/favicon.ico ./site > icon 2> /dev/null
  $ head -c 60 icon | tr -d '\r' | sed -n '1,2p'
  Status: 200 OK
  Content-Type: image/x-icon
  $ wc -c < icon | tr -d ' '
  1196
  $ tail -c 1150 icon | cmp - "$LINEA_ROOT"/examples/site-icon/favicon.ico && echo the body is the icon
  the body is the icon

Any other path answers 404.

  $ env -i REQUEST_METHOD=GET PATH_INFO=/robots.txt ./site 2> /dev/null | tr -d '\r' | sed -n 1p
  Status: 404 Not Found
