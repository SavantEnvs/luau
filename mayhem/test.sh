#!/usr/bin/env bash
#
# mayhem/test.sh — run luau's doctest suite (built by mayhem/build.sh).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

RUNNER="build-tests/Luau.UnitTest"
if [ ! -x "$RUNNER" ]; then
    echo "ERROR: test runner $RUNNER missing — build.sh should have produced it" >&2
    exit 1
fi

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

OUTPUT=$("$RUNNER" 2>&1); RC=$?
echo "$OUTPUT"

# Parse doctest summary: "[doctest] test cases:  N | P passed | F failed | S skipped"
PASSED=$(echo "$OUTPUT" | grep -oP '\d+(?= passed)' | tail -1 || echo 0)
FAILED=$(echo "$OUTPUT" | grep -oP '\d+(?= failed)' | tail -1 || echo 0)
SKIPPED=$(echo "$OUTPUT" | grep -oP '\d+(?= skipped)' | tail -1 || echo 0)

: "${PASSED:=0}" "${FAILED:=0}" "${SKIPPED:=0}"

# Oracle: runner must exit 0 AND actually run tests. Without this, a
# crash or a reward-hacking no-op that never prints the doctest summary
# defaults to tests=0/failed=0 and silently passes emit_ctrf's check
# (PORTING.md step 8: "ran the corpus, exit 0" is NOT acceptable).
if [ "$RC" -ne 0 ]; then
    echo "ERROR: $RUNNER exited $RC" >&2
    emit_ctrf "doctest" "$PASSED" "$FAILED" "$SKIPPED"
    exit 1
fi
if [ "$(( PASSED + FAILED + SKIPPED ))" -eq 0 ]; then
    echo "ERROR: no parseable doctest summary from $RUNNER — test oracle vacuous" >&2
    emit_ctrf "doctest" 0 1 0
    exit 1
fi

emit_ctrf "doctest" "$PASSED" "$FAILED" "$SKIPPED"
