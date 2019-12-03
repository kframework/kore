#!/usr/bin/env bash

set -exuo pipefail

TOP=${TOP:-$(git rev-parse --show-toplevel)}
KWASM_DIR=$TOP/wasm-semantics
export KWASM_DIR

# Prefer to use Kore master
PATH="$TOP/.build/kore/bin${PATH:+:}$PATH"
export PATH
rm -f .build/k/bin/kore-*

mkdir -p $(dirname $KWASM_DIR)

rm -rf $KWASM_DIR
git clone --recurse-submodules 'https://github.com/kframework/wasm-semantics' $KWASM_DIR --branch 'master'

cd $KWASM_DIR

# Display the HEAD commit on evm-semantics for the log.
git show -s HEAD

# Use the K Nightly build from the Kore integration tests.
rm -rf deps/k/k-distribution/target/release/k
mkdir -p deps/k/k-distribution/target/release
ln -s $TOP/.build/k deps/k/k-distribution/target/release

make build-haskell -B

env KORE_EXEC_OPTS="--rts-statistics $TOP/kwasm-simple-arithmetic-spec-stats.json" \
    make TEST_SYMBOLIC_BACKEND=haskell tests/proofs/simple-arithmetic-spec.k.prove

env KORE_EXEC_OPTS="--rts-statistics $TOP/kwasm-loops-spec-stats.json" \
    make TEST_SYMBOLIC_BACKEND=haskell tests/proofs/loops-spec.k.prove

env KORE_EXEC_OPTS="--rts-statistics $TOP/kwasm-memory-symbolic-type-spec-stats.json" \
    make TEST_SYMBOLIC_BACKEND=haskell tests/proofs/memory-symbolic-type-spec.k.prove

env KORE_EXEC_OPTS="--rts-statistics $TOP/kwasm-locals-spec-stats.json" \
    make TEST_SYMBOLIC_BACKEND=haskell tests/proofs/locals-spec.k.prove
