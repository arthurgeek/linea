The library tests itself.

  $ linea test "$LINEA_ROOT"/std > out
  $ cat out
  ok    cli.cli errors display what went wrong
  ok    cli.custom_usage overrides usage output
  ok    cli.expect_end verifies all tokens consumed
  ok    cli.find_flag searches hierarchically
  ok    cli.find_option searches hierarchically
  ok    cli.flag registers boolean switches
  ok    cli.flag reports presence of flags
  ok    cli.format_help returns subcommand or root help
  ok    cli.from_slice creates a cursor from a slice
  ok    cli.get parses typed option values
  ok    cli.get_optional parses present and absent options
  ok    cli.get_positional parses typed positionals
  ok    cli.has_next reports available tokens
  ok    cli.help_command reports active help target
  ok    cli.help_for_arguments shows the command a refused parse reached
  ok    cli.help_for_arguments shows the command missing a requirement
  ok    cli.help_for_arguments shows the command that declares a refused value
  ok    cli.help_for_arguments shows the command whose argument was refused
  ok    cli.help_for_arguments shows the command whose value was refused when names repeat
  ok    cli.is_help reports help request
  ok    cli.is_supplied distinguishes user options from defaults
  ok    cli.new creates cursor from args
  ok    cli.new creates system command
  ok    cli.new_in creates a custom allocator command
  ok    cli.next advances and returns tokens
  ok    cli.option registers valued options
  ok    cli.option retrieves matched option value
  ok    cli.optional_parsed converts present option or none
  ok    cli.options_all collects repeatable options
  ok    cli.parse descends into nested subcommands
  ok    cli.parse does not take a declared switch as a value
  ok    cli.parse ends subcommand matching at a double dash
  ok    cli.parse handles optional and variadic positionals
  ok    cli.parse handles subcommand variadic positionals
  ok    cli.parse lets a declared short h name its own switch
  ok    cli.parse names a missing required option by its flag
  ok    cli.parse parses cursor into matches
  ok    cli.parse reads help only where a help subcommand is registered
  ok    cli.parse records global switches where they are declared
  ok    cli.parse refuses a value attached to a flag
  ok    cli.parse reports every refused allocation
  ok    cli.parse splits short clusters and attached short values
  ok    cli.parse takes a lone dash as a positional
  ok    cli.parse takes a negative number as a value unless a short switch spells it
  ok    cli.parse takes an attached long option value
  ok    cli.parse_args parses process arguments
  ok    cli.peek inspects token without advancing
  ok    cli.positional registers positional arguments
  ok    cli.positional retrieves positional arguments
  ok    cli.positionals_all collects variadic positionals
  ok    cli.print_help answers 0 once the help is written, and 1 when it cannot be
  ok    cli.report answers the usage status, or 1 when memory runs out
  ok    cli.require_value extracts value or fails
  ok    cli.required_option extracts value or fails
  ok    cli.required_parsed converts present option or fails
  ok    cli.required_positional extracts value or fails
  ok    cli.subcommand registers nested commands
  ok    cli.subcommand returns matched subcommand record
  ok    cli.subcommand_matches returns child matches
  ok    cli.subcommand_name returns subcommand identifier
  ok    cli.usage aligns columns by characters
  ok    cli.usage formats aligned help documentation
  ok    cli.usage lists positionals before the subcommand
  ok    cli.usage_error answers the usage status
  ok    cmp.unit values are equivalent
  ok    collections.a deleted collision bucket is reused without allocation
  ok    collections.a drain settles linear values without a release implementation
  ok    collections.a map built in an allocator holds no entries
  ok    collections.a map written without an allocator is the system map
  ok    collections.a new map holds no entries
  ok    collections.a nonempty drain is returned intact by finish
  ok    collections.collisions preserve probe chains and return the replaced key
  ok    collections.drains held in a vector release in generic code
  ok    collections.each allocation failure covers every growth step in a merge sequence
  ok    collections.each allocation failure covers every growth step in an insert sequence
  ok    collections.each allocation failure covers every growth step in an upsert sequence
  ok    collections.empty iteration and drain need no allocation
  ok    collections.empty maps and zero sized entries are supported
  ok    collections.entries borrow each live entry once
  ok    collections.finish returns a map that still holds entries
  ok    collections.first allocation failure returns a linear value
  ok    collections.get accepts a borrowed query for an owned text key
  ok    collections.growth and drain preserve borrowed values
  ok    collections.length counts live entries through replacement and removal
  ok    collections.map failures display their reason
  ok    collections.map replaces and removes complete entries
  ok    collections.maps held in a vector release in generic code
  ok    collections.merge combines a resident value and inserts a missing key
  ok    collections.merge refusal returns its inputs and hits need no allocation
  ok    collections.merge takes a combine that changes a lent count
  ok    collections.mixed operations match a dense keyed reference
  ok    collections.refused allocation recovers inputs and preserves existing entries
  ok    collections.remove accepts a borrowed query and returns the owned key
  ok    collections.settling a refused insertion releases the key and value
  ok    collections.settling an upsert mismatch releases the built entry
  ok    collections.tombstone cleanup preserves capacity when few entries remain
  ok    collections.update accepts a borrowed query for an owned text key
  ok    collections.update takes a transform that changes a lent count
  ok    collections.update transforms a present value and ignores a missing key
  ok    collections.upsert constructs only missing entries and preserves resident keys
  ok    collections.upsert factory failure and key mismatch preserve contents
  ok    collections.upsert leaves owned callback captures with the caller
  ok    collections.upsert refusal precedes factory and occupied updates need no allocation
  ok    collections.upsert refusal returns owned callback captures untouched
  ok    collections.upsert retains external values after factory scope ends
  ok    collections.upsert returns an entry when matching key and query hashes disagree
  ok    collections.upsert returns linear factory errors and mismatched entries
  ok    collections.upsert reuses a tombstone after growth is refused
  ok    collections.upsert reuses collision tombstones and accepts zero sized entries
  ok    collections.upsert takes callbacks that change lent counts
  ok    collections.upsert transfers linear values without release
  ok    convert.a generic into call uses its declared target
  ok    convert.int16 identity conversion preserves its range
  ok    convert.int16 to int32 preserves exact values and checks bounds
  ok    convert.int16 to int64 preserves exact values and checks bounds
  ok    convert.int16 to int8 preserves exact values and checks bounds
  ok    convert.int16 to uint16 preserves exact values and checks bounds
  ok    convert.int16 to uint32 preserves exact values and checks bounds
  ok    convert.int16 to uint64 preserves exact values and checks bounds
  ok    convert.int16 to uint8 preserves exact values and checks bounds
  ok    convert.int32 identity conversion preserves its range
  ok    convert.int32 to int16 preserves exact values and checks bounds
  ok    convert.int32 to int64 preserves exact values and checks bounds
  ok    convert.int32 to int8 preserves exact values and checks bounds
  ok    convert.int32 to uint16 preserves exact values and checks bounds
  ok    convert.int32 to uint32 preserves exact values and checks bounds
  ok    convert.int32 to uint64 preserves exact values and checks bounds
  ok    convert.int32 to uint8 preserves exact values and checks bounds
  ok    convert.int64 identity conversion preserves its range
  ok    convert.int64 to int16 preserves exact values and checks bounds
  ok    convert.int64 to int32 preserves exact values and checks bounds
  ok    convert.int64 to int8 preserves exact values and checks bounds
  ok    convert.int64 to uint16 preserves exact values and checks bounds
  ok    convert.int64 to uint32 preserves exact values and checks bounds
  ok    convert.int64 to uint64 preserves exact values and checks bounds
  ok    convert.int64 to uint8 preserves exact values and checks bounds
  ok    convert.int8 identity conversion preserves its range
  ok    convert.int8 to int16 preserves exact values and checks bounds
  ok    convert.int8 to int32 preserves exact values and checks bounds
  ok    convert.int8 to int64 preserves exact values and checks bounds
  ok    convert.int8 to uint16 preserves exact values and checks bounds
  ok    convert.int8 to uint32 preserves exact values and checks bounds
  ok    convert.int8 to uint64 preserves exact values and checks bounds
  ok    convert.int8 to uint8 preserves exact values and checks bounds
  ok    convert.into preserves the external owner of a transferred view
  ok    convert.into transfers a linear source to the requested destination
  ok    convert.try_into narrows integers through their try_from
  ok    convert.try_into uses the destination's try_from
  ok    convert.uint16 identity conversion preserves its range
  ok    convert.uint16 to int16 preserves exact values and checks bounds
  ok    convert.uint16 to int32 preserves exact values and checks bounds
  ok    convert.uint16 to int64 preserves exact values and checks bounds
  ok    convert.uint16 to int8 preserves exact values and checks bounds
  ok    convert.uint16 to uint32 preserves exact values and checks bounds
  ok    convert.uint16 to uint64 preserves exact values and checks bounds
  ok    convert.uint16 to uint8 preserves exact values and checks bounds
  ok    convert.uint32 identity conversion preserves its range
  ok    convert.uint32 to int16 preserves exact values and checks bounds
  ok    convert.uint32 to int32 preserves exact values and checks bounds
  ok    convert.uint32 to int64 preserves exact values and checks bounds
  ok    convert.uint32 to int8 preserves exact values and checks bounds
  ok    convert.uint32 to uint16 preserves exact values and checks bounds
  ok    convert.uint32 to uint64 preserves exact values and checks bounds
  ok    convert.uint32 to uint8 preserves exact values and checks bounds
  ok    convert.uint64 identity conversion preserves its range
  ok    convert.uint64 to int16 preserves exact values and checks bounds
  ok    convert.uint64 to int32 preserves exact values and checks bounds
  ok    convert.uint64 to int64 preserves exact values and checks bounds
  ok    convert.uint64 to int8 preserves exact values and checks bounds
  ok    convert.uint64 to uint16 preserves exact values and checks bounds
  ok    convert.uint64 to uint32 preserves exact values and checks bounds
  ok    convert.uint64 to uint8 preserves exact values and checks bounds
  ok    convert.uint8 identity conversion preserves its range
  ok    convert.uint8 to int16 preserves exact values and checks bounds
  ok    convert.uint8 to int32 preserves exact values and checks bounds
  ok    convert.uint8 to int64 preserves exact values and checks bounds
  ok    convert.uint8 to int8 preserves exact values and checks bounds
  ok    convert.uint8 to uint16 preserves exact values and checks bounds
  ok    convert.uint8 to uint32 preserves exact values and checks bounds
  ok    convert.uint8 to uint64 preserves exact values and checks bounds
  ok    default.a derived default builds each field from its default
  ok    default.bool text and option default to empty values
  ok    default.generic code starts from a default
  ok    default.numbers default to zero
  ok    env.a count says where the arguments stop
  ok    env.a variable is read by its exact name
  ok    env.an entry splits at its first equals sign
  ok    env.args start with the executable path
  ok    env.at reads an argument as text and refuses an index past the end
  ok    env.available_parallelism is positive
  ok    env.every entry has a name
  ok    env.every variable has a name and no equals sign in it
  ok    env.raw arguments preserve existing storage and missing indices
  ok    ffi.a view of nothing is lent at an address
  ok    ffi.bytes are copied from an address
  ok    ffi.bytes past a nul are copied by length
  ok    ffi.entries are read where the list holds them
  ok    ffi.errno is answered only when the call failed
  ok    ffi.lent text reads back as the original
  ok    ffi.no bytes are copied from a null pointer of no length
  ok    ffi.null text is refused rather than read
  ok    ffi.only a zero address is_null
  ok    ffi.text holding a nul is refused where the nul is
  ok    ffi.text is copied into the given allocator
  ok    ffi.text is copied with a terminator
  ok    ffi.text is lent at its first byte
  ok    ffi.the failure value selects errno
  ok    ffi.the length stops at the terminator
  ok    ffi.the value is what c returned
  ok    fmt.a default spec adds no padding
  ok    fmt.a fill of several scalars stays within the width
  ok    fmt.a nullary parse error renders its reason
  ok    fmt.a padded spec sets only the width
  ok    fmt.a spec_of the written parts names each one
  ok    fmt.a utf8 failure displays its offset and keeps its bytes
  ok    fmt.an impossible close error renders as none
  ok    fmt.boolean renderers name both values
  ok    fmt.decimal_digits count every place
  ok    fmt.each allocation failure covers every growth step of an owned rendering
  ok    fmt.fixed digits round half away from zero
  ok    fmt.float debug composes with nested derivation
  ok    fmt.float debug distinguishes adjacent values
  ok    fmt.float debug names infinities and canonical nan
  ok    fmt.float debug preserves extremes and subnormals
  ok    fmt.float debug preserves fractions and signed zero
  ok    fmt.float debug propagates the first writer failure
  ok    fmt.float debug supports complete value assertions
  ok    fmt.float debug switches notation at the documented thresholds
  ok    fmt.float display composes with interpolation and wrappers
  ok    fmt.float display keeps a decimal point on integral values
  ok    fmt.float display names infinities and nan
  ok    fmt.float display preserves extremes and subnormals
  ok    fmt.float display preserves signed zero
  ok    fmt.float display propagates the first writer failure
  ok    fmt.float display renders the shortest round trip decimal
  ok    fmt.float display uses an exponent outside the fixed range
  ok    fmt.float32 debug writes the shortest binary32 decimal
  ok    fmt.float32 display renders the shortest round trip decimal
  ok    fmt.hexadecimal_digits count every place
  ok    fmt.int16 renderers preserve decimal boundaries
  ok    fmt.int32 renderers preserve decimal boundaries
  ok    fmt.int64 renderers preserve decimal boundaries
  ok    fmt.int8 renderers preserve decimal boundaries
  ok    fmt.option display distinguishes absence and renders its payload
  ok    fmt.owned rendering allocates from the system allocator
  ok    fmt.owned rendering allocates its text from an arena
  ok    fmt.owned rendering formats interpolation values
  ok    fmt.owned rendering outlives its input owner
  ok    fmt.owned rendering settles its partial string on allocation failure
  ok    fmt.owned text renders content and encoding errors
  ok    fmt.padding splits the spare columns by alignment
  ok    fmt.power_of_ten multiplies by ten each step
  ok    fmt.renderers stop at the first writer failure
  ok    fmt.result display renders both payloads
  ok    fmt.string debug quotes escapes and preserves utf8 scalars
  ok    fmt.string display preserves empty and unicode text
  ok    fmt.text errors render the reason and byte offset
  ok    fmt.uint16 renderers preserve decimal boundaries
  ok    fmt.uint32 renderers preserve decimal boundaries
  ok    fmt.uint64 renderers preserve decimal boundaries
  ok    fmt.uint8 renderers preserve decimal boundaries
  ok    fmt.unit debug renders as empty parentheses
  ok    fmt.write_debug appends to what the writer holds
  ok    fmt.write_debug pads quoted text
  ok    fmt.write_display appends to what the writer holds
  ok    fmt.write_display ignores number parts on other values
  ok    fmt.write_display pads text by its alignment
  ok    fmt.write_float appends to what the writer holds
  ok    fmt.write_float pads signs and names non finite values
  ok    fmt.write_float rounds to its precision
  ok    fmt.write_float32 rounds the binary32 digits
  ok    fmt.write_integer appends to what the writer holds
  ok    fmt.write_integer reaches both ends of every width
  ok    fmt.write_integer right aligns and pads after the sign
  ok    fmt.write_integer writes hexadecimal digits in the case asked
  ok    fs.a child path joins with one slash
  ok    fs.a dangling link a walk follows is reported as not found
  ok    fs.a direct file write reports scratch allocation failure
  ok    fs.a direct file write takes its path scratch from an arena
  ok    fs.a directory changed during a walk is reported once, by its own path
  ok    fs.a directory swapped for a link during a walk is not followed
  ok    fs.a file close failure returns all successfully read bytes
  ok    fs.a file open failure has no partial allocation
  ok    fs.a file read failure and close failure are both retained
  ok    fs.a file read failure displays its primary and cleanup reasons
  ok    fs.a file takes a logged line
  ok    fs.a followed link back into the walk is a loop and the walk goes on
  ok    fs.a parent is held open again only when its birth time is the one recorded
  ok    fs.a symbolic link names its target and refuses an existing name
  ok    fs.a walk enters a directory whose path is longer than the system opens
  ok    fs.a walk error displays its path and its cause
  ok    fs.a walk error names the path it could not read
  ok    fs.a walk holding one open directory lists the deeper ones
  ok    fs.a walk over an arena counts every entry of the tree
  ok    fs.a walk reports a link without following it
  ok    fs.a walk reports every entry below the root once
  ok    fs.a walk runs inside a simulation
  ok    fs.a walk stops at its depth limit
  ok    fs.a word above the signed range reads as a negative number
  ok    fs.an atomic save reports scratch allocation failure
  ok    fs.an atomic save takes its scratch names from an arena
  ok    fs.an entry kind displays as a word
  ok    fs.an entry's depth counts directories from the root
  ok    fs.an entry's kind tells a file from a directory
  ok    fs.an entry's modification time is when it was written
  ok    fs.an entry's name is the last component of its path
  ok    fs.an entry's path joins the root to the names below it
  ok    fs.an entry's permissions give its owner what created it took
  ok    fs.an entry's size counts a file's bytes
  ok    fs.as_bytes returns the bytes the path was made from
  ok    fs.atomic cleanup retains primary close remove and parent errors
  ok    fs.atomic parent close failure preserves publication and skips removal
  ok    fs.atomic save preserves old contents on create conflict and replaces permissions
  ok    fs.atomic save rejects an observed nonregular destination before writing
  ok    fs.atomic save rejects special permission bits before io
  ok    fs.closing a walk part-way closes the directories it is inside
  ok    fs.create refuses an existing entry unless it replaces it
  ok    fs.creating a directory refuses an existing entry
  ok    fs.creating a directory takes its scratch from an arena
  ok    fs.creating a file makes an entry that opens
  ok    fs.creating a file reports scratch allocation failure
  ok    fs.creating a file takes its path scratch from an arena
  ok    fs.direct file writes require a policy and report the accepted extent
  ok    fs.each allocation failure covers a direct file write
  ok    fs.each allocation failure covers both scratch names of an atomic save
  ok    fs.each allocation failure covers creating a file
  ok    fs.each allocation failure covers creating a symbolic link
  ok    fs.each allocation failure covers every growth step of a file read
  ok    fs.each allocation failure of a walk is reported
  ok    fs.file close consumes a failed descriptor
  ok    fs.from_arg takes an argument as a path and refuses a missing one
  ok    fs.from_str accepts text and refuses an embedded nul
  ok    fs.is_dir holds of a directory alone
  ok    fs.is_file holds of a regular file alone
  ok    fs.is_symlink holds of a link the walk does not follow
  ok    fs.opening a file reads what was written
  ok    fs.opening a file takes its path scratch from an arena
  ok    fs.opening a path reports scratch allocation failure
  ok    fs.opening a walk of a missing directory reports it
  ok    fs.path components preserve a root parent and reject special final names
  ok    fs.path display escapes undecodable bytes without losing them
  ok    fs.path errors are independent of released input bytes
  ok    fs.paths preserve non utf8 bytes and reject nul at its offset
  ok    fs.positional file reads and writes at offsets
  ok    fs.reading a file accepts its exact byte limit
  ok    fs.reading a file allocates from the system allocator
  ok    fs.reading a file allocates its bytes from an arena
  ok    fs.reading a file retains the extra byte after a limit failure
  ok    fs.reading text decodes the file as utf8
  ok    fs.reading text names the offset of invalid utf8
  ok    fs.reading text releases the bytes of every failure and every refusal
  ok    fs.reading text reports a missing file as a read failure
  ok    fs.removing a directory refuses one that holds a file and a missing one
  ok    fs.removing a directory takes its scratch from an arena
  ok    fs.removing a file takes its name and reports a missing one
  ok    fs.saving atomically publishes the new contents
  ok    fs.settling a failed file read keeps the read and close errors
  ok    fs.skipping a directory's children leaves them out
  ok    fs.temporary names have a fixed ascii extent and a single terminator
  ok    fs.writing a file reports the bytes written
  ok    hash.boolean hashes distinguish values
  ok    hash.boolean queries match only the same value
  ok    hash.hasher finish observes without resetting or consuming the stream
  ok    hash.hasher new starts with an empty stream
  ok    hash.hasher write_byte preserves byte extremes and limb carries
  ok    hash.hasher write_u64 preserves all bytes in little endian order
  ok    hash.integer hashes accept every width and signed boundary
  ok    hash.integer queries preserve numeric type and equality
  ok    hash.long streams keep checked arithmetic in range
  ok    hash.structural hashing preserves field order and variant identity
  ok    hash.unit hashes are deterministic
  ok    hash.unit queries match
  ok    html.an attribute value cannot end its quotes
  ok    html.escape writes into any writer and appends
  ok    html.escaped text reads in an interpolation
  ok    html.every special character in a row is replaced
  ok    html.special characters are written as entities
  ok    html.special characters beside multi byte text keep the text whole
  ok    html.text that is already escaped is escaped again
  ok    html.text without special characters is written unchanged
  ok    http.a bare lf ends a line
  ok    http.a body cut short after the answer is observed as unread
  ok    http.a body holds exactly its length
  ok    http.a body is read as bytes
  ok    http.a body is text only when it is utf8
  ok    http.a body past its bound is refused and its connection closed
  ok    http.a body reader advances and stops at its boundary
  ok    http.a body replaces the one before it
  ok    http.a body shorter than its length is malformed
  ok    http.a body that is not json answers 400
  ok    http.a body that is not utf8 answers 400
  ok    http.a bound address that cannot be read closes the listener
  ok    http.a bytes response holds its body as built
  ok    http.a cgi error displays its cause
  ok    http.a cgi head request is answered_with the head alone
  ok    http.a cgi request answers each limits status one past the bound
  ok    http.a chunked response is decoded and its trailers skipped
  ok    http.a client error displays its reason
  ok    http.a client given a TLS configuration holds it until it is closed
  ok    http.a client given no TLS configuration verifies servers with the system's roots
  ok    http.a client in an allocator keeps the TLS configuration it was given
  ok    http.a client keeps the limits it was given
  ok    http.a client refuses a request past its outstanding bound
  ok    http.a client reset before accept never stops serving and the next is served
  ok    http.a client that fails the handshake is closed and serving goes on
  ok    http.a close token in a second connection header closes after the response
  ok    http.a closed port refuses the connection
  ok    http.a connection reaches a listening origin
  ok    http.a connection the server closed while idle is replaced
  ok    http.a cookie error displays its reason
  ok    http.a cookie is cleared with an empty expired value
  ok    http.a cookie is set with the attributes given
  ok    http.a cookie refused for memory leaves no header
  ok    http.a cookie that does not decode reads as none
  ok    http.a cookie value reads back as it was set
  ok    http.a dead end literal gives way to a parameter
  ok    http.a deadline ends a body the server sends too slowly
  ok    http.a decode error answers by whose mistake it is
  ok    http.a decoded path is encoded again into the target
  ok    http.a derived params reads each field by its name
  ok    http.a failed encoding answers 500
  ok    http.a failed flush answers 500
  ok    http.a failed listener close ends serving with close
  ok    http.a failed write is reported by every later write
  ok    http.a failure displays what went wrong
  ok    http.a fatal accept failure ends serving and closes the listener
  ok    http.a field reads its value or says why it cannot
  ok    http.a folded header is refused
  ok    http.a form body is read from standard input
  ok    http.a form body is read only when the content type names one
  ok    http.a form content type is named exactly
  ok    http.a form of one pair too many is refused with 413
  ok    http.a form of the most pairs is answered in the smallest arena
  ok    http.a generated id takes nothing from the request allocator
  ok    http.a get is answered_with a status header
  ok    http.a get reads a local HTTPS server's answer
  ok    http.a get reads a local server's answer
  ok    http.a handler a sequential server cannot make closes the listener
  ok    http.a handler cannot set the status as a header
  ok    http.a handler error before headers answers its status
  ok    http.a handler error is answered_with its status and message
  ok    http.a handler is given the request's read deadline
  ok    http.a handler is made as itself and a result as what it holds
  ok    http.a handler one task cannot make ends serving before anything is accepted
  ok    http.a handlers own id is replaced
  ok    http.a head is read without waiting for its body
  ok    http.a head request is answered with the head alone
  ok    http.a header error displays its reason
  ok    http.a header is found by its folded name
  ok    http.a header is read by its folded name
  ok    http.a header is spelled from its variable
  ok    http.a header_value is found by its folded name
  ok    http.a held body follows the head
  ok    http.a hexadecimal digit is its lowercase ASCII byte
  ok    http.a json body is encoded and described
  ok    http.a json body within the default limits decodes in the default arena
  ok    http.a json response holds its encoded value
  ok    http.a known length frames a persistent response
  ok    http.a linger read waits no longer than the read timeout
  ok    http.a listen_and_serve error displays its cause
  ok    http.a listening server announces the port it bound before accepting
  ok    http.a listening server answers on every task it serves with
  ok    http.a listening server makes one handler per serving task and announces once
  ok    http.a listening server whose handler cannot be made asks its factory once
  ok    http.a listening server whose second handler cannot be made announces nothing
  ok    http.a literal beats a parameter at the same position
  ok    http.a logged router logs each exchange it serves
  ok    http.a malformed header is refused
  ok    http.a malformed id the client sent is replaced
  ok    http.a malformed or unread client id is never logged
  ok    http.a malformed pair is skipped and the others survive
  ok    http.a malformed pattern is refused
  ok    http.a malformed request is answered and serving continues
  ok    http.a malformed request is refused before the handler
  ok    http.a malformed request line is refused
  ok    http.a malformed response is refused
  ok    http.a malformed status line is refused
  ok    http.a malformed url is refused
  ok    http.a match visits only nodes whose prefix matches
  ok    http.a media_type is the value without its parameters
  ok    http.a message is read through its request
  ok    http.a method mismatch gives way to a less specific path
  ok    http.a method pattern beats a methodless one
  ok    http.a method token names its method exactly
  ok    http.a missing request method answers nothing
  ok    http.a name that is not a token is refused
  ok    http.a named code finds its variant
  ok    http.a new client holds no connections
  ok    http.a new error has its status and no message
  ok    http.a new header list is empty
  ok    http.a new router answers 404
  ok    http.a newcomer at capacity closes the connection idle longest and keeps the rest
  ok    http.a param value is found by its exact name once
  ok    http.a param value parses borrows or is optional
  ok    http.a parameter beats a remainder
  ok    http.a params of its own refuses a value with a reason
  ok    http.a parent that refuses the discard buffer ends serving before accepting
  ok    http.a path ends at the query
  ok    http.a path is refused when no router matched
  ok    http.a path or domain that could end the cookie is refused
  ok    http.a path reads a struct by name or its only value
  ok    http.a path reads its fields from the path values
  ok    http.a path value decodes escapes after matching
  ok    http.a path_value is found by its exact name
  ok    http.a pattern ending in a slash matches that path alone
  ok    http.a pattern has one capture for each named segment
  ok    http.a pattern splits into its method and path
  ok    http.a percent error displays its reason
  ok    http.a plain link carries bytes both ways and closes
  ok    http.a policy of no threads is refused and closes the listener
  ok    http.a port that is taken is a listen failure
  ok    http.a prefixed cookie is cleared with secure
  ok    http.a prefixed cookie keeps the rules its prefix names
  ok    http.a query answers a refusal of a params of its own
  ok    http.a query decodes into its pairs
  ok    http.a query follows the first question mark
  ok    http.a query of one pair too many is refused with 414
  ok    http.a query of the most pairs is answered in the smallest arena
  ok    http.a query reads its fields by name
  ok    http.a query that is not percent encoded utf8 has no pairs
  ok    http.a read timeout answers 408
  ok    http.a recorded_body is what a client would read
  ok    http.a redirect changes the method and drops credentials as its status says
  ok    http.a redirect is followed to its location
  ok    http.a redirect past the limit fails
  ok    http.a redirect sets its status and location and refuses a control byte
  ok    http.a reference resolves against its base
  ok    http.a refused arena is answered 503
  ok    http.a refused body left unread does not lose the answer
  ok    http.a refused buffer answers 500 before the handler
  ok    http.a refused cookie answers 500
  ok    http.a refused document change answers 500
  ok    http.a refused head is a malformed or oversized response
  ok    http.a refused header answers 500
  ok    http.a replacement refused for memory keeps the old value
  ok    http.a request allocates in its arena
  ok    http.a request at every limit is answered in the smallest arena
  ok    http.a request at the header and body limits is answered
  ok    http.a request error answers its status
  ok    http.a request error displays its reason
  ok    http.a request error names the status that answers it
  ok    http.a request extracts a form by its field names
  ok    http.a request extracts any type that implements extract
  ok    http.a request gives its form_params only when the body is one
  ok    http.a request gives its origin from the host header
  ok    http.a request gives its path_params once a router matched it
  ok    http.a request gives its query_params decoded
  ok    http.a request head names the target host headers and framing
  ok    http.a request holds its method and url
  ok    http.a request is built as a client sends it
  ok    http.a request keeps its method token as sent
  ok    http.a request larger than the arena is answered 500
  ok    http.a request names its method
  ok    http.a request no server reads has no deadline
  ok    http.a request refuses a method or url it cannot send
  ok    http.a request sends its body to the handler
  ok    http.a request split into single bytes parses as one
  ok    http.a request that leaves no room for the response is answered 500
  ok    http.a request the handler never saw is logged without an id
  ok    http.a request whose deadline has passed is never sent
  ok    http.a request with a body parses
  ok    http.a request without a cookie header has no cookies
  ok    http.a request's headers are checked as they are added
  ok    http.a resolve error displays its reason
  ok    http.a response body is text only when it is held utf8
  ok    http.a response describes its status headers and url
  ok    http.a response framed by its length is read to its end
  ok    http.a response reads its held body and no streamed one
  ok    http.a response reads its status
  ok    http.a response settled by another client never reaches that client's pool
  ok    http.a response takes another status
  ok    http.a response without a length runs until the server closes
  ok    http.a retried accept is logged as a warning
  ok    http.a rewound request arena keeps only its first chunk
  ok    http.a route closure reads what it captured
  ok    http.a route error displays its reason
  ok    http.a route is registered once per shape and method
  ok    http.a route returning a response is registered and answers
  ok    http.a router built in an allocator answers 404
  ok    http.a router keeps its routes in an arena
  ok    http.a router written without an allocator is the system router
  ok    http.a scheme is a letter then scheme characters then a colon
  ok    http.a segment ends at the next slash
  ok    http.a segment is a literal a parameter or a remainder
  ok    http.a serve error displays its cause
  ok    http.a serving task refused its discard buffer ends serving with memory
  ok    http.a short header after a long line is answered in the smallest arena
  ok    http.a silent client times out and the next is served
  ok    http.a silent close is closed not an error
  ok    http.a silent server times the read out
  ok    http.a socket body preserves the next requests read ahead
  ok    http.a stated handler reads its state
  ok    http.a stateful function is lent the state with each count of extractors
  ok    http.a stateful router lends the state to each route
  ok    http.a stateless function is registered with each count of extractors
  ok    http.a stateless function serves a router with no state
  ok    http.a status equals the same code spelled as other
  ok    http.a status has its code
  ok    http.a status has its reason phrase
  ok    http.a status line names its code and version
  ok    http.a status response has no body
  ok    http.a stream that fails stops where it stands
  ok    http.a stream the arena cannot hold is refused
  ok    http.a streamed answer goes out as it is written
  ok    http.a streamed body follows the head
  ok    http.a streamed body is sent by its length
  ok    http.a streamed body may exceed the arena
  ok    http.a streamed body of unknown length is sent in chunks
  ok    http.a streamed body reads its request
  ok    http.a streamed body uses what its handler captured
  ok    http.a streamed response has no held body
  ok    http.a test request carries the headers added to it
  ok    http.a test request is read through its request
  ok    http.a text response holds its rendered body
  ok    http.a text response past the arena is refused
  ok    http.a truncated socket body reports a sticky bad request
  ok    http.a url displays its origin path and query
  ok    http.a url error displays its reason
  ok    http.a url names its origin path and query
  ok    http.a url's members describe it
  ok    http.a value may hold equals signs and quotes around it are dropped
  ok    http.a variable that is not utf8 is read as its bytes
  ok    http.a walk of the headers shows one id
  ok    http.a well-formed id the client sent is kept
  ok    http.a wrong method is 405 with allow
  ok    http.add_header keeps the values a name already has
  ok    http.adding a header keeps earlier values
  ok    http.ambiguous framing is rejected before the body size
  ok    http.an IPv6 host is refused as an address the client cannot reach
  ok    http.an announced server answers the connection queued for it
  ok    http.an arena below the metadata requirement is refused before serving
  ok    http.an arena too small for the limits is refused
  ok    http.an arena too small for the limits is refused with a parent
  ok    http.an authority is a host and an optional port
  ok    http.an empty body materializes without arena headroom
  ok    http.an endpoint receives the same body through a stated router
  ok    http.an error displays its status and message
  ok    http.an error is answered with its headers
  ok    http.an error is answered with its message
  ok    http.an error reads its status and message
  ok    http.an error renders its message into the arena
  ok    http.an error sends the headers it is given
  ok    http.an error whose message does not fit keeps its status
  ok    http.an escape is a percent and two capital digits
  ok    http.an exchange is logged at the level its status calls for
  ok    http.an exchange opened in an allocator takes its arena from it
  ok    http.an exchange's arena holds what its limits allow
  ok    http.an expiry before 1601 is refused
  ok    http.an extractor the arena cannot hold answers 500 and releases what was read
  ok    http.an html response holds its rendered body and content type
  ok    http.an html response past the arena is refused
  ok    http.an http variable is a header
  ok    http.an https server whose certificate names another host is refused
  ok    http.an id is kept only when it is short visible ascii
  ok    http.an identified exchange is logged with its id
  ok    http.an identified request keeps the rest of the request
  ok    http.an idle keepalive connection expires without another response
  ok    http.an io error answers 500
  ok    http.an origin displays in canonical form
  ok    http.an origin parses ipv6 with custom port
  ok    http.an origin parses normalizes default ports and folds ascii case
  ok    http.an origin refuses invalid inputs
  ok    http.an unknown version is refused
  ok    http.an upsert reason answers with its cause
  ok    http.any text is written percent encoded
  ok    http.arena arithmetic stops at the largest integer
  ok    http.bodyless statuses are recognised
  ok    http.bodyless statuses emit no content type and no body
  ok    http.buffers in an arena last for any number of requests
  ok    http.cgi reserves full body storage while http streams it
  ok    http.closing a client closes its idle connections
  ok    http.codings and connection tokens are read from comma-separated values
  ok    http.codings and options sent across several headers are read as one list
  ok    http.content length alone frames the body
  ok    http.content_length must be digits and agree
  ok    http.cookie decodes the percent encoded value
  ok    http.cookie finds a cookie by name
  ok    http.cookies walk the pairs of a cookie header in order
  ok    http.count includes every value a repeated name holds
  ok    http.cross site use requires secure
  ok    http.decoding appends the bytes escapes spell
  ok    http.discarding a response closes its connection
  ok    http.each accept retry is observed with its pause
  ok    http.each allocation failure covers every acquisition from the parent
  ok    http.each allocation failure covers every buffer identifying grows
  ok    http.each allocation failure covers every table a route grows
  ok    http.each limit answers its status at one past the bound
  ok    http.each request gets a time ordered uuid
  ok    http.each task routes path parameters through its own router
  ok    http.every connection header can request close
  ok    http.every connection is answered 503 while the parent refuses the arena
  ok    http.every exchange returns its arena to the parent
  ok    http.every shape releases its extractors last first and stops at a refusal
  ok    http.finishing a short unread body keeps its connection
  ok    http.form reads borrowed fields from the explicit body
  ok    http.get answers head
  ok    http.header compares names under ascii case folding
  ok    http.header lists held in a vector release in generic code
  ok    http.header reads the first value under ascii case folding
  ok    http.headers added one at a time are checked together
  ok    http.headers go out in order before the default content type
  ok    http.headers walk in arrival order
  ok    http.http 11 host header is strictly enforced
  ok    http.identical shapes are a duplicate
  ok    http.interim heads are skipped and a response to HEAD has no body
  ok    http.into_state returns the state and releases the handler
  ok    http.json decodes the body or names what is wrong
  ok    http.json is named by its media type
  ok    http.json reads the explicit body instead of the metadata payload
  ok    http.json refuses a body that is not utf8
  ok    http.limits beyond every arena are refused without overflowing
  ok    http.listening in the system allocator serves nothing when told to
  ok    http.materializing a body keeps its bytes for repeated readers
  ok    http.more idle connections than workers can all make another request
  ok    http.no match is 404
  ok    http.non ascii values without escapes read as sent
  ok    http.one connection is served and serve returns
  ok    http.only a timed out wait is a timeout
  ok    http.only reads the single value whatever its name
  ok    http.path values belong to the request answered
  ok    http.percent decoding reads escapes in either case and keeps plus
  ok    http.percent decoding refuses an escape that is not two hexadecimal digits
  ok    http.percent decoding refuses bytes that are not utf8
  ok    http.percent decoding reports a full allocator
  ok    http.percent decoding undoes percent encoding
  ok    http.percent encoding keeps only unreserved bytes
  ok    http.percent_encoded text reads in an interpolation
  ok    http.pipelined requests keep their order on a sequential dispatcher
  ok    http.pipelined requests keep their order with one worker
  ok    http.plaintext a TLS stream holds past a response keeps its connection out of the pool
  ok    http.redirects between http and https drop credentials across origins
  ok    http.redirects stale failures and idempotent methods are recognised
  ok    http.remove_header drops every value of a name
  ok    http.removing a header drops every value
  ok    http.removing a header leaves the others in order
  ok    http.request is_https checks forwarded headers and env
  ok    http.request is_https reads a quoted Forwarded value whole
  ok    http.resolve_url resolves with the system allocator
  ok    http.running out of memory answers 500
  ok    http.same_origin policy validates requests
  ok    http.sequential routing with path parameters
  ok    http.serve_opened defaults to concurrent worker execution
  ok    http.serving answers each client on its own task
  ok    http.serving by default answers two requests at once
  ok    http.serving in the system allocator answers a request
  ok    http.serving reports an accept failure when closing the listener fails too
  ok    http.serving that cannot begin announces nothing
  ok    http.serving with a TLS configuration answers over TLS
  ok    http.set_header replaces every value of a name
  ok    http.setting a header replaces every value
  ok    http.status returns the status the error answers with
  ok    http.streaming body limits do not reserve the body in the arena
  ok    http.text that does not decode answers 400
  ok    http.the bound address is logged as listening
  ok    http.the default arena holds every request the default limits admit
  ok    http.the default client limits bound the pool and the waits
  ok    http.the default limits bound lines headers and bodies
  ok    http.the first cookie of a repeated name wins across headers
  ok    http.the first of a repeated variable is read
  ok    http.the first refusing extractor answers the request
  ok    http.the library extractors and a type that reads itself are arguments
  ok    http.the pool keeps an https connection apart from an http one
  ok    http.the protocol the client spoke is not the programs
  ok    http.the root pattern matches the root alone
  ok    http.the shared state counts every request from every task
  ok    http.the state comes back when serving with it ends
  ok    http.the unreserved bytes are letters digits and four marks
  ok    http.transfer encoding is not implemented
  ok    http.transient accept failures are retried until a connection is served
  ok    http.two requests to one origin share a pooled connection
  ok    http.two tasks failing with owned reasons report one and release the other
  ok    http.typed cgi endpoints keep the configured form limit
  ok    http.unescaping keeps bytes that are not utf8
  ok    http.whitespace around pairs is tolerated and names match exactly
  ok    http.with_state lends its state to every request
  ok    index.a from end index displays its source notation
  ok    index.derived from end debug renders the offset
  ok    index.derived from end equality compares the offset
  ok    index.derived from end release consumes the offset
  ok    io.a borrowed raw line keeps its terminator and bytes that are not utf8
  ok    io.a borrowed raw line resumes with its retained prefix
  ok    io.a buffer refusal returns the supplied writer
  ok    io.a buffered text failure preserves accepted progress and pending bytes
  ok    io.a buffered writer holds its bytes in an arena
  ok    io.a buffered writer renders a utf8 line across short writes
  ok    io.a closed simulation leaves the system current
  ok    io.a delivery with nothing waiting for it changes nothing
  ok    io.a failed finish can be released whole
  ok    io.a failed prompt flush does not read input
  ok    io.a failed prompt preserves existing input lookahead
  ok    io.a failed prompt write does not read input
  ok    io.a full buffer accepts new bytes only after draining old bytes
  ok    io.a long sleep inside a run waits for nothing
  ok    io.a preallocated write buffer needs no further allocation
  ok    io.a preallocated writer requires nonempty storage
  ok    io.a prompt finishes short writes and keeps input lookahead
  ok    io.a prompt reads its response into an arena
  ok    io.a raw line preserves crlf without text conversion
  ok    io.a reader buffers from the system allocator
  ok    io.a refused buffer displays a failed close
  ok    io.a resumed borrowed line is held in an arena
  ok    io.a resumed borrowed raw line is held in an arena
  ok    io.a resumed owned line is allocated from an arena
  ok    io.a resumed owned raw line is allocated from an arena
  ok    io.a simulation opens with the default network or the one given
  ok    io.a simulation that has done nothing has a fixed fingerprint
  ok    io.a smaller line limit releases excess record capacity
  ok    io.a writer buffers from the system allocator
  ok    io.abandon returns the reader and drops its read ahead
  ok    io.abort drops pending bytes and returns the writer
  ok    io.advancing the world moves the virtual clock by exactly that much
  ok    io.allocation failure preserves the prefix and unconsumed lookahead
  ok    io.allocation refusal returns an untouched writer
  ok    io.an empty buffered write does not drain a full buffer
  ok    io.an incomplete line resumes with its retained prefix
  ok    io.an incomplete utf8 prefix is retained after input failure
  ok    io.an input failure can_resume an owned line
  ok    io.an oversized line retains its consumed prefix
  ok    io.buffered bytes count what was read ahead and not returned
  ok    io.buffered output retries only its unsent suffix
  ok    io.chunk reads keep read ahead for the next line
  ok    io.core.a line is the value and the ending after it
  ok    io.core.a loop requires a positive carrier count
  ok    io.core.a readiness within its holder watches the same descriptor
  ok    io.core.a share taken back was not delivered
  ok    io.core.a source names the descriptor it was made from
  ok    io.core.a task runs on the system outside a simulation
  ok    io.core.a value that prints while it is printed is printed
  ok    io.core.a write to a descriptor the process lacks reports why
  ok    io.core.an empty descriptor read does not access the descriptor
  ok    io.core.an input failure displays its position and reason
  ok    io.core.an io error converts into itself unchanged
  ok    io.core.an io error displays its numeric reason
  ok    io.core.closing a descriptor wrapper succeeds
  ok    io.core.derived io error debug renders the code
  ok    io.core.derived io error equality compares the code
  ok    io.core.derived io error release consumes the code
  ok    io.core.eprint renders a value and ignores a refused write
  ok    io.core.eprintln renders a line and ignores a refused write
  ok    io.core.gathered bytes reach the target once rendering ends
  ok    io.core.io errors preserve operation category and progress
  ok    io.core.io operations and categories display their names
  ok    io.core.print renders a value to standard output
  ok    io.core.println ends the value with a line on standard output
  ok    io.core.releasing a descriptor leaves it open
  ok    io.core.settling the last share lets the signal be shared again
  ok    io.core.standard error is descriptor two
  ok    io.core.standard input is descriptor zero
  ok    io.core.standard output is descriptor one
  ok    io.core.the system is not simulated
  ok    io.core.the system runtime_identity is zero
  ok    io.core.write failures display their kind or underlying reason
  ok    io.core.write_all preserves the prefix across short writes
  ok    io.core.write_all rejects zero progress and skips empty inputs
  ok    io.core.write_all reports progress before an underlying failure
  ok    io.draining a full buffer can fail without accepting new bytes
  ok    io.each allocation failure covers every growth step of a borrowed line
  ok    io.each allocation failure covers every growth step of a borrowed raw line
  ok    io.each allocation failure covers every growth step of a prompt
  ok    io.each allocation failure covers every growth step of a resumed borrowed line
  ok    io.each allocation failure covers every growth step of a resumed borrowed raw line
  ok    io.each allocation failure covers every growth step of a resumed owned line
  ok    io.each allocation failure covers every growth step of a resumed owned raw line
  ok    io.each allocation failure covers every growth step of a whole input
  ok    io.each allocation failure covers every growth step of an owned line
  ok    io.each allocation failure covers every growth step of an owned raw line
  ok    io.each allocation failure covers opening a reader
  ok    io.finishing after an underlying flush failure does not repeat bytes
  ok    io.inherited resolves in the task that uses it
  ok    io.invalid owned text restores the complete raw record
  ok    io.line errors display their reason
  ok    io.milliseconds too many to count saturate
  ok    io.nested buffered drain failure counts only delivered bytes
  ok    io.nested buffered flush preserves delivery progress and pending bytes
  ok    io.open returns the reader when no buffer is made
  ok    io.owned lines are allocated from an arena
  ok    io.owned lines outlive the input and reader
  ok    io.owned raw lines are allocated from an arena
  ok    io.partial discard preserves extractable bytes but prevents resume
  ok    io.pending holds the bytes not yet handed on
  ok    io.prompt errors display the failed step and its reason
  ok    io.prompt reads through a reader in an arena
  ok    io.prompt writes to standard error and reads its reader
  ok    io.raw resume preserves invalid utf8 and the terminator
  ok    io.read_exact allocates from the system allocator
  ok    io.read_exact allocates the body from its allocator
  ok    io.read_exact collects a body split across reads
  ok    io.read_exact keeps its bytes apart from the reader allocator
  ok    io.read_exact refuses past its limit before reading
  ok    io.read_exact refuses while a line read needs recovery
  ok    io.read_exact reports a reader that overruns its destination
  ok    io.read_exact reports how much arrived before the end
  ok    io.reading all allocates from the system allocator
  ok    io.reading text decodes the input as utf8
  ok    io.reading text names the offset of invalid utf8
  ok    io.reading text releases the bytes of every failure and every refusal
  ok    io.reading text reports a reader failure as a read failure
  ok    io.refused resume shrinking preserves the previous prefix
  ok    io.resuming with a smaller limit bounds the retained capacity
  ok    io.settling a failed finish keeps the write failure and a failed close
  ok    io.settling a failed read releases the partial bytes
  ok    io.settling a refused buffer closes the stream and keeps the reason
  ok    io.taking an invalid complete line does not discard the following line
  ok    io.text lines strip only their terminators
  ok    io.the default network delivers whole writes after a millisecond
  ok    io.the io inside a run is its simulation
  ok    io.three buffered layers count each delivered byte once
  ok    io.whole input accepts short reads and an exact limit
  ok    io.whole input errors display their reason
  ok    io.whole input growth refusal preserves bytes before reading more
  ok    io.whole input initial allocation refusal does not read
  ok    io.whole input is allocated from an arena
  ok    io.whole input limit failure retains the extra byte
  ok    io.whole input rejects unreported destination overflow
  ok    io.whole input zero limit distinguishes eof from one byte
  ok    io.whole_input_failure display borrows its partial bytes
  ok    io.whole_input_failure retains a partial scalar and its stream offset
  ok    iter.a double ended map yields from both ends until they meet
  ok    iter.a failed collection can be released whole
  ok    iter.a filter releases its inner iterator
  ok    iter.a filter sequence preserves selected order
  ok    iter.a filter_map releases its inner iterator
  ok    iter.a filter_map sequence preserves transformed order
  ok    iter.a map releases its inner iterator
  ok    iter.a map walks as a sequence
  ok    iter.a mutable all stops at its first rejection and keeps callback state
  ok    iter.a mutable any stops at its match and keeps callback state
  ok    iter.a mutable find stops at its match and keeps callback state
  ok    iter.a mutable find_map stops at its selection and keeps callback state
  ok    iter.a mutable fold leaves callback state with the caller
  ok    iter.a mutable for_each leaves visitor state with the caller
  ok    iter.a sequence offers every operation without iterate
  ok    iter.all short circuits and is true for empty
  ok    iter.an iterator walks as a sequence of itself
  ok    iter.any short circuits and is false for empty
  ok    iter.collect empty input succeeds with an exhausted allocator
  ok    iter.collect first push refusal returns the item and advanced linear captures
  ok    iter.collect preserves result items and returns exhausted state
  ok    iter.collect returns linear elements and captures after success or refusal
  ok    iter.copied into_inner returns the advanced iterator
  ok    iter.copied yields the values a slice views
  ok    iter.count answers how many items a sequence yields
  ok    iter.count keeps no borrowed items external owner
  ok    iter.count observes linear elements without settling them
  ok    iter.count walks what an iterator has left
  ok    iter.counted find borrows a linear iterator and resource owning callback
  ok    iter.counted find observes linear elements without settling them
  ok    iter.counted find preserves a borrowed items external owner
  ok    iter.counted find reports empty absent first and last matches
  ok    iter.counted find stops without lookahead and leaves the remainder
  ok    iter.each allocation failure covers every growth step of a collection
  ok    iter.each allocation failure covers every growth step of an extension
  ok    iter.empty map recovers protocol captures without settling them
  ok    iter.enumerate into_inner returns the advanced iterator
  ok    iter.enumerate pairs positions from zero
  ok    iter.extend appends items in source order
  ok    iter.extend at exact capacity does not allocate after exhaustion
  ok    iter.extend fills exact remaining capacity before exhaustion
  ok    iter.extend returns the rejected item and resumes without recomputing
  ok    iter.extend_owned keeps nothing of what the iterator walks
  ok    iter.extend_owned returns the refused item and keeps the prefix
  ok    iter.filter into_inner returns the advanced iterator
  ok    iter.filter recovers callback state after rejected items
  ok    iter.filter skips false items and stays exhausted
  ok    iter.filter_map changes the item type
  ok    iter.filter_map recovers callback state after exhaustion
  ok    iter.filter_map recovers its inner iterator
  ok    iter.filter_map skips consumed items
  ok    iter.filter_map that rejects every item reaches exhaustion
  ok    iter.filtering can discard affine items
  ok    iter.find returns the first matching item or none
  ok    iter.find_map stops at the first selected item
  ok    iter.fold moves one accumulator through every item
  ok    iter.fold takes a closure that changes a lent count
  ok    iter.folding text can return a borrowed item
  ok    iter.for_each consumes linear items
  ok    iter.for_each visits every linear item in order
  ok    iter.into_parts hands back a held linear item
  ok    iter.map and filter_map compose
  ok    iter.map changes the item type
  ok    iter.map filter and filter_map walk backwards over a double ended source
  ok    iter.map into_inner returns the advanced iterator
  ok    iter.map recovers the advanced source and mutated callback
  ok    iter.map transforms lazily and stays exhausted
  ok    iter.min and max pick the first least and the last greatest
  ok    iter.mutable terminals borrow read callbacks and preserve protocol captures
  ok    iter.next_if takes only an accepted item
  ok    iter.peek shows the next item without taking it
  ok    iter.peekable yields every item once in order
  ok    iter.position counts from zero
  ok    iter.position hands linear items to its predicate
  ok    iter.position lends a predicate the caller uses again
  ok    iter.reduce combines from the first item
  ok    iter.releasing a copied releases its iterator once
  ok    iter.releasing a filter releases its iterator once
  ok    iter.releasing a filter_map releases its iterator once
  ok    iter.releasing a map releases its iterator once
  ok    iter.releasing a rev releases its iterator once
  ok    iter.releasing a scan releases its iterator once
  ok    iter.releasing a skip releases its iterator once
  ok    iter.releasing a take releases its iterator once
  ok    iter.releasing a zip releases both iterators once
  ok    iter.releasing an enumerate releases its iterator once
  ok    iter.rev into_inner returns the source advanced from its end
  ok    iter.rev walks a range and a slice from the end
  ok    iter.reversing twice restores the order
  ok    iter.scan recovers its source and running state
  ok    iter.scan runs its step only for items asked for
  ok    iter.scan yields each running total
  ok    iter.settling a failed collection keeps the allocation reason
  ok    iter.skip disposes of what it passes
  ok    iter.skip ends with its source while passing
  ok    iter.skip into_inner returns the advanced iterator
  ok    iter.sum and product start from zero and one
  ok    iter.take asks for no more than it yields
  ok    iter.take ends with its source
  ok    iter.take into_inner returns the advanced iterator
  ok    iter.text adapters preserve the borrowed backing
  ok    iter.type changing adapters preserve borrowed outputs
  ok    iter.type changing adapters transfer linear outputs
  ok    iter.zip asks the second sequence nothing once the first ends
  ok    iter.zip disposes of the first item taken past the end
  ok    iter.zip recovers both sources as far as each advanced
  ok    iter.zip stops at the shorter sequence
  ok    json.a bom inside a string is preserved
  ok    json.a decode error displays its reason and the path to it
  ok    json.a decode error runs out of memory only when an allocation failed
  ok    json.a decode error written without an allocator is the system error
  ok    json.a decode_file error shows its variant and converts through question mark
  ok    json.a decoded reader counts the lines it read
  ok    json.a decoded reader hands its reader back
  ok    json.a document renders into an arena
  ok    json.a failing stream ends reading with the line it was reading
  ok    json.a file is decoded into a typed value
  ok    json.a file is decoded into an arena
  ok    json.a file is read and parsed into a document
  ok    json.a file is read into an arena
  ok    json.a file larger than the parse limits is refused at the read
  ok    json.a file that is missing or malformed names the step that failed
  ok    json.a file that is not utf8 fails to parse as invalid utf8
  ok    json.a final carriage return ends the last line as a crlf does
  ok    json.a line past the input limit is skipped and reported
  ok    json.a line that does not decode names its line and the field
  ok    json.a line that is not utf8 is skipped and reported
  ok    json.a lines error displays its line and its problem
  ok    json.a malformed line names its line and reading continues
  ok    json.a max depth holds at most the hard depth
  ok    json.a max members holds at most the hard member count
  ok    json.a max number bytes holds at most the hard token length
  ok    json.a mutation reason displays its problem
  ok    json.a parse error displays its problem and the byte it stopped at
  ok    json.a parsed number keeps its token in an arena
  ok    json.a writer error converts into an encoding failure
  ok    json.a zero input limit reports every line that is not blank
  ok    json.abandon returns the reader past what was read ahead
  ok    json.an empty file fails to parse and a directory fails to read
  ok    json.an integer number keeps its token in an arena
  ok    json.an object decoder records its fields in an arena
  ok    json.array allocation refusal preserves the incoming value
  ok    json.array makes an empty array in the system allocator
  ok    json.array makes an empty array without allocating
  ok    json.array_height tracks repeated maxima and absent removal
  ok    json.arrays transfer children and preserve order after removal
  ok    json.as_bool reads only a boolean
  ok    json.as_int64 checks kind and range
  ok    json.as_int64 reads a number value and refuses other kinds
  ok    json.as_str reads only a string
  ok    json.as_uint64 checks kind sign and range
  ok    json.as_uint64 reads a number value and refuses other kinds
  ok    json.at finds an element by position
  ok    json.at_field copies the name into the system allocator
  ok    json.at_index records an array position
  ok    json.attachment enforces depth and recomputes height after removal
  ok    json.begin_object opens an object that takes members
  ok    json.boolean makes a boolean value in the system allocator
  ok    json.boolean makes a boolean value without allocating
  ok    json.boolean writes true or false
  ok    json.configured limits accept the boundary and reject the next value
  ok    json.crlf and a missing final newline end lines
  ok    json.decode allocates from the system allocator
  ok    json.decode allocates the record from an arena
  ok    json.decode error allocation failure releases owned path segments
  ok    json.decode error path allocation failure settles the partial error
  ok    json.decode error paths own names and expose root first segments
  ok    json.decode errors held in a vector release in generic code
  ok    json.decode parses then decodes and reports a parse error
  ok    json.decoded string owns storage and settles allocation failure
  ok    json.decoded yields typed values
  ok    json.decoding a file keeps read and decode failures distinct
  ok    json.decoding a file that is not utf8 fails to parse
  ok    json.derived record encoding uses field order and null option values
  ok    json.derived records own text and apply optional field policy
  ok    json.document output escapes every control byte
  ok    json.document output preserves number tokens and escapes text
  ok    json.document round trips preserve structure independent of member order
  ok    json.duplicate decoded names are refused before their values
  ok    json.each allocation failure covers every segment of a field path
  ok    json.each allocation failure is reported or read
  ok    json.elements borrow only an arrays children
  ok    json.encoded lines read back as the values written
  ok    json.encoder bounds nested containers at 128
  ok    json.encoding errors preserve writer details in debug output
  ok    json.end_array closes only an array
  ok    json.end_object refuses an object waiting for a value
  ok    json.failure starts a value error at the root
  ok    json.failure starts a value error in the system allocator
  ok    json.field takes the missing value of an absent member
  ok    json.finish refuses a member no field read
  ok    json.float observations are independent of the document
  ok    json.float64 writes the shortest digits and refuses nan
  ok    json.from_int keeps the token in the system allocator
  ok    json.from_int makes a number value
  ok    json.from_int makes a number value in the system allocator
  ok    json.from_int uses the exact decimal text
  ok    json.from_uint keeps the token in the system allocator
  ok    json.from_uint makes a number value
  ok    json.from_uint makes a number value in the system allocator
  ok    json.from_uint uses the exact decimal text
  ok    json.from_value decodes a document held in an arena into system values
  ok    json.from_value decodes a parsed value and leaves it with the caller
  ok    json.from_value decodes a value into an arena
  ok    json.from_value decodes into the system allocator
  ok    json.get finds a member by name without retaining the query
  ok    json.height tracks repeated maxima and replacement of the last tall child
  ok    json.incomplete documents release completed siblings and report eof
  ok    json.insert replaces a member and returns the previous value
  ok    json.integer writes decimal digits
  ok    json.json mutation allocation refusals preserve destinations and return subtrees
  ok    json.json parser disposes completed siblings and partial tokens on invalid input
  ok    json.json parser disposes every allocation on success and each refusal
  ok    json.json render disposes partial output on each allocation refusal
  ok    json.json replacement and removal transfer owners without allocation
  ok    json.json typed decode disposes records and error paths on each refusal
  ok    json.json typed map settles owned keys values and collisions on each refusal
  ok    json.key is refused outside an object
  ok    json.kind names every kind of value
  ok    json.line_number counts blank lines
  ok    json.malformed documents report the first unusable byte
  ok    json.member limit refuses new names and allows replacement
  ok    json.members walk only an objects entries
  ok    json.nested codecs emit one value and preserve the caller's container
  ok    json.null makes a null value in the system allocator
  ok    json.null makes a null value without allocating
  ok    json.null writes one null value
  ok    json.number allocation failure is a value
  ok    json.number constructor enforces the hard token limit
  ok    json.number float access rounds without changing the token
  ok    json.number keeps its spelling in the system allocator
  ok    json.number owns its token independently of input
  ok    json.number parse keeps the token in the system allocator
  ok    json.number preserves validated decimal spelling
  ok    json.number requires one complete json token
  ok    json.number scanning classifies every prefix of a number
  ok    json.number scanning stops before delimiters and reports absolute offsets
  ok    json.number values keep their spelling and refuse other text
  ok    json.number_text reads only a number
  ok    json.object decoder copies queries and decoded results outlive document
  ok    json.object makes an empty object in the system allocator
  ok    json.object makes an empty object without allocating
  ok    json.only an allocation failure is running out of memory
  ok    json.open accepts only an object
  ok    json.open reads a document from each line
  ok    json.open reads an object with the system allocator
  ok    json.open_in hands the reader back when no buffer is made
  ok    json.open_in holds each line and document in an arena
  ok    json.optional decodes a present member and answers none for an absent one
  ok    json.parse allocates the document from the system allocator
  ok    json.parse_bytes allocates the document from the system allocator
  ok    json.parsed bytes are allocated from an arena
  ok    json.parsed documents own text and preserve number tokens
  ok    json.parser accepts 128 containers and refuses the next opener
  ok    json.parsing nested documents handles bounded allocation refusal
  ok    json.path_length counts every segment to the failing value
  ok    json.preflight precedes utf8 and utf8 precedes grammar
  ok    json.reason says why a value did not decode
  ok    json.refused mutations return the complete incoming owner
  ok    json.releasing a recursive document settles both allocator owners
  ok    json.remove_member returns the stored value and forgets its name
  ok    json.render allocates the text from the system allocator
  ok    json.render allocation failure leaves the document usable
  ok    json.rendered text is independent of the document
  ok    json.replacement reuses the stored key with an exhausted allocator
  ok    json.required refuses an absent member even for an option
  ok    json.segment reads the path root first
  ok    json.settling a refused member releases it and keeps the reason
  ok    json.string copies its text into the system allocator
  ok    json.string escape errors keep absolute offsets after input release
  ok    json.string limits count decoded bytes and allow empty text
  ok    json.string scanning decodes all short escapes
  ok    json.string scanning preserves unicode and decodes surrogate pairs
  ok    json.string scanning rejects bad escapes surrogates and truncated prefixes
  ok    json.string scanning rejects raw controls and accepts their unicode escapes
  ok    json.string values own their text
  ok    json.string writes quoted escaped text
  ok    json.swallowed child and writer failures poison the encoder
  ok    json.text returns the token as it was written
  ok    json.the default limits bound input depth and nodes
  ok    json.typed collections keep owned values and nested error paths
  ok    json.typed encoding preserves borrowed writer errors
  ok    json.typed encoding preserves finite floats and refuses nonfinite values
  ok    json.typed encoding preserves scalars text and container order
  ok    json.typed encoding rejects invalid custom codec sequences
  ok    json.typed maps refuse names that decode to the same key
  ok    json.typed records apply missing policy and settle early owners
  ok    json.typed scalars check every integer width and numeric kind
  ok    json.unicode escapes cover each utf8 width boundary
  ok    json.value writes one value through its own codec
  ok    json.write preserves borrowed writer failures and the document
  ok    json.write_line writes one document on one line
  ok    json.wrong kind insertion returns the complete subtree
  ok    json.zero limits are restrictions and container depth excludes scalars
  ok    log.a descriptor sink reports a refused line
  ok    log.a field is written as its key and value
  ok    log.a field observes a value its caller keeps
  ok    log.a level displays in capitals
  ok    log.a line below the minimum level is not written
  ok    log.a line is built in an arena
  ok    log.a line starts with the time it was written
  ok    log.a line the allocator refuses is reported and not written
  ok    log.a line the sink refuses is reported
  ok    log.a logger builds its lines in the allocator it was given
  ok    log.a logger is enabled at its minimum level and above
  ok    log.a logger to standard error builds lines in the allocator it was given
  ok    log.a logger to standard error copies freely
  ok    log.a logger to standard error uses the system allocator
  ok    log.a logger writes to the sink it was given
  ok    log.a message is quoted only when it could be read as a field
  ok    log.a value is quoted when it could not be read back otherwise
  ok    log.a value is rendered once and written as rendered
  ok    log.a value is written through display
  ok    log.added fields are written in order
  ok    log.and adds a second field after the first
  ok    log.debug writes a debug line
  ok    log.each allocation failure covers every growth step of a line
  ok    log.error writes an error line
  ok    log.info writes an info line
  ok    log.warn writes a warn line
  ok    mem.a buffer arrives zeroed and holds what it is given
  ok    mem.a buffer byte view covers the requested extent
  ok    mem.a buffer disposes through its stored allocator
  ok    mem.a buffer from a later chunk is disposed into its arena
  ok    mem.a byte store reaches one byte
  ok    mem.a byte vector reads from a reader into its own buffer
  ok    mem.a carried field keeps a lend until its holders last use
  ok    mem.a carried type that can carry nothing is owned
  ok    mem.a chunked arena hands out exactly its size less the cursor
  ok    mem.a client and a server session carry a handshake between them
  ok    mem.a client session starts handshaking
  ok    mem.a closure calls what it captured
  ok    mem.a closure keeps its captures in an arena
  ok    mem.a closure opened in the system allocator calls what it captured
  ok    mem.a configuration from text that is not PEM is refused
  ok    mem.a directory stream lists what a directory holds
  ok    mem.a directory stream opens a directory inside the one it reads
  ok    mem.a directory's lasting identity is the same through two streams
  ok    mem.a dotted name resolves to itself and an empty one to nothing
  ok    mem.a drain stopped early is returned by finish and resumes
  ok    mem.a foreign_address is where the bytes are
  ok    mem.a foreign_byte is read at its offset
  ok    mem.a foreign_word is read at its offset
  ok    mem.a handle hands out buffers the allocator counts
  ok    mem.a handle written without a parent is a handle over the system
  ok    mem.a kept value comes back as it went in
  ok    mem.a lambda that captures nothing allocates nothing
  ok    mem.a new release log holds no releases
  ok    mem.a parent refusing a chunk refuses the reservation that needed it
  ok    mem.a read walk lends each viewed element
  ok    mem.a refused allocation releases the callback
  ok    mem.a refused allocation reports what it was for and answers status 1
  ok    mem.a refused overflowing reservation keeps the cursor
  ok    mem.a release log holds its codes in release order
  ok    mem.a reservation larger than the first chunk is handed out whole
  ok    mem.a rewound arena hands out its slab again zeroed
  ok    mem.a shared log allocator is shared by tasks that allocate at once
  ok    mem.a shared log counts a dropped arena buffer as outstanding
  ok    mem.a shared log counts only successful acquisitions
  ok    mem.a shared log counts refused attempts too
  ok    mem.a shared log counts the buffers given back
  ok    mem.a shared log counts what is acquired and not disposed
  ok    mem.a shared log is not all_disposed while an allocation is live
  ok    mem.a shared log refuses a later attempt through live handles
  ok    mem.a shared log refuses every acquisition of the named size from one on
  ok    mem.a shared log refuses every attempt from the one named
  ok    mem.a shared log refuses one acquisition of the named size
  ok    mem.a shared log refuses the acquisition open names
  ok    mem.a shared log remembers the most bytes live at once
  ok    mem.a shared test allocator over an arena is released with a dropped buffer
  ok    mem.a slice debugs as its elements in brackets
  ok    mem.a slice observes only its initialized extent
  ok    mem.a state holds the bits it was made of
  ok    mem.a system drain stopped early is returned by finish with its storage
  ok    mem.a tag records its code when it is released
  ok    mem.a terminated copy ends with one zero byte
  ok    mem.a test allocator counts past a thousand acquisitions
  ok    mem.a test allocator over an arena is released with a dropped buffer
  ok    mem.a vec written without an allocator is the system vec
  ok    mem.a walk lent a drain may stop early and leave the rest with its owner
  ok    mem.acquired counts only successful acquisitions
  ok    mem.address.nowhere is the address of no bytes
  ok    mem.all_disposed is false while an allocation is live
  ok    mem.allocating again preserves a live buffer view
  ok    mem.an address at a number names the bytes there
  ok    mem.an arena backs another arena
  ok    mem.an arena hands out storage and gives the slab back
  ok    mem.an arena over an arena is rewound in place
  ok    mem.an arena over an arena takes its whole size from it
  ok    mem.an arena refuses what it cannot hold
  ok    mem.an arena smaller than its cursor rewinds to nothing
  ok    mem.an arena the backing refused refuses everything
  ok    mem.an empty buffer is allocated rather than refused
  ok    mem.an empty slice accepts its empty subspan
  ok    mem.an exchange returns the value it replaces
  ok    mem.an inconsistent comparison leaves a permutation
  ok    mem.arena vector discard does not invoke optional element release
  ok    mem.as_slice views only the live elements
  ok    mem.attempts count refused acquisitions too
  ok    mem.closing a descriptor the process lacks reports an error
  ok    mem.derived oom equality compares its case
  ok    mem.derived oom release consumes its case
  ok    mem.derived oom rendering names its case
  ok    mem.derived system allocator debug renders its case
  ok    mem.derived system allocator equality compares its case
  ok    mem.disposed counts the buffers given back
  ok    mem.each allocation failure covers every growth step in a push sequence
  ok    mem.each allocation failure covers every growth step in an append_slice sequence
  ok    mem.empty fd requests do not access a descriptor
  ok    mem.empty pipe requests do not access a descriptor
  ok    mem.equal slices hash equally
  ok    mem.fail_at refuses a later acquisition through live handles
  ok    mem.fd reads reject a count past the remaining buffer
  ok    mem.fd reads reject an offset past the buffer
  ok    mem.filled repeats a value in the system allocator
  ok    mem.floats sort with a comparison that places nan
  ok    mem.from_fn builds a vector in the system allocator
  ok    mem.from_fn lends an initializer the caller keeps
  ok    mem.from_fn takes an initializer that changes a lent count
  ok    mem.get borrows an element or answers none past the end
  ok    mem.length counts the viewed elements
  ok    mem.live_bytes counts what is acquired and not disposed
  ok    mem.load traps at a misaligned offset
  ok    mem.load traps past the end
  ok    mem.load_byte traps past the end
  ok    mem.one handle serves more than one allocation
  ok    mem.open policies have the runtime's codes
  ok    mem.open records into the backing the caller chooses
  ok    mem.open refuses the acquisition it names
  ok    mem.opening a missing directory answers its errno
  ok    mem.outstanding counts a dropped arena buffer until the end
  ok    mem.peak_bytes remembers the most bytes live at once
  ok    mem.pipe reads reject a range past the buffer
  ok    mem.random_words differ between reads
  ok    mem.releasing a closure returns its bytes
  ok    mem.releasing a drain stopped early releases only what remains
  ok    mem.releasing a slice leaves its storage owned
  ok    mem.report answers status 1
  ok    mem.rewinding gives back every chunk but the first
  ok    mem.settling a refused push releases the value and keeps the reason
  ok    mem.slice iteration collects observations and transformed values
  ok    mem.slice iteration early exit leaves the source mutable
  ok    mem.slice iteration from both ends yields each element once
  ok    mem.slice iteration handles empty and single element subspans
  ok    mem.slice iteration observes affine and linear elements without copying or settling
  ok    mem.slice iteration retains order and independent observations
  ok    mem.slices equal by their elements
  ok    mem.slices order by their first different element
  ok    mem.socket reads reject a range past the buffer
  ok    mem.sort keeps sorted input and reverses descending input
  ok    mem.sort orders integers ascending
  ok    mem.sort orders text and derived orders
  ok    mem.sort_by keeps equal keys in order at every length up to seventy
  ok    mem.sort_by makes n log n comparisons
  ok    mem.sort_by reorders linear elements
  ok    mem.sort_by sorts a large random vector stably
  ok    mem.sorting allocates nothing
  ok    mem.sorting an empty or one element vector compares nothing
  ok    mem.split lends the elements on each side of the split
  ok    mem.store traps at a misaligned offset
  ok    mem.store traps past the end
  ok    mem.store_byte traps past the end
  ok    mem.take leaves the default behind
  ok    mem.typed slots move an aggregate to independent storage
  ok    mem.vec append_slice copies the elements after the live ones
  ok    mem.vec append_slice in an arena keeps nothing of its source
  ok    mem.vec append_slice keeps every element across growth
  ok    mem.vec append_slice of nothing changes nothing and allocates nothing
  ok    mem.vec byte buffer transfer rejects a prefix past the buffer
  ok    mem.vec byte buffer transfers preserve an empty prefix and an empty buffer
  ok    mem.vec byte buffer transfers preserve storage without allocator headroom
  ok    mem.vec clear releases every element and keeps capacity
  ok    mem.vec constructors reserve exact capacity once
  ok    mem.vec drain hands over linear elements first to last
  ok    mem.vec drain of an empty vector hands over nothing
  ok    mem.vec drain walk abandoned early leaves discardable elements
  ok    mem.vec drain walks arena elements with for
  ok    mem.vec empty and refused constructors do not initialize
  ok    mem.vec empty construction and disposal do not call the allocator
  ok    mem.vec filled initializes independent elements
  ok    mem.vec filled preserves the observations in its seed
  ok    mem.vec finish disposes an empty vector
  ok    mem.vec finish returns nonempty ownership
  ok    mem.vec first insertion refusal keeps empty storage and the item
  ok    mem.vec from_fn builds its elements in an arena
  ok    mem.vec from_fn constructs linear elements
  ok    mem.vec from_fn lends an initializer that builds in an arena
  ok    mem.vec from_fn preserves callbacks on empty overflow and refusal
  ok    mem.vec from_fn preserves records borrowed from its callback
  ok    mem.vec from_fn preserves state and constructs linear elements
  ok    mem.vec growth preserves floats booleans and unit elements
  ok    mem.vec length tracks insertions and removals
  ok    mem.vec new starts empty in the system allocator
  ok    mem.vec new_in starts empty
  ok    mem.vec pop hands over linear elements from an arena
  ok    mem.vec pop takes elements last first and keeps capacity
  ok    mem.vec push failure returns ownership without changing elements
  ok    mem.vec push preserves values across growth
  ok    mem.vec release disposes backing once after its elements
  ok    mem.vec release excludes a removed element
  ok    mem.vec release visits each element once in reverse order
  ok    mem.vec remove closes the gap and preserves absent indices
  ok    mem.vec reserved insertions do not allocate
  ok    mem.vec split lends disjoint halves
  ok    mem.vec truncate releases the tail last first and keeps capacity
  ok    mem.vec unallocated byte storage has no buffer
  ok    mem.windows yield each run of consecutive elements
  ok    net.a backlog holds one to 4096 connections
  ok    net.a borrowed connection writer keeps the connection open
  ok    net.a client reports the listener as its peer
  ok    net.a client that holds its task holds up no other
  ok    net.a connect whose deadline has passed times out
  ok    net.a connect whose deadline is never waits for the handshake
  ok    net.a connect whose handshake ends at its deadline connects
  ok    net.a connection close reports success
  ok    net.a connection reaches its own listener
  ok    net.a connection reports its read deadline
  ok    net.a connection reset before accept is reported as reset and the next is accepted
  ok    net.a connection to a closed port is refused
  ok    net.a deadline ends a write the peer never reads
  ok    net.a deadline ends reads that each arrive in time
  ok    net.a deadline of never leaves reads unbounded
  ok    net.a failed listener close ends serving with close
  ok    net.a fatal accept failure ends serving and closes the listener
  ok    net.a limit is reached at its count and none is never reached
  ok    net.a listener accepts through the acceptor trait
  ok    net.a listener close consumes a failed descriptor
  ok    net.a listener close reports success
  ok    net.a listener reports the port it was given
  ok    net.a net error displays its reason
  ok    net.a read deadline leaves writes unbounded
  ok    net.a read whose bytes arrive at its deadline reads them
  ok    net.a read_by is the nearest of the read bound, the deadline and the caller's
  ok    net.a reset connection is reset at its peer
  ok    net.a reset or exhausted accept is retried
  ok    net.a scripted listener fails as scripted then accepts and reports its close failure
  ok    net.a second listener on one address is in use
  ok    net.a serve error displays its cause
  ok    net.a shut down writer ends the peer input
  ok    net.a silent peer times out the read
  ok    net.a simulated connection kept past its simulation closes
  ok    net.a write times out when the peer reads nothing
  ok    net.an accept whose connection is ready at its deadline takes it
  ok    net.an accept whose deadline has passed times out with no client
  ok    net.an accept whose deadline is never waits as accept does
  ok    net.an accept_attempt retries failures with a growing pause that a connection resets
  ok    net.an address debugs its parts
  ok    net.an address displays as dotted octets and a port
  ok    net.an address keeps the parts it was built from
  ok    net.an address parses and prints the same
  ok    net.an address refuses what is not ipv4
  ok    net.an address survives the runtime packing
  ok    net.an operation bound of zero or too far ahead is never
  ok    net.any names every interface
  ok    net.finish closes the listener and reports the accept failure before the close failure
  ok    net.listen queues the default backlog or the one given
  ok    net.loopback names this host
  ok    net.next asks the listener nothing until a retry has waited its pause
  ok    net.on_tasks answers what every task answered
  ok    net.only a timed_out accept is timed_out
  ok    net.resolving a dotted address or localhost needs no network
  ok    net.serve runs the handler once for each connection and returns
  ok    net.serve_workers handles connections concurrently
  ok    net.serve_workers sequential policy
  ok    net.serving no connections returns at once and closes the listener
  ok    net.set_timeouts keeps the deadline
  ok    net.tasks that cannot be made do not hold up the one that runs
  ok    net.the accept_backoff doubles from 5 ms to one second
  ok    net.the handler reads from each connection and names its peer
  ok    net.transient accept failures are retried until a connection is served
  ok    net.zero workers closes the listener and returns
  ok    num.both float types add from zero and multiply from one
  ok    num.every integer type adds from zero and multiplies from one
  ok    option.a mutable and_then calls its transform only for some
  ok    option.a mutable fallback runs only for none
  ok    option.a mutable map calls its transform only for some
  ok    option.an eager option fallback accepts affine values
  ok    option.and_then takes a transform that changes a lent count
  ok    option.and_then transforms some and preserves none
  ok    option.derived option debug renders its case and payload
  ok    option.derived option equality compares cases and payloads
  ok    option.derived option release releases only a present payload
  ok    option.is_some answers whether a value is present
  ok    option.map preserves a record borrowed from its callback
  ok    option.map takes a transform that changes a lent count
  ok    option.map transforms some and preserves none
  ok    option.mutable option combinator preserves its caller's protocol capture
  ok    option.option combinators preserve borrowed payloads
  ok    option.tag predicates preserve affine payloads
  ok    option.tag predicates preserve linear payloads
  ok    option.unwrap returns some
  ok    option.unwrap traps on none
  ok    option.unwrap_or returns some or the eager fallback
  ok    option.unwrap_or_else calls only for none
  ok    option.unwrap_or_else takes a fallback that changes a lent count
  ok    process.a block's strings are walked in order
  ok    process.a child blocked on a full pipe ends when it is waited for
  ok    process.a child has a positive process ID
  ok    process.a child starts in its directory
  ok    process.a cleared environment holds only what was set
  ok    process.a command keeps its text in its allocator
  ok    process.a fiber captures a child's output and waits for it on a loop
  ok    process.a killed child is reported killed by signal nine
  ok    process.a new command runs its program
  ok    process.a null error stream discards what the child reports
  ok    process.a null input reads as empty
  ok    process.a null output discards what the child writes
  ok    process.a process error displays its reason
  ok    process.a program that is not there is not found
  ok    process.a removed variable does not reach the child
  ok    process.a runtime answer keeps its operation and category
  ok    process.a set variable reaches the child
  ok    process.a signal is there only for a killed child
  ok    process.a status reports how the child ended
  ok    process.a variable name holding an equals sign is refused
  ok    process.an argument holding a NUL byte is refused
  ok    process.an exit code is there only for an exit
  ok    process.an exit status displays how the child ended
  ok    process.arguments reach the child in order
  ok    process.closing a pipe reader consumes it and reports a bad descriptor
  ok    process.closing a pipe writer consumes it and reports a bad descriptor
  ok    process.each allocation failure covers capturing output
  ok    process.each allocation failure covers starting a child
  ok    process.input written to a child comes back through its output
  ok    process.megabytes on both streams are read without stalling
  ok    process.only an exit with code zero is a success
  ok    process.output captures both streams and the status
  ok    process.output too long kills and reaps the child
  ok    process.raising the open file limit twice answers the same limit
  ok    process.standard error is read apart from standard output
  ok    process.standard output is there only when it was piped
  ok    process.streams have the runtime's codes
  ok    process.waiting reports the exit code
  ok    process.waiting with output reads both streams
  ok    range.a descending inclusive range yields the end it stops at
  ok    range.a descending range yields its values downwards
  ok    range.a range at the ends of its type walks back without stepping past them
  ok    range.a range displays its source notation
  ok    range.a range ending at the largest value finishes without stepping past it
  ok    range.a range ending at the smallest value finishes without stepping past it
  ok    range.a range walked from both ends yields each value once
  ok    range.a range walked from the back yields its values in reverse
  ok    range.a range walks as the sequence it is
  ok    range.a range yields its values in order and then nothing
  ok    range.an empty range yields nothing
  ok    range.an inclusive range yields the end an exclusive one stops before
  ok    range.derived range debug renders every field
  ok    range.derived range equality compares every field
  ok    range.derived range release releases its endpoints in reverse field order
  ok    release.discarding a copyable value runs nothing
  ok    release.never release is available to an uninhabited payload
  ok    release.releasing an observation leaves its owner available
  ok    release.str release preserves shared literal storage
  ok    result.a mutable and_then calls its transform only for ok
  ok    result.a mutable fallback consumes only an error
  ok    result.a mutable map calls its transform only for ok
  ok    result.a mutable map_err consumes only an error
  ok    result.a result fallback can close an owned error arena
  ok    result.an eager result fallback discards affine values and errors
  ok    result.and_then takes a transform that changes a lent count
  ok    result.and_then transforms ok and preserves err
  ok    result.derived result debug renders both cases
  ok    result.derived result equality compares cases and payloads
  ok    result.derived result release releases the payload of either case
  ok    result.is_ok answers whether this is a success
  ok    result.map takes a transform that changes a lent count
  ok    result.map transforms ok and preserves err
  ok    result.map_err takes a transform that changes a lent count
  ok    result.map_err transforms err and preserves ok
  ok    result.map_err wraps an error in the contextual enum
  ok    result.mutable result combinator preserves its caller's protocol capture
  ok    result.result combinators preserve borrowed payloads
  ok    result.settled keeps ok and reduces err to its reason
  ok    result.tag predicates preserve affine payloads
  ok    result.tag predicates preserve linear payloads
  ok    result.unwrap returns ok
  ok    result.unwrap traps on err
  ok    result.unwrap_or returns ok or the eager fallback
  ok    result.unwrap_or_else calls only for err
  ok    result.unwrap_or_else takes a fallback that changes a lent count
  ok    scalar.a float32 absolute value drops the sign and keeps everything else
  ok    scalar.a float32 nan is equal to nothing including itself
  ok    scalar.a logarithm has defined limits
  ok    scalar.a nan is equal to nothing including itself
  ok    scalar.an absolute value drops the sign and keeps everything else
  ok    scalar.an exponential has defined limits
  ok    scalar.ceil rounds up and keeps the sign of a negative fraction
  ok    scalar.cosine uses radians and preserves special values
  ok    scalar.float32 bits are its ieee encoding
  ok    scalar.float32 from_bits keeps every bit
  ok    scalar.float32 total order ranks every class
  ok    scalar.float64 bits are its ieee encoding
  ok    scalar.float64 from_bits keeps every bit
  ok    scalar.float64 total order ranks every class
  ok    scalar.floor rounds down and keeps zero infinity and nan
  ok    scalar.powers prioritize identities and preserve odd signs
  ok    scalar.round takes halfway values to even
  ok    scalar.sine uses radians and preserves special values
  ok    scalar.square roots preserve zero and infinite limits
  ok    scalar.trunc rounds toward zero and keeps the sign
  ok    session.a handle keeps its allocator without its body
  ok    session.a receive answers what the peer sent
  ok    session.a receive until answers what a prompt peer sent
  ok    session.a receive until hands the endpoint back when the peer is late
  ok    session.a send hands the value to the peer
  ok    session.an endpoint answers the number it was opened with
  ok    session.an offer answers the branch the peer chose
  ok    session.an owned handle can be detached
  ok    session.choosing left runs the peers left branch
  ok    session.choosing right runs the peers right branch
  ok    session.closing a handle waits for the body
  ok    session.entering a protocol keeps the endpoint
  ok    session.the dual of a protocol is what its peer does
  ok    session.the dual of the dual is the protocol
  ok    session.values sent in a row arrive in the order they were sent
  ok    task.a cancelled slot runs nothing and gives the body back
  ok    task.a client reaches the state its owner holds
  ok    task.a copied key names the same registration
  ok    task.a failed preparation settles to its reason
  ok    task.a handle is delivered once its body has returned
  ok    task.a key is refused by another set and after its slot is reused
  ok    task.a lazy_map hands linear results to their owner
  ok    task.a lazy_map in completion order runs no more jobs at once than its bound
  ok    task.a lazy_map in completion order yields each result as its job finishes
  ok    task.a lazy_map keeps every result of a fallible function
  ok    task.a lazy_map released early settles every job it started
  ok    task.a lazy_map releases results that own storage
  ok    task.a lazy_map runs no more jobs at once than its bound
  ok    task.a lazy_map yields every result in input order
  ok    task.a map visits each worker entry a fixed number of times per chunk
  ok    task.a map with results to yield does not finish
  ok    task.a minted key names what it was minted for
  ok    task.a prepared body runs once its task starts
  ok    task.a refused allocation hands the body back
  ok    task.a refused allocation leaves a lazy_map in completion order settled
  ok    task.a refused allocation moves work to the caller and keeps every result
  ok    task.a registered endpoint is delivered once its peer sends
  ok    task.a sequential lazy_map in completion order yields in input order
  ok    task.a sequential lazy_map starts no task and yields the same results
  ok    task.a set with nothing registered answers none without waiting
  ok    task.a signal is registered in a wait set and withdrawn
  ok    task.a slow item fills the window and the places wrap
  ok    task.a started task answers its handle
  ok    task.a stopped map yields only what it started
  ok    task.a system task has no carrier
  ok    task.a taken endpoint comes back with its peer's value still queued
  ok    task.a task started in one call runs its body
  ok    task.a task that cannot start answers the reason
  ok    task.a thread that cannot be made hands the body back
  ok    task.a timer is registered and withdrawn
  ok    task.a value that is ready now is delivered at once
  ok    task.a value that is writable at once is delivered
  ok    task.all runs sequentially and on threads
  ok    task.all_in takes its results and tasks from its allocator
  ok    task.an errand answers its number once the errands it waits for have run
  ok    task.an offering endpoint is delivered once its peer chooses
  ok    task.an owning task hands its state back when closed
  ok    task.calls from two tasks run one at a time
  ok    task.closing a set answers a signal registration undelivered
  ok    task.closing a set answers what it still holds
  ok    task.closing answers every change a call made
  ok    task.each next delivers one of several ready sources
  ok    task.join runs on threads
  ok    task.join runs sequentially
  ok    task.join3 runs no more closures at once than its bound
  ok    task.join3 runs sequentially and on threads
  ok    task.join3_in allocates nothing in sequence
  ok    task.join3_in takes each task from its allocator
  ok    task.join4 runs no more closures at once than its bound
  ok    task.join4 runs sequentially and on threads
  ok    task.join4_in allocates nothing in sequence
  ok    task.join4_in takes each task from its allocator
  ok    task.join_in allocates nothing in sequence
  ok    task.join_in takes each task from its allocator
  ok    task.map keeps every result of a fallible function
  ok    task.map preserves deterministic order
  ok    task.map starts the next item as soon as one finishes
  ok    task.map_in takes its results and tasks from its allocator
  ok    task.releasing a client leaves its owner serving
  ok    task.releasing an owner joins its task
  ok    testing.a failure displays the caller's message
  ok    testing.a new recorder holds nothing
  ok    testing.a recorder keeps what was rendered into it
  ok    testing.a recorder records into an arena
  ok    testing.a recorder records into the system allocator
  ok    testing.a recorder traps when a write exceeds its storage
  ok    testing.a refused failure is a refusal and an assertion is not
  ok    testing.a success matches its value and an error never does
  ok    testing.allocated fails a refused allocation as a refusal carrying the message
  ok    testing.allocated hands back what a granted allocation built
  ok    testing.allocated reports each refusal of a walked body
  ok    testing.an assertion checks its condition and preserves the message
  ok    testing.an equality answers and carries what it was given
  ok    testing.an error is accepted and a success is reported
  ok    testing.byte reads a written byte and nothing past the end
  ok    testing.each_allocation_failure accepts a run that completes despite the refusal
  ok    testing.each_allocation_failure reports a body that allocates nothing
  ok    testing.each_allocation_failure reports a failed run that left an allocation live
  ok    testing.each_allocation_failure reports a refused run that fails for another reason
  ok    testing.each_allocation_failure reports a run with nothing refused that failed
  ok    testing.each_allocation_failure returns the attempts it walked
  ok    testing.each_allocation_failure takes callbacks that change lent counts
  ok    testing.each_allocation_failure walks a body that keeps an arena buffer
  ok    testing.each_allocation_failure walks an arena backing
  ok    testing.each_allocation_failure walks every attempt and settles
  ok    testing.equality accepts values with debug without display
  ok    testing.equality checks option variants and payloads
  ok    testing.equality checks result variants and payloads
  ok    testing.length counts the bytes written
  ok    testing.oom_is_a_refusal accepts each refused allocation
  ok    text.a hex error displays its reason
  ok    text.a hex_digit has its value in either case
  ok    text.a length counts bytes and not characters
  ok    text.a scalar value outlives the text that encoded it
  ok    text.a search position outlives the text that was searched
  ok    text.a slice refuses what is not text
  ok    text.a string is a text writer
  ok    text.a string written without an allocator is the system string
  ok    text.a user type implements parse by splitting once
  ok    text.a value below 16 is one hex_digit
  ok    text.an argument past the count is nothing
  ok    text.an empty allocator refuses owned text
  ok    text.an empty str has no bytes
  ok    text.as_bytes views the encoded bytes
  ok    text.ascii folding ignores case and nothing else
  ok    text.byte append grows text in an arena
  ok    text.clear empties the text and keeps its storage
  ok    text.copied text outlives its source owner
  ok    text.copied text outlives the source allocation owner
  ok    text.each allocation failure covers every byte append
  ok    text.each allocation failure covers every growth step in a multi append text
  ok    text.empty owned text needs no allocator capacity
  ok    text.ends_with compares the trailing bytes
  ok    text.equal owned and observed text share a content hash
  ok    text.find respects boundaries and empty needles
  ok    text.float parsing bounds token work before conversion
  ok    text.float parsing preserves exact values and signed zero
  ok    text.float parsing refuses range loss and invalid decimal tokens
  ok    text.float parsing results and errors outlive input
  ok    text.float32 parses through the parse trait
  ok    text.float32 parsing rounds once to binary32
  ok    text.float64 parses through the parse trait
  ok    text.from_bytes accepts valid utf8 and refuses the rest
  ok    text.hex decoding reads two digits a byte in either case
  ok    text.hex decoding refuses an odd count or a letter past f
  ok    text.hex decoding reports a full allocator
  ok    text.hex encoding writes two digits a byte
  ok    text.hex_encoded bytes read in an interpolation
  ok    text.initial copy refusal releases the empty owner
  ok    text.int16 parse checks limits
  ok    text.int32 parse checks limits
  ok    text.int64 parse checks limits
  ok    text.int8 parse checks limits
  ok    text.integer parsing accepts zeroes and reports missing digit offsets
  ok    text.integer parsing rejects non decimal input
  ok    text.into_bytes returns the encoded bytes
  ok    text.invalid byte append leaves text and input unchanged
  ok    text.invalid owned bytes are returned with the sequence offset
  ok    text.length counts encoded bytes
  ok    text.length counts the encoded bytes of owned text
  ok    text.lines have no empty final line
  ok    text.lines split at newlines and drop the terminator
  ok    text.new owned text is empty system text
  ok    text.owned text accepts unallocated queries
  ok    text.owned text append failure preserves complete text
  ok    text.owned text checks its prefix
  ok    text.owned text checks its suffix
  ok    text.owned text compares ignoring ascii case
  ok    text.owned text copies appends and transfers bytes
  ok    text.owned text copies into another allocator
  ok    text.owned text copies into the system allocator
  ok    text.owned text copies into the system allocator from an arena
  ok    text.owned text equality compares utf8 contents
  ok    text.owned text finds a needle
  ok    text.owned text iterates its lines
  ok    text.owned text iterates its scalars
  ok    text.owned text parses a value
  ok    text.owned text reads a byte by offset
  ok    text.owned text slices on character boundaries
  ok    text.owned text splits at a separator
  ok    text.owned text splits once at a separator
  ok    text.owned text trims ascii whitespace
  ok    text.owned text trims unicode whitespace
  ok    text.owned text views its encoded bytes
  ok    text.parse errors can be released explicitly
  ok    text.parse selects its implementation from a named type argument
  ok    text.parse selects its implementation from a result annotation
  ok    text.parsed values and errors outlive their input text
  ok    text.refused conversions held in a vector release in generic code
  ok    text.scalar iteration preserves nul bom and scalar extrema
  ok    text.scalar iteration reports values and byte positions
  ok    text.search errors can be released explicitly
  ok    text.settling invalid bytes keeps the offset of the bad sequence
  ok    text.split handles empty input and multibyte delimiters
  ok    text.split preserves empty fields and stays finished
  ok    text.split_once cuts at the first separator of any width
  ok    text.starts_with compares the leading bytes
  ok    text.text equality and order are total by bytes
  ok    text.text hashes preserve utf8 bytes and length
  ok    text.text queries compare contents
  ok    text.trim_ascii removes only ascii whitespace at the ends
  ok    text.trim_unicode removes white space at the ends
  ok    text.two hex digits spell one byte
  ok    text.uint16 parse checks limits
  ok    text.uint32 parse checks limits
  ok    text.uint64 parse checks limits
  ok    text.uint8 parse checks limits
  ok    text.unicode trim recognizes every white space character
  ok    text.utf8 validation error is independent of released input
  ok    text.utf8 validation rejects non scalar and incomplete encodings
  ok    text.valid owned bytes keep nul and bom
  ok    text.validated byte transfer does not allocate
  ok    text.view reads the owned text
  ok    time.a backoff doubles its pause up to the longest
  ok    time.a backoff gives no pause that would end past the deadline
  ok    time.a deadline after no time has already passed
  ok    time.a deadline an hour away has about an hour left
  ok    time.a deadline an hour away has not expired
  ok    time.a deadline too far away never passes
  ok    time.a deadline's time left counts down to zero
  ok    time.a duration displays in the largest unit below it
  ok    time.a duration is made from_milliseconds
  ok    time.a duration is made from_seconds
  ok    time.a duration returns its nanoseconds
  ok    time.a new backoff starts at its first pause
  ok    time.a reset backoff starts again at its first pause
  ok    time.a sleep lasts at least its duration
  ok    time.a timestamp displays as rfc 3339
  ok    time.a timestamp is made only inside the years rfc 3339 writes
  ok    time.an http_date displays in the form header fields use
  ok    time.an instant measures the time since another
  ok    time.an instant measures the time since it was read
  ok    time.an instant reads nanoseconds of the monotonic clock
  ok    time.from_nanoseconds makes a duration that long
  ok    time.nanoseconds returns the part of a second
  ok    time.now reads the present
  ok    time.the earlier of two deadlines is the nearer one
  ok    time.the monotonic clock never moves back
  ok    time.the runtime is given never as no deadline
  ok    time.unix_seconds counts from the epoch
  ok    tls.a TLS error becomes an I/O error by category
  ok    tls.a TLS error displays what failed
  ok    tls.a client accepting any certificate connects to an unknown server
  ok    tls.a client and a server exchange bytes over a pipe
  ok    tls.a client configuration closes while a stream it opened lives
  ok    tls.a client configuration is built from the system's roots or from roots of its own
  ok    tls.a client configuration is read from PEM files
  ok    tls.a client configuration refuses a certificate without its key
  ok    tls.a client given roots trusts those roots alone
  ok    tls.a client refuses a certificate no trusted root issued
  ok    tls.a client refuses a server whose certificate names another host
  ok    tls.a client refuses an expired certificate
  ok    tls.a client trusts a server whose root it names among its roots
  ok    tls.a configuration file error displays its cause
  ok    tls.a connect whose deadline has passed times out before shaking hands
  ok    tls.a finished stream hands back its transport after close_notify
  ok    tls.a handshake the server never answers ends at its deadline
  ok    tls.a refusal displays its operation, its reason and its code
  ok    tls.a refusal keeps the runtime's code and classifies it
  ok    tls.a refused name is refused before any byte is sent
  ok    tls.a scratch PEM file holds its text
  ok    tls.a second connection with one configuration resumes the first session
  ok    tls.a server configuration closes while a stream it opened lives
  ok    tls.a server configuration is built from a certificate and its key
  ok    tls.a server configuration is read from PEM files
  ok    tls.a server refuses a client that shares none of its protocols
  ok    tls.a server requiring a client certificate accepts a client presenting one
  ok    tls.a server requiring a client certificate refuses a client without one
  ok    tls.a server requiring a client certificate refuses one no trusted root issued
  ok    tls.a server requiring client certificates needs roots to verify them
  ok    tls.a server stream reads what a client wrote before closing
  ok    tls.a stream accepted later runs no handshake until it is used
  ok    tls.a stream accepted later shakes hands at its first read
  ok    tls.a stream accepted later shakes hands by the deadline it is given
  ok    tls.a stream cut short without close_notify is truncated
  ok    tls.a stream lends its transport to be configured
  ok    tls.a stream lends its transport to be observed
  ok    tls.a stream that notified its close still reads the peer's answer
  ok    tls.a stream's writer refuses to write before the handshake
  ok    tls.a stream's writer sends encrypted bytes over the connection
  ok    tls.a write larger than one record arrives whole
  ok    tls.an abandoned stream is truncated at its peer
  ok    tls.an accept whose deadline has passed times out before shaking hands
  ok    tls.an optional client certificate lets a client without one connect
  ok    tls.bytes after the peer's close_notify are ignored
  ok    tls.closing a stream sends close_notify to the peer
  ok    tls.no protocol is agreed when the client offers none
  ok    tls.taking from the front of a queue keeps the rest in order
  ok    tls.the client and the server agree on the protocol both prefer
  ok    tls.the system's roots alone do not trust the test root
  ok    tuple.a five tuple prints its components in parentheses
  ok    tuple.a four tuple prints its components in parentheses
  ok    tuple.a pair derives its traits from its components
  ok    tuple.a pair prints its components in parentheses
  ok    tuple.a pair releases its components last first
  ok    tuple.a seven tuple prints its components in parentheses
  ok    tuple.a six tuple prints its components in parentheses
  ok    tuple.a three tuple prints its components in parentheses
  ok    tuple.an eight tuple compares by position
  ok    tuple.an eight tuple prints its components in parentheses
  ok    tuple.eight tuple compares and hashes by every component
  ok    tuple.five tuple compares and hashes by every component
  ok    tuple.four tuple compares and hashes by every component
  ok    tuple.pair compares and hashes by every component
  ok    tuple.seven tuple compares and hashes by every component
  ok    tuple.six tuple compares and hashes by every component
  ok    tuple.three tuple compares and hashes by every component
  ok    uuid.a parse error says where the text went wrong
  ok    uuid.a timestamp is read only from version 7
  ok    uuid.a v4 identifier has version 4 and the rfc variant
  ok    uuid.a v7 identifier records when it was made
  ok    uuid.an identifier parses back to itself
  ok    uuid.ascii is the written form
  ok    uuid.bytes come back as they went in
  ok    uuid.debug writes the identifier as display does
  ok    uuid.equal identifiers hash alike
  ok    uuid.text that is not an identifier is refused where it goes wrong
  ok    uuid.the bytes of max are all 255
  ok    uuid.the max identifier is all one and sorts last
  ok    uuid.the nil identifier is all zero
  ok    uuid.the variant is read from the top bits of byte 8
  ok    uuid.the version is read from its four bits
  ok    uuid.v7 identifiers made in later milliseconds sort later
  
  1940 passed, 0 failed
