#!/bin/sh
LOG=$(ls -1t ./nspanel-kernel-build-*.log | sed -n '1p')

git status --short
git commit -m "Add NSPanel kernel build log" -- "$LOG"
git push origin fix/rockchip-gem-zero-size
