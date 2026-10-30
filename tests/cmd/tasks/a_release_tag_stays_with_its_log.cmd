A library `ReleaseTag` observes the `ReleaseLog` it writes when it is
released, and the log is `@unshareable`, so a tag moved into a task is
refused: its creator could read the log while the task wrote it. The tag is
internal to the standard library, so the program is a test in a copy of it,
in the module `task`, which already names `Chan` and `End`.

  $ cp -R "$LINEA_ROOT"/std copied
  $ cat > copied/task/release_probe.lin <<'EOF'
  > import std.mem
  > 
  > test fn a_tag_moved_into_a_task() {
  >     let log = mem.ReleaseLog.open(1)
  >     let tag = log.tag(1)
  >     let body = sink [sink tag] |sink me: Chan[End]| {
  >         tag.release()
  >         me.close()
  >     }
  >     let slot = prepare(body).unwrap()
  >     slot.start().close()
  >     log.release()
  > }
  > EOF
  $ linea check copied
  error[O-Cross]: a task cannot take a value observing `log`, which its creator may read too: a `mem.ReleaseLog` is not `Shareable`
   --> copied/task/release_probe.lin:6:27
    |
  6 |     let body = sink [sink tag] |sink me: Chan[End]| {
    |                           ^^^ this capture observes it
    |
    = help: reading this value may change it; move it into one task, or give the task a value that reading never changes
  [1]
