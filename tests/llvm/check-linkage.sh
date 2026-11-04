#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

set -eu

if [ "$#" -ne 5 ]; then
	printf 'Usage: check-linkage LDD NM READELF LLVM_CONFIG EXECUTABLE\n' >&2
	exit 2
fi

case "$("$4" --version)" in
	23.*) ;;
	*)
		printf 'Expected qualified LLVM 23\n' >&2
		exit 1
		;;
esac

dependencies=$("$1" "$5")
count=0
resolved=
while read -r library arrow candidate rest; do
	case "$library" in
		libLLVM*)
			[ "$arrow" = '=>' ] || exit 1
			count=$((count + 1))
			resolved=$candidate
			;;
	esac
done <<EOF
$dependencies
EOF
if [ "$count" -ne 1 ]; then
	printf 'Expected exactly one shared LLVM in %s:\n%s\n' "$5" "$dependencies" >&2
	exit 1
fi
expected=$("$4" --link-shared --libfiles core analysis)
# The shell's file-identity check follows symlinks without another host tool.
if [ ! "$resolved" -ef "$expected" ]; then
	printf 'LLVM library differs from llvm-config: %s versus %s\n' "$resolved" "$expected" >&2
	exit 1
fi

dynamic=$("$3" -d "$5")
needed=0
while IFS= read -r line; do
	case "$line" in
		*NEEDED*libLLVM*) needed=$((needed + 1)) ;;
	esac
done <<EOF
$dynamic
EOF
if [ "$needed" -ne 1 ]; then
	printf 'Expected one direct LLVM dynamic dependency in %s\n' "$5" >&2
	exit 1
fi
symbols=$("$2" -D "$5")
case "$symbols" in
	*LLVMContextCreate*LLVMVerifyModule*) ;;
	*)
		printf 'Missing LLVM construction/verification imports in %s\n' "$5" >&2
		exit 1
		;;
esac
