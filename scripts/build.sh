#!/bin/sh

set -e
set -u

export TOP=${TOP:-$(git rev-parse --show-toplevel)}
export PATH="$(stack path --local-bin)${PATH:+:$PATH}"

MAKE="make -O -j --directory $TOP"
$MAKE clean
$MAKE k-frontend
$MAKE coverage_report haskell_documentation
