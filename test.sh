#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════════════════
# LiF:YO Docker — Local sanity tests
# Run before committing: ./test.sh
# ══════════════════════════════════════════════════════════════════════════════

SKIP_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --no-build) SKIP_BUILD=true ;;
    esac
done

PASS=0
FAIL=0

run_test() {
    local name="$1"
    shift
    printf "  %-40s" "${name}"
    if output=$("$@" 2>&1); then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        echo "    ${output}" | head -5
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "=== LiF:YO Docker — Sanity Tests ==="
echo ""

# ── Syntax checks ───────────────────────────────────────────────────────────
echo "Syntax checks:"
run_test "entrypoint.sh bash syntax" bash -n entrypoint.sh
run_test "docker-compose.yml valid" docker compose config -q
run_test "docker-compose.prod.yml valid" docker compose -f docker-compose.prod.yml config -q

# ── Shellcheck (if installed) ───────────────────────────────────────────────
if command -v shellcheck &>/dev/null; then
    echo ""
    echo "Shell linting:"
    run_test "entrypoint.sh shellcheck" shellcheck -e SC2034,SC2046,SC2086 -s bash entrypoint.sh
else
    echo ""
    echo "Shell linting: SKIPPED (install shellcheck for shell linting)"
fi

# ── File checks ─────────────────────────────────────────────────────────────
echo ""
echo "File checks:"
run_test ".env.example exists" test -f .env.example
run_test "config_local.cs.template exists" test -f config_local.cs.template
run_test "world_1.xml.template exists" test -f world_1.xml.template
run_test "mariadb-custom.cnf exists" test -f mariadb-custom.cnf
run_test "LICENSE exists" test -f LICENSE
run_test ".gitignore exists" test -f .gitignore
run_test ".env not tracked by git" bash -c '! git ls-files --error-unmatch .env 2>/dev/null'

# ── Env var consistency ─────────────────────────────────────────────────────
echo ""
echo "Env var consistency:"

# Check that every env var in docker-compose.yml has a corresponding entry in .env.example
run_test "compose vars in .env.example" bash -c '
    missing=""
    while IFS= read -r var; do
        if ! grep -q "^${var}=" .env.example; then
            # Skip internal vars not meant for .env
            case "$var" in DB_HOST|DB_PORT|DB_USER|DB_PASSWORD|DB_NAME|GAME_PORT_PLUS1|GAME_PORT_PLUS2|MARIADB_*) continue;; esac
            missing="${missing} ${var}"
        fi
    done < <(grep -oP "^\s+[A-Z_]+(?=:)" docker-compose.yml | tr -d " ")
    if [ -n "$missing" ]; then
        echo "Missing from .env.example:${missing}"
        exit 1
    fi
'

# ── Template variable checks ───────────────────────────────────────────────
run_test "template vars are exported" bash -c '
    missing=""
    for var in $(grep -oP "\\\$\{(\w+)\}" world_1.xml.template | grep -oP "\w+" | sort -u); do
        if ! grep -q "export.*${var}" entrypoint.sh; then
            missing="${missing} ${var}"
        fi
    done
    if [ -n "$missing" ]; then
        echo "Not exported in entrypoint.sh:${missing}"
        exit 1
    fi
'

# ── Docker build test ─────────────────────────────────────────────────────
if [ "${SKIP_BUILD}" = "false" ]; then
    echo ""
    echo "Docker build:"
    run_test "docker image builds" docker compose build
else
    echo ""
    echo "Docker build: SKIPPED (--no-build)"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
echo ""

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
