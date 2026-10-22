The notes CLI tool manages a collection of notes with tags, priority,
status, and structured output formatting.

  $ linea build "$LINEA_ROOT"/examples/notes -o notes

With no arguments, the tool displays its usage.

  $ ./notes
  usage: notes <command> [options]
  
  Manage personal notes
  
  commands:
    add <title>    add a new note
    list           list matching notes
    done <id>      mark a note as completed
    remove <id>    delete a note by ID
    show <id>      display single note details
    help           display this help message
  
  options:
    --json              shortcut for --format json
    --table             shortcut for --format table
    --format <value>    output format: table or json
    --config <value>    path to configuration file (default: notes.cfg)


Adding notes records titles, priorities, and tags.

  $ ./notes add "Write design doc" --tags work,spec --priority high
  added note 1: "Write design doc" [high]
  $ ./notes add "Buy groceries" --tags home,errands --priority low
  added note 2: "Buy groceries" [low]
  $ ./notes add "Review Linea PR" --tags work --priority normal
  added note 3: "Review Linea PR" [normal]

Listing notes in table format shows aligned columns.

  $ ./notes list --table
  ID  STATUS  PRIORITY  TITLE             TAGS
  1   [open]  high      Write design doc  work, spec
  2   [open]  low       Buy groceries     home, errands
  3   [open]  normal    Review Linea PR   work

Filtering by tag displays only matching notes.

  $ ./notes list --tag work --table
  ID  STATUS  PRIORITY  TITLE             TAGS
  1   [open]  high      Write design doc  work, spec
  3   [open]  normal    Review Linea PR   work

Marking a note as completed updates its status.

  $ ./notes done 1
  completed note 1: "Write design doc"

Listing notes in JSON format emits a structured array.

  $ ./notes list --json
  [{"id":1,"title":"Write design doc","status":"done","priority":"high","tags":["work","spec"]},{"id":2,"title":"Buy groceries","status":"open","priority":"low","tags":["home","errands"]},{"id":3,"title":"Review Linea PR","status":"open","priority":"normal","tags":["work"]}]

Showing details of a single note.

  $ ./notes show 1 --table
  ID:          1
  Status:      done
  Priority:    high
  Title:       Write design doc
  Tags:        work, spec

Filtering by status.

  $ ./notes list --status open --table
  ID  STATUS  PRIORITY  TITLE             TAGS
  2   [open]  low       Buy groceries     home, errands
  3   [open]  normal    Review Linea PR   work

Removing a note deletes it from the store.

  $ ./notes remove 2
  removed note 2: "Buy groceries"

Looking up a removed note fails with an honest error.

  $ ./notes show 2
  error: note 2 not found
  [1]

An unknown command reports a usage error.

  $ ./notes nonexistent
  error: unknown command 'nonexistent'
  usage: notes <command> [options]
  [2]

A subcommand displays its own usage and options when requested.

  $ ./notes add --help
  usage: notes add [options] <title>
  
  add a new note
  
  options:
    --tags <value>    comma-separated list of tags
    --priority <value>    note priority (low, normal, high)

The help command followed by a subcommand also displays that subcommand's usage.

  $ ./notes help add
  usage: notes add [options] <title>
  
  add a new note
  
  options:
    --tags <value>    comma-separated list of tags
    --priority <value>    note priority (low, normal, high)

Omitting a required positional argument reports an error.

  $ ./notes add
  error: missing required argument 'title'
  usage: notes <command> [options]
  [2]

Providing an invalid value for an option reports an error.

  $ ./notes add "Design review" --priority urgent
  error: invalid priority, expected 'low', 'normal', or 'high'
  usage: notes <command> [options]
  [2]

Passing duplicate options across root and subcommand is rejected.

  $ ./notes --config a.cfg list --config b.cfg
  error: duplicate option '--config'
  usage: notes <command> [options]
  [2]

An explicit configuration file that does not exist is rejected.

  $ ./notes list --config missing.cfg
  error: failed to read configuration file
  [1]

Conflicting format options are rejected.

  $ ./notes list --json --table
  error: conflicting output format options: cannot specify both --json and --table
  usage: notes <command> [options]
  [2]

Providing an invalid note ID reports an error.

  $ ./notes done abc
  error: invalid note ID, expected a number
  usage: notes <command> [options]
  [2]

Adding a note with an empty title is rejected.

  $ ./notes add ""
  error: note title cannot be empty
  usage: notes <command> [options]
  [2]

Extra unexpected positional arguments are rejected.

  $ ./notes add "My title" extra
  error: unexpected argument 'extra'
  usage: notes <command> [options]
  [2]

Providing an invalid status filter reports an error.

  $ ./notes list --status invalid
  error: unknown status, expected 'open', 'done', or 'all'
  usage: notes <command> [options]
  [2]


