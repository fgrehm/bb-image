# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim worker vm exedev worker-vm

say "the baked trust store excludes the revoked eMudhra and Comodo roots"
crun <<'SH'
set -eu

bundle=/etc/ssl/certs/ca-certificates.crt
subjects="$(openssl crl2pkcs7 -nocrl -certfile "$bundle" | openssl pkcs7 -print_certs -noout)"
count="$(printf '%s\n' "$subjects" | grep -c '^subject=')"
# A missing or truncated bundle still parses, and would pass the absence test
# below. Anchor it to a plausible size instead of an exact count, so routine
# root-program churn does not fail the check.
[ "$count" -ge 100 ] || {
	echo "the trust store holds $count certificates; expected at least 100" >&2
	exit 1
}

# DSA-6572-1 removed these two after the eMudhra intermediate keys were shown
# to be recoverable. Other emSign and Comodo roots stay trusted, so the
# assertion is by certificate name, not by organization.
for revoked in 'emSign ECC Root CA - G3' 'AAA Certificate Services'; do
	if printf '%s\n' "$subjects" | grep -Fq "$revoked"; then
		echo "the trust store still contains the revoked $revoked root" >&2
		exit 1
	fi
done

echo "trust store carries $count certificates without the revoked roots"
SH
