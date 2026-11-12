#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# perl -pi behaves the same on macOS and Linux, unlike sed -i (BSD vs GNU).
echo "Copying and patching WebMinidisc's interface declarations..."
cp webminidisc/src/services/interfaces/himd.ts webminidisc/src/services/interfaces/netmd.ts src/wmd/original/services/interfaces/
for x in src/wmd/original/services/interfaces/*
do
    perl -pi -e '
        print "// This file has been auto-generated! DO NOT EDIT!\n" if $. == 1;
        s/^import Worker(.*)? from \x27[^\x27]+\x27;/const Worker$1 = null as any;/;
        s/import\.meta\.url/""/g;
    ' "$x"
done
