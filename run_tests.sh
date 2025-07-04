#!/bin/bash
set -e

for test in test/*.test.mo; do
  echo "=> Running $test"
  # Remove dirname and .test.mo
  test_name=$(basename $test .test.mo)
  mops test $test_name
done