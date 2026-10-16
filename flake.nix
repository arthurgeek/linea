{
  description = "linea development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # `nix develop`
        #
        # Clang rather than the platform default, so `cc` is the same compiler
        # everywhere and a generated binary is linked the same way on every
        # machine. It is also the only one of the two that offers the memory
        # sanitizer at all.
        devShells.default = pkgs.mkShell.override { stdenv = pkgs.clangStdenv; } {
          buildInputs = [
            pkgs.zig
            pkgs.zls

            # Backend toolchain. `mlir-opt` lowers the dialects the compiler
            # prints to the LLVM dialect and `mlir-translate` turns that into
            # LLVM IR; the compiler and linker come from the stdenv C
            # toolchain, which mkShell already puts on PATH as `cc` and which
            # takes LLVM IR as an input language -- so no assembler of our own
            # appears here.
            pkgs.llvmPackages.mlir

            # The editor grammar is generated from `grammar.js` rather than
            # committed, and the gates read what it emits. Both happen during a
            # test run, so the CLI is a requirement of the suite rather than
            # only of someone editing the grammar.
            pkgs.tree-sitter
            # `tree-sitter generate` evaluates grammar.js, so it needs a
            # JavaScript runtime. Nothing else here does.
            pkgs.nodejs
            # Transcript cases drive the HTTP examples with `curl`.
            pkgs.curl
            # The C-interop cases link SQLite with `"link": ["sqlite3"]` and
            # include its header; the shell's compiler wrapper puts both on
            # the search paths.
            pkgs.sqlite
          ];

          shellHook = ''
            # Find the checkout the shell was entered from. `nix develop <path>`
            # run from outside any checkout finds none, and then there is no
            # build output to put on PATH and no editor grammar to install, so
            # everything below that needs the checkout is skipped.
            _linea_root="$PWD"
            while [ "$_linea_root" != "/" ] && [ ! -f "$_linea_root/flake.nix" ]; do
              _linea_root="$(dirname "$_linea_root")"
            done
            if [ -f "$_linea_root/flake.nix" ]; then
              _linea_checkout=1
            else
              _linea_checkout=0
            fi

            # The repo's own build output comes first, so `linea` in the Helix
            # config resolves to the tree being worked in -- which is the right
            # binary when the language itself is what is under development. It
            # can be stale: format-on-save applies whatever was last built, and
            # keeping that current is the user's business.
            if [ "$_linea_checkout" = 1 ]; then
              export PATH="$_linea_root/zig-out/bin:$PATH"
            fi

            # Each block runs only when that editor is on PATH, so the hook
            # no-ops for people who do not use it, and in CI.

            # Helix -- the tree-sitter grammar. Regeneration is gated on the
            # content of grammar.js rather than on its timestamp, for the
            # reason the Sublime syntax below is: a checkout sets an mtime to
            # whenever it ran, which is not ordered against a file generated
            # from it, so "the source is newer" can be false for a source that
            # changed. The stamp is a copy of grammar.js as it was when the
            # parser was last generated from it.
            #
            # The parser and the shared object stay on timestamps, which is
            # sound because both are written here: a regenerated parser is
            # newer than the object built before it, and a `cc` that fails
            # leaves no object, so the next entry retries.
            if [ "$_linea_checkout" = 1 ] && command -v hx >/dev/null 2>&1; then
              _ts_dir="$_linea_root/editor-support/tree-sitter-linea"
              _ts_parser="$_ts_dir/src/parser.c"
              _ts_built="$_ts_dir/src/grammar.js.built"
              _hx_grammar="$HOME/.config/helix/runtime/grammars/linea.so"
              _hx_queries="$HOME/.config/helix/runtime/queries/linea"
              if [ ! -f "$_ts_parser" ] || ! cmp -s "$_ts_dir/grammar.js" "$_ts_built"; then
                ( cd "$_ts_dir" && tree-sitter generate -o src >/dev/null ) \
                  && cp "$_ts_dir/grammar.js" "$_ts_built"
              fi
              mkdir -p "$(dirname "$_hx_grammar")"
              if [ ! -f "$_hx_grammar" ] || [ "$_ts_parser" -nt "$_hx_grammar" ]; then
                cc -shared -fPIC -O2 -I "$_ts_dir/src" -o "$_hx_grammar" "$_ts_parser"
              fi
              mkdir -p "$_hx_queries"
              cp "$_ts_dir"/queries/*.scm "$_hx_queries"/
              unset _ts_dir _ts_parser _ts_built _hx_grammar _hx_queries
            fi

            # bat -- the Sublime syntax. Gating the work is load-bearing rather
            # than tidy: `bat cache --build` reads every syntax bat knows about
            # and takes seconds, which is intolerable on every shell entry and
            # fine on the rare one following a change.
            #
            # Gated on content and not on a timestamp. `cp` stamps its
            # destination with the time of the copy, so the installed file is
            # newer than its source the moment it is written -- and any later
            # change that does not push the source's mtime past that point,
            # which a checkout restoring an older one does, leaves "source is
            # newer" false permanently. The editor then reads a stale syntax
            # that no shell entry will ever replace, and nothing says so,
            # because wrong highlighting is not an error.
            #
            # The stamp is a copy of what was installed when the cache was last
            # built successfully, so a failed build is retried rather than
            # recorded as done. bat reads the cache and not the file, which is
            # why the two are tracked apart.
            _sub_src="$_linea_root/editor-support/sublime-linea/linea.sublime-syntax"
            if [ "$_linea_checkout" = 1 ] && command -v bat >/dev/null 2>&1 && [ -f "$_sub_src" ]; then
              _sub_dst="$(bat --config-dir)/syntaxes/linea.sublime-syntax"
              _sub_built="$(bat --cache-dir)/linea.sublime-syntax.built"
              if ! cmp -s "$_sub_src" "$_sub_dst" || ! cmp -s "$_sub_src" "$_sub_built"; then
                mkdir -p "$(dirname "$_sub_dst")" "$(dirname "$_sub_built")"
                cp "$_sub_src" "$_sub_dst"
                if bat cache --build >/dev/null 2>&1; then
                  cp "$_sub_src" "$_sub_built"
                else
                  echo "linea: bat cache --build failed; syntax installed but not loaded" >&2
                fi
              fi
              unset _sub_dst _sub_built
            fi
            unset _sub_src _linea_root _linea_checkout
          '';
        };

        # Optional offline reference generator; ordinary builds use committed vectors.
        devShells.math-reference = pkgs.mkShell.override { stdenv = pkgs.clangStdenv; } {
          buildInputs = [ pkgs.mpfr pkgs.gmp ];
        };
      }
    );
}
