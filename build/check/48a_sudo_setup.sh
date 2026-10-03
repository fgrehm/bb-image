# Partials sourced by build/check.sh via build/check/lib.sh.
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full

# Mutates only a disposable container, with synthetic passwords.
say "human password setup retires bootstrap sudo, with failure recovery"
crun --user root <<'SH'
set -eu
helper=/usr/local/sbin/bb-set-password
bootstrap=/etc/sudoers.d/zz-bb-bootstrap

if printf 'ProofMismatch42!\nOtherProof43!\n' | runuser -u developer -- sudo -n "$helper"; then
	echo "mismatched password unexpectedly succeeded" >&2
	exit 1
fi
[ -f "$bootstrap" ]
runuser -u developer -- sudo -n -k true
if runuser -u developer -- sudo -n "$helper" </dev/null; then
	echo "EOF unexpectedly succeeded" >&2
	exit 1
fi
[ -f "$bootstrap" ]

# Refuse a broken policy before changing the password.
printf '%s\n' 'invalid sudoers ???' > /etc/sudoers.d/zzz-test
chmod 0440 /etc/sudoers.d/zzz-test
if "$helper" </dev/null; then exit 1; fi
[ "$(passwd -S developer | awk '{print $2}')" = L ]
rm /etc/sudoers.d/zzz-test

# Ordinary passwd does not switch sudo policy; only the setup helper does.
printf 'DisposableProof42!\nDisposableProof42!\n' | runuser -u developer -- sudo -n passwd developer
[ -f "$bootstrap" ]
runuser -u developer -- sudo -n -k true

# Detect another broad passwordless grant and restore bootstrap for recovery.
printf '%s\n' 'developer ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/zzz-test
chmod 0440 /etc/sudoers.d/zzz-test
if printf 'DisposableProof42!\nDisposableProof42!\n' | runuser -u developer -- sudo -n "$helper"; then
	echo "competing passwordless policy unexpectedly accepted" >&2
	exit 1
fi
[ -f "$bootstrap" ]
runuser -u developer -- sudo -n -k true
rm /etc/sudoers.d/zzz-test

printf 'DisposableProof42!\nDisposableProof42!\n' | runuser -u developer -- sudo -n "$helper"
[ ! -e "$bootstrap" ]
visudo -c
if runuser -u developer -- sudo -n -k true; then
	echo "passwordless sudo survived setup" >&2
	exit 1
fi
if printf 'WrongProof42!\nWrongProof42!\nWrongProof42!\n' | runuser -u developer -- sudo -S -k true; then
	echo "incorrect password authenticated" >&2
	exit 1
fi
printf 'DisposableProof42!\n' | runuser -u developer -- sudo -S -k true

# Repeat setup after bootstrap is gone, authenticated with the current password.
printf 'DisposableProof42!\nReplacementProof43!\nReplacementProof43!\n' | runuser -u developer -- sudo -S -k "$helper"
[ ! -e "$bootstrap" ]
printf 'ReplacementProof43!\n' | runuser -u developer -- sudo -S -k true
SH

say "fresh container restores bootstrap access"
crun --user developer <<'SH'
set -eu
[ -f /etc/sudoers.d/zz-bb-bootstrap ]
sudo -n -k true
SH
