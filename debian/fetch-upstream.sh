#!/bin/sh
# KubeOS metrics-server: fetch the pinned upstream binary at build time.
#
# WHY    The binary is 80 MB and upstream publishes no Debian package. Committing it to git
#        would bloat the repository for ever; fetching it at build time with a pinned SHA256
#        gives the same reproducibility (a changed or truncated download fails the build) and
#        keeps the repository small. This is the logic build hook 9027 used, moved here.
# SAFE   Writes only into the given directory, and only after the checksum matches.
set -eu

DEST=${1:?usage: fetch-upstream.sh <directory>}
VERSION=${METRICS_SERVER_VERSION:-v0.8.0}
# Measured from metrics-server-linux-amd64 v0.8.0 on 2026-11-11 (upstream ships no
# checksum file). Re-measure and bump both values together when VERSION moves.
SHA256=${METRICS_SERVER_SHA256:-be3b876eea1350628b43b9d661be1c98832cf2ca22ebbbe59f4bd9e01445d0df}
URL="https://github.com/kubernetes-sigs/metrics-server/releases/download/${VERSION}/metrics-server-linux-amd64"

log() { printf 'fetch-upstream: %s\n' "$*"; }
die() { printf 'fetch-upstream: ERROR: %s\n' "$*" >&2; exit 1; }

install -d "$DEST"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

log "fetching $URL"
i=0
until curl -fsSL --retry 3 --retry-delay 5 -o "$WORK/metrics-server" "$URL"; do
    i=$((i + 1))
    [ "$i" -ge 3 ] && die "could not download $URL"
    log "retry $i/3"
done

GOT=$(sha256sum "$WORK/metrics-server" | cut -d' ' -f1)
[ "$GOT" = "$SHA256" ] || die "checksum mismatch for $VERSION:
    expected $SHA256
    got      $GOT
    If this is a deliberate version bump, update METRICS_SERVER_SHA256 and the changelog."

install -m 0755 "$WORK/metrics-server" "$DEST/metrics-server"
[ "$("$DEST/metrics-server" --version 2>/dev/null | head -1 | grep -c "$VERSION")" = 1 ] \
    || log "note: the binary did not print its version; checksum is what proves it"
log "installed $VERSION into $DEST"
