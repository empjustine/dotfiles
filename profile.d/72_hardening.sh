#!/bin/sh
# 72_hardening.sh — install-time refusals (DR-006, DR-011).
#
# Gate: none; env-only. Side effect: exports only.
# Kept apart from 70_moratorium.sh on purpose: a release-age window *delays* an
# install, this file *refuses* one — different failure modes, different
# switches to explain (DR-038).

# No lifecycle scripts: preinstall/postinstall is the common supply-chain
# vector. Packages that need one need an explicit opt-in.
NPM_CONFIG_IGNORE_SCRIPTS="true"

# pip installs only inside a virtualenv.
PIP_REQUIRE_VIRTUALENV="true"
export NPM_CONFIG_IGNORE_SCRIPTS PIP_REQUIRE_VIRTUALENV
