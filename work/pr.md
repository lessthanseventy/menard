# bin/menard: a read-only _build says so and runs the last build

Closes ticket #571. In a sandboxed seat menard's `_build` is not writable; the launcher's compile
failed on the write and blamed "a compile error in menard ITSELF (a half-applied edit)".

Now, when `_build/$MIX_ENV` is not writable, the launcher skips `deps.get` and the compile, says on
stderr that the build is read-only and the last build runs, and proceeds as `--frozen`.

Checked: new `bin_copy_test` makes the copy's `_build` read-only with the source newer than the build;
red before (exit 1), green after (4/5 in bin_copy_test). The fifth, "mix.lock gained a dep", needs a
writable ~/.hex and fails in this seat with or without the change (`Hex.Registry.Server … :eaccess`).
