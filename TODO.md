# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- `find calls Menard.Verbs.edit lib` found nothing, while every writing verb calls it as `edit(…)`
  under `import Menard.Verbs` (2026-10-01). A local call in a module that imports the target's
  module is a call of it.
