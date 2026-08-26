#!/usr/bin/env bash
#
# pin-guard — verify the checksum-coupled pins in the dev_workstation role.
#
# Each <tool>_version in ansible/roles/dev_workstation/defaults/main.yml has a
# sibling <tool>_sha256 that is the trust anchor for ansible's get_url. A
# version-only bump — an unattended Renovate PR, or a hand edit that forgets
# the second line — leaves the digest pointing at the previous release, and the
# role can no longer download its tools. This script resolves the digest
# upstream publishes for the *pinned* version and compares it against what is
# committed, so such a change fails CI instead of merging.
#
# Usage: scripts/pin-guard.sh [path/to/defaults/main.yml]
#
# Exit 0 = every coupled pair agrees with upstream. Exit 1 = a mismatch, a
# missing pin, or an unresolvable upstream asset. Failing on an unresolvable
# asset is deliberate: a yanked or renamed release is exactly the case where
# the pin must not be trusted.

set -euo pipefail

DEFAULTS="${1:-ansible/roles/dev_workstation/defaults/main.yml}"
CURL_OPTS=(--silent --show-error --fail --location --max-time 30 --retry 3 --retry-delay 2)

status=0

value_of() {
  local key=$1 val
  val=$(sed -n -E "s/^${key}:[[:space:]]*\"?([^\"[:space:]]+)\"?[[:space:]]*\$/\1/p" "$DEFAULTS" | head -n1)
  if [ -z "$val" ]; then
    echo "::error::pin-guard: ${key} not found in ${DEFAULTS}"
    exit 1
  fi
  printf '%s' "$val"
}

compare() {
  local tool=$1 version=$2 committed=$3 upstream=$4
  if [ -z "$upstream" ]; then
    echo "::error::pin-guard: could not resolve the upstream sha256 for ${tool} ${version} — release asset missing, renamed, or unreachable"
    status=1
  elif [ "$committed" = "$upstream" ]; then
    echo "pin-guard: OK   ${tool} ${version} — committed sha256 matches upstream"
  else
    echo "::error::pin-guard: ${tool} ${version} sha256 mismatch — committed ${committed}, upstream ${upstream}. The *_version and its sibling *_sha256 must move together."
    status=1
  fi
}

echo "pin-guard: checking ${DEFAULTS}"

# --- sops: checksums.txt, row for the linux.amd64 binary the role downloads --
sops_version=$(value_of dev_workstation_sops_version)
sops_sha256=$(value_of dev_workstation_sops_sha256)
sops_asset="sops-v${sops_version}.linux.amd64"
sops_upstream=$(
  curl "${CURL_OPTS[@]}" \
    "https://github.com/getsops/sops/releases/download/v${sops_version}/sops-v${sops_version}.checksums.txt" \
    | awk -v asset="$sops_asset" '$2 == asset { print $1 }' | head -n1 || true
)
compare sops "$sops_version" "$sops_sha256" "$sops_upstream"

# --- uv: per-asset .sha256 sidecar for the linux x86_64 tarball -------------
uv_version=$(value_of dev_workstation_uv_version)
uv_sha256=$(value_of dev_workstation_uv_sha256)
uv_upstream=$(
  curl "${CURL_OPTS[@]}" \
    "https://github.com/astral-sh/uv/releases/download/${uv_version}/uv-x86_64-unknown-linux-gnu.tar.gz.sha256" \
    | awk '{ print $1 }' | head -n1 || true
)
compare uv "$uv_version" "$uv_sha256" "$uv_upstream"

exit "$status"
