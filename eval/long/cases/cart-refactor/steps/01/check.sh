source "$EVAL_COMMON"
compiles
left=$(grep -rn --exclude-dir=hidden "price_with_tax" lib test) && fail "still named price_with_tax: $left"
tests_pass
formatted
