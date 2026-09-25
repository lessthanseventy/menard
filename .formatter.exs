[
  # not test/fixtures: weird.ex keeps shapes a formatter would rewrite ('single' charlists), on purpose
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib}/**/*.{ex,exs}",
    "test/*.exs",
    "test/{menard,support}/**/*.{ex,exs}"
  ],
  line_length: 110,
  plugins: [DoctestFormatter]
]
