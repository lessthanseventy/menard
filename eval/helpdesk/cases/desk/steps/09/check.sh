# step 09: Desk.Tickets is split for real (split.py), credo finds nothing, and every acceptance
# test of every step still passes: the API test holds each public function in place
source "$CASE_DIR/../../grade.sh"
python3 "$CASE/split.py" || exit 1
out=$(mix credo 2>&1) || { echo "$out" | tail -15; echo "FAIL: credo"; exit 1; }
hidden 09
graded all
