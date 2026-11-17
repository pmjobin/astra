#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Short PR lane: authenticated seed emits and runs new native objects."""
import argparse
import json
from pathlib import Path

from common import ROOT, clean_environment, external, identify, require, run, sha, verify, write
from trust import seed_manifest


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('seed', 'library', 'library_receipt', 'output'):
		p.add_argument('--'+key.replace('_', '-'), type=Path, required=True)
	a = p.parse_args()
	manifest = seed_manifest(ROOT/'tools/ci/seed-linux.json')
	verify(a.seed, manifest)
	receipt = json.loads(a.library_receipt.read_text())
	verify(a.library, receipt['library'])
	require(receipt['archive_sha256'] == json.loads((ROOT/'tools/ci/llvm-linux.json').read_text())['archive']['sha256'], 'LLVM provenance mismatch')
	out = external(a.output)
	env = clean_environment()
	env['LD_LIBRARY_PATH'] = str(a.library.resolve().parent)
	help_text, _ = run([a.seed, '--help'], out/'help', env)
	require(b'Explicit sources form one program' in help_text, 'not an Astra seed')
	for mode in ('O0', 'O2'):
		obj, exe = out/(mode+'.o'), out/mode
		run([a.seed, '-c', '-'+mode, '-o', obj, ROOT/'tests/install/main.astra'], out/(mode+'-compile'), env)
		require(obj.read_bytes()[:5] == b'\x7fELF\x02', 'not a native ELF object')
		run(['cc', '-no-pie', obj, '-o', exe], out/(mode+'-link'), env)
		stdout, stderr = run([exe], out/(mode+'-run'), env)
		require(not stdout and not stderr, 'unexpected program streams')
	_, stderr = run([a.seed, '-c', '-o', out/'bad.o', ROOT/'tests/install/negative-type.astra'], out/'negative', env, expected=1)
	require(b'type' in stderr and not (out/'bad.o').exists(), 'negative did not refuse output')
	write(out/'result.json', dict(status='AUTHENTICATED_SEED_NATIVE_SMOKE_PASS', seed=identify(a.seed), library=identify(a.library), scope='PR bootstrap smoke only; current-source rebuild, installers, docs and full qualification are nightly gates'))


if __name__ == '__main__':
	main()
