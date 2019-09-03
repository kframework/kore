#!/usr/bin/env bash

set -exuo pipefail

export TOP=${TOP:-$(git rev-parse --show-toplevel)}

source $TOP/scripts/run-on-haskell.include.sh

stack install stylish-haskell
export PATH=$(stack path --bin-path)

runOnHaskellFiles "$TOP" .build/kore/bin/stylish-haskell -i
