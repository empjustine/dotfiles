#!/bin/sh
# 70_moratorium.sh — dependency moratorium: release-age windows only (DR-005,
# DR-011).
#
# Gate: none; env-only and host-agnostic — the policy travels with the shell
# instead of being written into each tool's config (DR-011).
# Side effect: exports only. Install-time refusals live in 72_hardening.sh and
# the cosmetic switches in 10_env.sh (DR-038 split).

# @see https://mise.jdx.dev/configuration/settings.html#minimum_release_age
MISE_MINIMUM_RELEASE_AGE="24h"
export MISE_MINIMUM_RELEASE_AGE

# npm/pnpm read these case-insensitively; the lowercase spelling is the one
# that survives both. pnpm counts minutes: 4320 = 3 days.
npm_config_min_release_age="3"
pnpm_config_minimum_release_age="4320"
export npm_config_min_release_age pnpm_config_minimum_release_age

# pip has no release-age knob of its own; uv carries the window for both.
UV_EXCLUDE_NEWER="3 days"
export UV_EXCLUDE_NEWER
