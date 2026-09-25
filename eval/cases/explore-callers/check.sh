source "$CASE_DIR/../common.sh"
[ -f CALLERS.txt ] || fail "no CALLERS.txt"
got=$(grep -v '^\s*$' CALLERS.txt | sed 's/^[-* `]*//; s/[` ]*$//' | sort -u)
want=$(printf '%s\n' Shop.Cart.lines/1 Shop.Orders.total/1 ShopWeb.CartLive.render/1 ShopWeb.CoreComponents.product_card/1 | sort)
[ "$got" = "$want" ] || fail "callers: got [$(echo $got)] want [$(echo $want)]"
echo ok
