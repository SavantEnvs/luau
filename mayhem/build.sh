#!/usr/bin/env bash
#
# mayhem/build.sh — build luau-analyze (sanitized) and the test suite.
# Runs inside the commit image as `mayhem` in /mayhem.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# ── Step 1: sanitized build — luau-analyze ─────────────────────────────────
mkdir -p build-san
cmake -S . -B build-san \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_FLAGS="-fsanitize=fuzzer-no-link $SANITIZER_FLAGS $DEBUG_FLAGS" \
    -DCMAKE_CXX_FLAGS="-fsanitize=fuzzer-no-link -include bits/stdc++.h $SANITIZER_FLAGS $DEBUG_FLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS" \
    -DLUAU_BUILD_CLI=ON \
    -DLUAU_BUILD_TESTS=OFF \
    -DLUAU_BUILD_WEB=OFF
cmake --build build-san -j"$MAYHEM_JOBS" \
    --target Luau.Analyze.CLI \
    --target Luau.Compiler \
    --target Luau.VM

cp build-san/luau-analyze /mayhem/luau-analyze

# ── Step 2: test suite — normal flags (no sanitizers) ─────────────────────
mkdir -p build-tests
cmake -S . -B build-tests \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_FLAGS="${COVERAGE_FLAGS}" \
    -DCMAKE_CXX_FLAGS="-include bits/stdc++.h ${COVERAGE_FLAGS}" \
    -DLUAU_BUILD_CLI=OFF \
    -DLUAU_BUILD_TESTS=ON \
    -DLUAU_BUILD_WEB=OFF
cmake --build build-tests -j"$MAYHEM_JOBS" --target Luau.UnitTest
