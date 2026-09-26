"""Tlön's AGENTS.md as the template carries it: two sections gone, the rest byte for byte.

    agents_md.py IN OUT

- "Let the watcher run the tests": both arms were told to run a background test watcher, which
  outlives the step, runs `mix test` on the run's database while the check drops and recreates it,
  and is invisible to test_runs.
- "Edit Elixir with Menard": the menard doors, which only the plugins under test may open.
"""

import sys

WATCHER = "### Let the watcher run the tests"
MENARD = "### Edit Elixir with Menard"
NEXT = "## How to work"


def strip(text):
    a, b = text.index(WATCHER), text.index(NEXT)
    if not a < text.index(MENARD) < b:
        raise ValueError("AGENTS.md's sections are not where this expects them")
    return text[:a] + text[b:]


if __name__ == "__main__":
    src, dest = sys.argv[1:3]
    # read before opening the destination: IN and OUT are the same file in build.sh
    text = open(src).read()
    open(dest, "w").write(strip(text))
