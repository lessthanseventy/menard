sed -i 's/category: :drink, stock: 20}/category: :drink, stock: 20, weight: 100}/; s/category: :kitchen, stock: 5}/category: :kitchen, stock: 5, weight: 350}/; s/category: :kitchen, stock: 2}/category: :kitchen, stock: 2, weight: 900}/' lib/shop/catalog.ex
# the sed runs a line past the formatter's width; the base the agent starts from must be formatted,
# or every run fails `clean` on a file the task never needed (bench1-3)
mix format lib/shop/catalog.ex
