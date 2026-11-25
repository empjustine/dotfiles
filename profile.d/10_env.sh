#!/bin/sh
# 10_env.sh — small environment switches that are neither supply-chain policy
# nor PATH (DR-005, DR-011, DR-038).
#
# Gate: none — env-only, so every shell and every interactivity; it runs before
# 20_core.bash so a system rc that reads these sees them.
# Side effect: exports only — no files, no forks.

if [ -d "${HOME}/Android/Sdk" ]; then
	ANDROID_HOME="${HOME}/Android/Sdk"
	export ANDROID_HOME
fi

# Cosmetic / behaviour switches, kept out of 70_moratorium.sh (release-age
# windows) and 72_hardening.sh (refusals): nothing here is a policy, so a
# reader should not have to decide whether it is.
NPM_CONFIG_FUND="false"
PIP_DISABLE_PIP_VERSION_CHECK=1
PYTHONDONTWRITEBYTECODE=1
# Ruff otherwise writes .ruff_cache into every project root. A pre-set
# RUFF_CACHE_DIR (an explicit project choice) wins.
RUFF_CACHE_DIR="${RUFF_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ruff}"
UV_INIT_BARE="1"
export NPM_CONFIG_FUND PIP_DISABLE_PIP_VERSION_CHECK PYTHONDONTWRITEBYTECODE RUFF_CACHE_DIR UV_INIT_BARE
