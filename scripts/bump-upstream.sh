#!/bin/sh
# Usage: scripts/bump-upstream.sh v3.9.1
# Sets the default upstream release in all files. Review, commit, then tag the release as <version>-1 (see README).
set -e
cd "$(dirname "$0")/.." || exit 1
version="$1"
printf '%s' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Usage: $0 vX.Y.Z" >&2; exit 1; }
if [ "${SKIP_REMOTE_CHECK:-}" != "1" ]; then
    curl -fsIL "https://github.com/Scanix/Gaeld/releases/download/$version/gaeld-ce-$version.tar.gz.sha256" >/dev/null \
        || { echo "ERROR: upstream release $version (or its checksum file) does not exist" >&2; exit 1; }
fi
sed -i.bak "s|^ARG GAELD_VERSION=.*|ARG GAELD_VERSION=$version|" Dockerfile
sed -i.bak "s|^GAELD_VERSION=.*|GAELD_VERSION=$version|" .env.template
sed -i.bak "s|\${GAELD_VERSION:-v[0-9.]*}|\${GAELD_VERSION:-$version}|g" compose.yaml
sed -i.bak "s#^| \`GAELD_VERSION\` | \`v[0-9.]*\`#| \`GAELD_VERSION\` | \`$version\`#" README.md
rm -f Dockerfile.bak .env.template.bak compose.yaml.bak README.md.bak
./scripts/check-versions.sh
echo
echo "Next: read the upstream release notes, run scripts/smoke-test.sh, commit, then tag and push:"
echo "  git tag $version-1 && git push origin $version-1"
