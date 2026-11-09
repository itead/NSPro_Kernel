#!/bin/sh
ARCH=arm64 CROSS_COMPILE=aarch64-unknown-linux-gnu- make -j"$(nproc)"   HOSTCFLAGS="-Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89 -fcommon"   Image dtbs modules 2>&1 | grep -v CC | tee /tmp/nspanel-kernel-build.log &
