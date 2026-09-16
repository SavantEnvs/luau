#!/usr/bin/env bash
#
# mayhem/build.sh — build luau fuzz harnesses and test suite.
# Runs inside the commit image as `mayhem` in /mayhem.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/usr/local/lib/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

INCLUDES="-ICommon/include -IAst/include -ICompiler/include -IAnalysis/include -IVM/include"

# ── Step 1: sanitized build — libs + luau-analyze ──────────────────────────
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

# ── Step 2: fuzz harnesses ─────────────────────────────────────────────────
LIBS="build-san/libLuau.Analysis.a build-san/libLuau.Compiler.a build-san/libLuau.Ast.a build-san/libLuau.VM.a"

# Compile standalone main as C so LLVMFuzzerTestOneInput keeps C linkage
"$CC" $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o

for t in compiler format linter number parser transpiler typeck; do
    "$CXX" -std=c++17 -include bits/stdc++.h $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
        $INCLUDES "fuzz/${t}.cpp" $LIBS \
        -o "/mayhem/fuzz-${t}"

    "$CXX" -std=c++17 -include cstdint $SANITIZER_FLAGS $DEBUG_FLAGS \
        $INCLUDES "fuzz/${t}.cpp" /tmp/standalone_main.o $LIBS \
        -o "/mayhem/fuzz-${t}-standalone"
done

# ── Step 3: test suite — normal flags (no sanitizers) ─────────────────────
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
