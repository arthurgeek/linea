A root that cannot be loaded is reported in the format asked for, like any
other problem: one JSON object on a line, with what is wrong and why.

  $ mkdir -p app && echo '{ "kind": "plugin" }' > app/linea.json && printf 'fn main() -> UInt8 {\n    0\n}\n' > app/main.lin
  $ linea check app
  error: cannot read 'app'
    the linea.json names a kind that is not `program` or `library`
  [74]
  $ linea check --error-format=json app
  {"severity":"error","message":"cannot read 'app'","file":null,"labels":[],"help":[],"notes":["the linea.json names a kind that is not `program` or `library`"],"fixes":[]}
  [74]
  $ linea check --error-format=json missing
  {"severity":"error","message":"cannot read 'missing'","file":null,"labels":[],"help":[],"notes":["no file or directory of that name"],"fixes":[]}
  [74]
