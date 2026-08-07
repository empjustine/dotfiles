#!/bin/zsh

if [ -n "$ZSH_VERSION" ]; then
	case "$-" in
		*i*)
			# Allowlisted atuin locations, in priority order. An arbitrary
			# atuin resolved from $PATH is intentionally NOT trusted. Termux
			# and the system "local" atuin are last (fallback only). zsh has
			# native preexec/precmd hooks, so no bash-preexec is needed.
			atuin_bin=""
			mise_attempted=""
			for cand in \
				"${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims/atuin" \
				"$HOME/.local/share/mise/shims/atuin" \
				"${LOCALAPPDATA:-$HOME/AppData/Local}/mise/shims/atuin.exe" \
				"${MISE_SYSTEM_DATA_DIR:-/usr/local/share/mise}/shims/atuin" \
				/usr/local/share/mise/shims/atuin \
				/home/linuxbrew/.linuxbrew/bin/atuin \
				"${SCOOP:-$HOME/scoop}/shims/atuin.exe" \
				/data/data/com.termux/files/usr/bin/atuin \
				/usr/bin/atuin ; do
				# Win32 (Git Bash/MSYS2): the Windows-only candidates above
				# (LOCALAPPDATA mise shims, scoop shims) embed the `.exe`
				# spelling directly — PE shims there have no extensionless
				# twin, so a plain `-x` probe suffices; POSIX candidates stay
				# bare.
				[ -x "$cand" ] || continue
				# A mise shim can exist yet have no version selected
				# (`mise ERROR No version is set for shim: atuin`, exit 1).
				# Verify the binary actually runs before trusting it.
				if ! "$cand" --version >/dev/null 2>&1; then
					case "$cand" in
						*/mise/shims/atuin*)
							if [ -z "$mise_attempted" ] && command -v mise >/dev/null 2>&1; then
								mise use -g atuin >/dev/null 2>&1
								mise_attempted=1
							fi
							"$cand" --version >/dev/null 2>&1 || continue
							;;
						*)
							continue
							;;
					esac
				fi
				atuin_bin="$cand"
				break
			done
			unset cand mise_attempted

			if [ -n "$atuin_bin" ]; then
				# shellcheck source=/dev/null
				eval "$("$atuin_bin" init zsh --disable-up-arrow || true)"
			fi

			unset atuin_bin
			;;
	esac
else
	printf '%s\n' "dotfiles: zsh-only snippet sourced under a non-zsh shell; skipping" >&2
fi
