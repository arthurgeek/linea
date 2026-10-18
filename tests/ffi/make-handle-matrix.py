# Writes the handle matrix: four cases that put a C object's handle in each
# place a program can hold one -- a local, a structure's field, an `inout`
# parameter, a field of `inout self` -- and change the object through each
# convention C may change it by: a plain lend (`named_reset`), `inout`
# (`named_replace`) and `sink` (`named_close`).
#
# - tests/ffi/every_change_to_a_handle_ends_what_was_read_from_it reads the
#   object's name, changes the object, then uses the name: each is [O-Borrow].
# - tests/ffi/a_handle_changes_after_the_last_read_of_it uses the name before
#   the change: each runs and prints 5.
# - tests/dependencies/every_change_to_a_librarys_handle_ends_what_was_read_from_it
#   and tests/dependencies/a_librarys_handle_changes_after_the_last_read_of_it
#   are the same with the handle's type declared in a library, `handles`, and
#   every changing `extern` declared in the program.
#
# Every Linea and C file it writes names it in its first lines; a manifest is
# JSON, which holds no comment, and carries no such line.
#
# Run from this directory, then format what it wrote and refill the goldens:
#   python3 make-handle-matrix.py
#   linea fmt <each written .lin file>
#   zig-out/bin/conformance <each case> --update ...
import os

root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
STAMP = 'Written by tests/ffi/make-handle-matrix.py, which writes the whole matrix;\nchange the script and run it rather than editing this file.'
LINEA_STAMP = ''.join(f'// {line}\n' for line in STAMP.split('\n'))

C = '/* ' + STAMP.replace('\n', '\n * ') + ' */\n' + r'''#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* An object holding a name C allocates. Resetting, replacing or closing it
 * frees the name it held. */
struct named { char *name; };

uint64_t named_open(void) {
    struct named *n = malloc(sizeof *n);
    n->name = strdup("first");
    return (uint64_t)(uintptr_t)n;
}

const char *named_name(uint64_t handle) { return ((struct named *)(uintptr_t)handle)->name; }

void named_reset(uint64_t handle) {
    struct named *n = (struct named *)(uintptr_t)handle;
    free(n->name);
    n->name = strdup("second");
}

void named_close(uint64_t handle) {
    struct named *n = (struct named *)(uintptr_t)handle;
    free(n->name);
    free(n);
}

void named_replace(uint64_t *handle) {
    named_close(*handle);
    *handle = named_open();
}
'''
HEAD = LINEA_STAMP + '''import std.ffi

// A handle to an object C holds. `read` says C only reads it; every other
// convention lets C change or free it.
@(opaque, linear)
type Name = UInt64

extern fn named_open() -> Name

extern fn named_name(read handle: Name) -> ffi.CText where borrows(handle)

extern fn named_reset(handle: Name)

extern fn named_replace(inout handle: Name)

extern fn named_close(sink handle: Name)

@linear
struct Box {
    handle: Name,
}

impl Box {
    fn close(sink self: Self) {
        let Box { handle: handle } = self
        named_close(handle)
    }
'''
# How C changes the object, given the place the handle sits in.
changes = {
    'reset': lambda p: f'named_reset({p})',
    'replace': lambda p: f'named_replace(&{p})',
    'close': lambda p: f'named_close({p})',
}
def body(place, change, before):
    read = f'        let length = name.length()'
    lines = [f'        let name = named_name({place})']
    if before:
        lines += [read, '        ' + changes[change](place)]
    else:
        lines += ['        ' + changes[change](place), read]
    return lines

def gen(before, cross=False):
    methods = []  # members of `impl Box`
    funcs = []
    calls = []
    for change in ['reset', 'replace']:
        b = body('self.handle', change, before)
        methods.append(f'    // A field of `inout self`, then `{change}`.\n    pub fn self_field_{change}(inout self: Self) -> UInt64 {{\n' + '\n'.join(b) + '\n        length\n    }\n')
        calls.append(f'self_field_{change}')
    for change in ['reset', 'replace', 'close']:
        b = body('held', change, before)
        settle = '' if change == 'close' else '    named_close(held)\n'
        funcs.append(f'// A local, then `{change}`.\npub fn local_{change}() -> UInt64 {{\n    var held = named_open()\n' + '\n'.join(l[4:] for l in b) + '\n' + settle + '    length\n}\n')
        calls.append(f'local_{change}')
    for change in ['reset', 'replace']:
        b = body('box.handle', change, before)
        funcs.append(f'// A field of a local structure, then `{change}`.\npub fn field_{change}() -> UInt64 {{\n    var box = Box {{ handle = named_open() }}\n' + '\n'.join(l[4:] for l in b) + '\n    box.close()\n    length\n}\n')
        calls.append(f'field_{change}')
        b = body('handle', change, before)
        funcs.append(f'// An `inout` parameter, then `{change}`.\nfn lent_{change}(inout handle: Name) -> UInt64 {{\n' + '\n'.join(l[4:] for l in b) + f'\n    length\n}}\n\npub fn param_{change}() -> UInt64 {{\n    var held = named_open()\n    let length = lent_{change}(&held)\n    named_close(held)\n    length\n}}\n')
        calls.append(f'param_{change}')
    head = HEAD
    if cross:
        head = HEAD.replace('''// A handle to an object C holds. `read` says C only reads it; every other
// convention lets C change or free it.
@(opaque, linear)
type Name = UInt64

extern fn named_open() -> Name
''', '''import handles

use handles.Name

// `Name` is sealed in the library `handles`, whose manifest trusts it with
// C, so it is a handle in this module's `extern` declarations too.
fn named_open() -> Name {
    handles.open()
}
''')
    src = head + '\n'.join(methods) + '}\n\n' + '\n'.join(funcs)
    # self methods called via a pub wrapper
    for change in ['reset', 'replace']:
        src += f'\npub fn self_{change}() -> UInt64 {{\n    var box = Box {{ handle = named_open() }}\n    let length = &box.self_field_{change}()\n    box.close()\n    length\n}}\n'
    pub_calls = [c if not c.startswith('self_field_') else c.replace('self_field_', 'self_') for c in calls]
    return src, pub_calls

LIB = LINEA_STAMP + '''// A handle to an object C holds, sealed so only this library makes one.
@(opaque, linear)
type Name = UInt64

extern fn named_open() -> Name

pub fn open() -> Name {
    named_open()
}
'''
cases = [('ffi', 'every_change_to_a_handle_ends_what_was_read_from_it', False, False), ('ffi', 'a_handle_changes_after_the_last_read_of_it', True, False),
         ('dependencies', 'every_change_to_a_librarys_handle_ends_what_was_read_from_it', False, True), ('dependencies', 'a_librarys_handle_changes_after_the_last_read_of_it', True, True)]
for group, name, before, cross in cases:
    d = os.path.join(root, group, name)
    os.makedirs(os.path.join(d, 'named'), exist_ok=True)
    open(os.path.join(d, 'named', 'named.c'), 'w').write(C)
    if cross:
        os.makedirs(os.path.join(d, 'handles'), exist_ok=True)
        open(os.path.join(d, 'handles', 'linea.json'), 'w').write('{ "kind": "library", "name": "handles", "extern": ["."] }\n')
        open(os.path.join(d, 'handles', 'handles.lin'), 'w').write(LIB)
        open(os.path.join(d, 'linea.json'), 'w').write('{ "extern": ["named"], "native": ["named/named.c"], "dependencies": { "handles": { "path": "handles", "extern": true } } }\n')
    else:
        open(os.path.join(d, 'linea.json'), 'w').write('{ "extern": ["named"], "native": ["named/named.c"] }\n')
    src, calls = gen(before, cross)
    open(os.path.join(d, 'named', 'named.lin'), 'w').write(src)
    if before:
        main = LINEA_STAMP + 'import std.io\nimport named\n\n// Each reads the name before C changes the object, so each answers 5.\nfn main() -> Result[UInt8, io.IoError] {\n' + ''.join(f'    io.println("{c}: {{named.{c}()}}")?\n' for c in calls) + '    .Ok(0)\n}\n'
    else:
        main = LINEA_STAMP + 'import named\n\n// Each reads the name after C changed the object it lives in.\nfn main() -> UInt8 {\n    let total = ' + ' + '.join(f'named.{c}()' for c in calls) + '\n    UInt8(total)\n}\n'
    open(os.path.join(d, 'main.lin'), 'w').write(main)
