# the gate of every app the change touched, in Tlön's own toolchain and the run's throwaway test DB
set -uo pipefail
changed=$(git diff --name-only eval-base; git ls-files --others --exclude-standard)
status=0 summary=""
for app in server console; do
  if [ "$app" = server ] || grep -q "^$app/" <<<"$changed"; then
    echo "== $app"
    out=$(cd $app && mix precommit 2>&1); code=$?
    echo "$out" | tail -25
    [ $code -eq 0 ] || { echo "FAIL: $app precommit"; status=1; }
    summary+="$app: $(grep -E 'Result:|[0-9]+ tests?,|FAIL' <<<"$out" | tail -1)"$'\n'
  fi
done
# last, where a row's `check` shows it: the gate's tail is the app's debug log
printf '%s' "$summary"
exit $status
