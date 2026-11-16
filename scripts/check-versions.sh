#!/bin/sh
# Verifies that the default upstream version is identical everywhere it is defined.
set -e
cd "$(dirname "$0")/.." || exit 1

dockerfile=$(sed -n 's/^ARG GAELD_VERSION=//p' Dockerfile)
template=$(sed -n 's/^GAELD_VERSION=//p' .env.template)
compose_args=$(sed -n 's/.*GAELD_VERSION: \${GAELD_VERSION:-\(v[0-9.]*\)}.*/\1/p' compose.yaml)
compose_image=$(sed -n 's/.*gaeld-deploy:\${GAELD_VERSION:-\(v[0-9.]*\)}.*/\1/p' compose.yaml)
readme=$(sed -n 's/^| `GAELD_VERSION` | `\(v[0-9.]*\)` |.*/\1/p' README.md)

status=0
for pair in "Dockerfile:$dockerfile" ".env.template:$template" "compose.yaml (build arg):$compose_args" \
            "compose.yaml (image tag):$compose_image" "README.md (options table):$readme"; do
    name=${pair%%:*}; value=${pair#*:}
    printf '%-28s %s\n' "$name" "${value:-<missing>}"
    [ "$value" = "$dockerfile" ] && [ -n "$value" ] || status=1
done
[ "$status" -eq 0 ] || { echo "ERROR: the default GAELD_VERSION differs between files. Use scripts/bump-upstream.sh." >&2; exit 1; }

note=$(sed -n 's/^\*\*Known upstream bug (\(v[0-9.]*\)).*/\1/p' README.md)
[ -z "$note" ] || [ "$note" = "$dockerfile" ] || \
    echo "WARNING: the README 'Known upstream bug' note was written for $note, the default is $dockerfile. Re-check it." >&2
echo "OK: default upstream version is $dockerfile"
