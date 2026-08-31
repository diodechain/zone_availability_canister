#!/bin/bash
set -e

# PocketIC in mops test does not complete live HTTPS outcalls; skip until
# HTTP outcall mocking is wired for CI.
SKIP_TESTS="oracle"

for test in test/*.test.mo; do
  test_name=$(basename "$test" .test.mo)
  for skip in $SKIP_TESTS; do
    if [ "$test_name" = "$skip" ]; then
      echo "=> Skipping $test (requires live HTTP outcalls)"
      continue 2
    fi
  done
  echo "=> Running $test"
  mops test "$test_name"
done
