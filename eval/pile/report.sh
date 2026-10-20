#!/usr/bin/env bash
# Tokens per landed commit, from the transcripts on this machine: no bench, no second session.
#
# Every Claude Code transcript (~/.claude/projects/*/*.jsonl) carries per-turn token usage and
# every tool call; every commit an agent made carries a `Claude-Session:` trailer. Joined by the
# session id (the transcript's `remote_session_change` attachment), each session has its tokens,
# its calls and the commits it landed on main, and the arms are where and when menard's hook was:
#
#   hooked  the menard repo from 2026-10-01, and every repo from 2026-10-20 (the plugin at user
#           scope since then: ~/.claude/settings.json enabledPlugins)
#   bare    tlon and ficciones from 2026-09-29 (the script ban's date) to 2026-10-19, no hook
#
# Same model and same repo across arms is what reads cleanly: tlon from 2026-10-20 against tlon
# before it. Earlier sessions are left out. ±5%: the counts are regexes over commands.
#
#   eval/pile/report.sh            the whole pass (~10 min over 1,400 transcripts), then the table
#   eval/pile/report.sh --cached   the table from the last pass
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="${MENARD_PILE:-$HOME/.cache/menard/pile}"
mkdir -p "$work"
P="$HOME/.claude/projects"

if [[ "${1:-}" != "--cached" ]]; then
  : > "$work/sessions.jsonl"
  for f in "$P"/*/*.jsonl; do
    jq -c -n --arg f "${f#"$P"/}" -f "$here/session.jq" "$f" >> "$work/sessions.jsonl" 2>/dev/null || true
  done
  : > "$work/commits.tsv"
  for r in "$HOME"/projects/*/; do
    [[ -d "$r/.git" ]] || continue
    branch=$(git -C "$r" symbolic-ref --short HEAD 2>/dev/null || echo HEAD)
    git -C "$r" log "$branch" --format='%H%x09%aI%x09%(trailers:key=Claude-Session,valueonly,separator=%x20)' --shortstat 2>/dev/null |
      awk -v repo="$(basename "$r")" -v OFS='\t' '
        /^[0-9a-f]{40}\t/ { if (h) print repo, h, d, s, ins, del; split($0, a, "\t"); h=a[1]; d=a[2]; s=a[3]; ins=0; del=0; next }
        /files? changed/ { ins=0; del=0; if (match($0, /([0-9]+) insertion/, m)) ins=m[1]; if (match($0, /([0-9]+) deletion/, m)) del=m[1] }
        END { if (h) print repo, h, d, s, ins, del }' >> "$work/commits.tsv"
  done
fi

# one row per session id: tokens and calls summed over its transcript files (a resume, a worktree)
jq -r 'select(.id != null) | [.id, (.file|split("/")[0]|sub("-home-andrew-projects-";"")|split("--")[0]), (.model // "?"), (.first // "")[0:10], (.usage.input + .usage.cache_read + .usage.cache_write), .usage.output, .turns, .bash, .edit, .read, .menard_cli, .menard_mcp, .python, .filtered, .denied] | @tsv' "$work/sessions.jsonl" |
  awk -F'\t' -v OFS='\t' '{ id=$1; if (!(id in big) || $7 > big[id]) { big[id]=$7; proj[id]=$2; model[id]=$3 }
    if (!(id in day) || $4 < day[id]) day[id]=$4
    for (i=5; i<=15; i++) sum[id, i]+=$i }
    END { for (id in proj) { line = id OFS proj[id] OFS model[id] OFS day[id]; for (i=5; i<=15; i++) line = line OFS sum[id, i]; print line } }' > "$work/by_id.tsv"
awk -F'\t' '{ match($4, /session_01[A-Za-z0-9]+/); id=substr($4, RSTART, RLENGTH); if (id=="") next; n[id]++; lines[id]+=$5+$6 }
  END { for (id in n) print id "\t" n[id] "\t" lines[id] }' "$work/commits.tsv" > "$work/commits_by_session.tsv"
awk -F'\t' -v OFS='\t' 'NR==FNR { n[$1]=$2; l[$1]=$3; next } { print $0, (n[$1]+0), (l[$1]+0) }' "$work/commits_by_session.tsv" "$work/by_id.tsv" > "$work/joined.tsv"

awk -F'\t' -v OFS='\t' '
function arm(project, day) {
  if (day >= "2026-10-20") return "hooked"
  if (project == "menard" && day >= "2026-10-01") return "hooked"
  if ((project == "tlon" || project == "ficciones") && day >= "2026-09-29") return "bare"
  return ""
}
function median(arr, n,   i, j, t) { for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (arr[j] < arr[i]) { t = arr[i]; arr[i] = arr[j]; arr[j] = t }; return (n % 2) ? arr[(n + 1) / 2] : (arr[n / 2] + arr[n / 2 + 1]) / 2 }
{ a = arm($2, $4); if (a == "") next
  m = $3; sub("claude-", "", m); k = a "\t" m
  n[k]++; tok[k]+=$5; out[k]+=$6; bash[k]+=$8; edit[k]+=$9; read[k]+=$10; py[k]+=$13; filt[k]+=$14; den[k]+=$15; com[k]+=$16; lines[k]+=$17
  if ($16 > 0) { withc[k]++; v[k, withc[k]] = $5 / 1e6 / $16 }
}
END {
  print "arm", "model", "sessions", "w/commits", "commits", "lines", "Mtok", "Mtok/commit", "median/session", "ktok/line", "kout/commit", "bash/commit", "reads/edit", "py/100bash", "filtered", "denied"
  for (k in n) if (com[k] > 0) { c = withc[k]; delete arr; for (i = 1; i <= c; i++) arr[i] = v[k, i]
    printf "%s\t%d\t%d\t%d\t%d\t%.1f\t%.2f\t%.2f\t%.1f\t%.1f\t%.1f\t%.2f\t%.1f\t%d\t%d\n", k, n[k], c, com[k], lines[k], tok[k]/1e6, tok[k]/1e6/com[k], median(arr, c), tok[k]/1e3/(lines[k]+1), out[k]/1e3/com[k], bash[k]/com[k], read[k]/(edit[k]+1), 100*py[k]/(bash[k]+1), filt[k], den[k] }
}' "$work/joined.tsv" | sort | column -t -s $'\t'
