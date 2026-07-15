# Contributing

## Formatting

CI enforces `forge fmt` with a pinned Foundry version (**v1.3.6**) so formatting is
reproducible regardless of your local Foundry. Before committing:

```sh
make fmt         # format using the pinned version
make fmt-check   # verify (identical to the CI check)
```

`make fmt` installs Foundry v1.3.6 side-by-side on first run — it does not have to be
your default. The initial install switches your active Foundry to v1.3.6; run
`foundryup -u stable` to switch back.
