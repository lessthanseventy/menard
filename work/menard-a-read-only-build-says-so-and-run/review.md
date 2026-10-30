Reviewer grade: no free reviewer is at the builder's grade (senior), so this review is by a reviewer below that grade. Verdict: APPROVE.

Checked:
- Diff: bin/menard (+10/-2) and test/menard/bin_copy_test.exs (+26). Read the whole launcher, not just the hunks.
- `bin/menard run test test/menard/bin_copy_test.exs`: 5 tests, 1 failed. The failure is "a checkout whose mix.lock gained a dep since its first run fetches it, and says nothing". It dies on `Hex.Registry.Server … {:error, :eaccess}`, i.e. the sandbox cannot write ~/.hex. Emma reports the same in her seat. The new read-only test passes (it is one of the four green). Not a logic failure in this change, but I did not run it on main, so I cannot say it is pre-existing.
- Check recorded as check_failed (exit 2) with that output.

Why approve: the #571 symptom is fixed for the case the test pins. A read-only _build is now reported on stderr, the last build runs with --frozen, and "compile error in menard ITSELF" is not printed.

Non-blocking points, filed as follow_ups:
- The writability test is on `_build/$MIX_ENV` only. A writable top dir with a read-only subdir still reaches the misleading message.
- With _build read-only, the launcher skips `deps.get` even though the fetch writes deps/, not _build. The comment's "can be neither fetched for nor compiled into" is wider than the code needs.
- The mix.lock test needs a writable ~/.hex, so it cannot run in a sandboxed seat.