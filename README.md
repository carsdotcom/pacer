<object data="assets/logo.png" type="image/jpeg">
  <img src="assets/PACER.png" alt="Pacer" />
</object>

# Pacer: An Elixir Library for Dependency Graph-Based Workflows With Robust Compile Time Safety & Guarantees

## Overview

`Pacer.Workflow` is an abstraction designed for complex workflows where many interdependent data points need to be
stitched together to provide a final result, specifically workflows where each data point needs to be
loaded and/or calculated using discrete, application-specific logic.

See the moduledocs for `Pacer.Workflow` for detailed information about how to use Pacer and define your own
workflows, along with a detailed list of options and ideas that underlie Pacer.

## Installation

Add :pacer to the list of dependencies in `mix.exs`:

```elixir
[
  {:pacer, "~> 0.1"}
]
```

## Anti-patterns

- Using Pacer when your dependency graph is a line, or if you just have a
  handfull of data points. You would be better off using a pipeline of function
  calls. It would be easier to write, clearer to read, and faster to execute.
- Not running your workflow in your tests. The main public interface of your
  workflow is calling `Pacer.Workflow.execute/1` on it. Having a test file
  for a Pacer workflow that does not do this, is like having any other module
  where the main public interface is not exercised in the tests.

  [Here is a repo with some practical examples of Pacer Anti-patterns](https://github.com/dewetblomerus/pacer_anti_patterns)

## Contributing

We welcome everyone to contribute to Pacer -- whether it is documentation updates, proposing and/or implementing new features, or contributing bugfixes.

Please feel free to create issues on the repo if you notice any bugs or if you would like to propose new features or implementations.

When contributing to the codebase, please:

1. Run the test suite locally with `mix test`
2. Verify Dialyzer still passes with `mix dialyzer`
3. Run `mix credo --strict`
4. Make sure your code has been formatted with `mix format`

In your PRs please provide the following detailed information as you see fit, especially for larger proposed changes:

1. What does your PR aim to do?
2. The reason/why for the changes
3. Validation and verification instructions (how can we verify that your changes are working as expected; if possible please provide one or two code samples that demonstrate the behavior)
4. Additional commentary if necessary -- tradeoffs, background context, etc.

We will try to provide responses and feedback in a timely manner. Please feel free to ping us if you have a PR or issue that has not been responded to.
