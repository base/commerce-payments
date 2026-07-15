# Foundry version CI uses for `forge fmt`. Pinned so formatting output is
# reproducible regardless of your default Foundry install.
FMT_VER := 1.3.6
FORGE_FMT := $(HOME)/.foundry/versions/v$(FMT_VER)/forge

.PHONY: fmt fmt-check

## Format all Solidity with the pinned Foundry version (installed side-by-side on first run).
fmt:
	@[ -x "$(FORGE_FMT)" ] || foundryup -i $(FMT_VER) >/dev/null
	@"$(FORGE_FMT)" fmt

## Verify formatting - identical to the CI check.
fmt-check:
	@[ -x "$(FORGE_FMT)" ] || foundryup -i $(FMT_VER) >/dev/null
	@"$(FORGE_FMT)" fmt --check
