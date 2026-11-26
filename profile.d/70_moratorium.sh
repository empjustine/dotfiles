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
# that survives both. pnpm counts minutes: 1440 = 1 day. npm/pnpm sit at 1 day
# while mise stays 24h and uv 3 days (DECISIONS.md DR-005's status notes): a
# consuming repo's gate pins have to reach what its other host already runs,
# and a 3-day window refused a release under 2 days old.
npm_config_min_release_age="1"
pnpm_config_minimum_release_age="1440"
export npm_config_min_release_age pnpm_config_minimum_release_age

# pip has no release-age knob of its own; uv carries the window for both.
UV_EXCLUDE_NEWER="3 days"
export UV_EXCLUDE_NEWER
