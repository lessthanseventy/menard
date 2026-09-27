# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- tlon pins menard 0.5.0 from hex (server/mix.lock), and `server/lib/server/source/tools.ex:56`
  hands `Menard.Clause.replace_body/5` whatever its caller gave as `code`. Since 0.5.0 a whole
  clause given there was taken as a `rewrite`; that fallback is removed (2026-09-26, with the
  prose verbs), so on upgrading tlon must send a whole clause to `Menard.Clause.rewrite/5` itself,
  or the call is refused toward `rewrite`. Not edited from here: tlon's change, when it upgrades.
- hooks/format-report.sh skips a shell-written file whose content its repo already holds, which is
  what git writes, except a conflicted merge's (`git merge`, `stash pop`, `rebase`): the markers are
  new content, so the file is formatted and named back as not parsing. The agent knows the merge
  conflicted; skip what `git ls-files -u` lists if that noise shows up.
