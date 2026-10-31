#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

set -eu

if [ "$#" -ne 3 ] && [ "$#" -ne 4 ]; then
	printf 'Usage: check-linkage LDD NM EXECUTABLE [READELF]\n' >&2
	exit 2
fi

dependencies=$("$1" "$3")
case "$dependencies" in
	*libLLVM*)
		printf 'Unexpected LLVM linkage in %s:\n%s\n' "$3" "$dependencies" >&2
		exit 1
		;;
esac

if [ "$#" -eq 4 ]; then
	dynamic=$("$4" -d "$3")
	case "$dynamic" in
		*libLLVM*)
			printf 'Unexpected LLVM dynamic dependency in %s\n' "$3" >&2
			exit 1
			;;
	esac
fi

symbols=$("$2" "$3")
case "$symbols" in
	*astra_backend_llvm_* | *LLVM*)
		printf 'Unexpected LLVM/backend symbols in %s\n' "$3" >&2
		exit 1
		;;
esac
