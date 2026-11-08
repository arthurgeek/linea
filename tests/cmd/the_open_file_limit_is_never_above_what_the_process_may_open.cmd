`process.raise_open_file_limit` answers how many files the process may open,
which is never more than the hard limit, nor, on macOS, than
`kern.maxfilesperproc`, however high the soft limit was set before.

  $ printf 'import std.io\nimport std.process\n\nfn main() -> UInt8 {\n    let limit = process.raise_open_file_limit() else |error| {\n        io.eprintln("cannot raise the open-file limit: {error}")\n        return 1\n    }\n    let _ = io.println("{limit}") else |_| {\n        return 1\n    }\n    0\n}\n' > limit.lin
  $ linea build limit.lin -o limit
  $ cap=$(ulimit -H -n); [ "$cap" = unlimited ] && cap=1048576; most=$(sysctl -n kern.maxfilesperproc 2>/dev/null) && [ "$most" -lt "$cap" ] && cap=$most; echo "$cap" > cap
  $ n=$(./limit); [ "$n" -le "$(cat cap)" ] && [ "$n" -gt 0 ] && echo "a raised soft limit is within what the process may open"
  a raised soft limit is within what the process may open
  $ n=$( (ulimit -S -n "$(cat cap)"; ./limit) ); [ "$n" -eq "$(cat cap)" ] && echo "a soft limit already at the cap is answered as it is"
  a soft limit already at the cap is answered as it is
  $ if [ "$(ulimit -H -n)" = unlimited ]; then n=$( (ulimit -S -n unlimited; ./limit) ); else n=$(./limit); fi; [ "$n" -le "$(cat cap)" ] && echo "an unlimited soft limit is answered as the cap"
  an unlimited soft limit is answered as the cap
