# Used by "mix format"
spark_locals_without_parens = [
  batch: 2,
  batch: 3,
  default: 1,
  dependencies: 1,
  doc: 1,
  field: 1,
  field: 2,
  guard: 1,
  resolver: 1,
  virtual?: 1
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
