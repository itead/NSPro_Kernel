#!/bin/sh
grep -n -B 8 -A 12 -m 5 -E 'error:|fatal error:|undefined reference|Error [0-9]' \
  /tmp/nspanel-kernel-build.log
