#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay the pinned UBI 9 build-only seed link from the authenticated producer object."""
import argparse
import json
from pathlib import Path
import shlex
import subprocess

from bootstrap import PROVIDERS
from common import ROOT, clean_environment, external, identify, require, run, sha, verify, write
from copr_source import RHEL9_PROVENANCE, RHEL9_SEED_PATH, seed_contract
from system_llvm import audit_elf, discover, rhel9


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('producer', 'producer-receipt', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	pin, _, _ = seed_contract('rhel9')
	provenance = json.loads((ROOT/RHEL9_PROVENANCE).read_bytes())
	require(sha(a.producer_receipt) == provenance['producer_source_generation_sha256'], 'producer receipt hash mismatch')
	receipt = json.loads(a.producer_receipt.read_bytes())
	require(receipt['commit'] == provenance['producer_commit'], 'producer commit mismatch')
	require(receipt['compiler_object']['sha256'] == provenance['producer_object_sha256'], 'producer object pin mismatch')
	obj = verify(a.producer, receipt['compiler_object']).resolve()
	sources = receipt['source_manifest']['files']
	for name in receipt['compiler_sources']:
		verify(ROOT/name, sources[name])
	build, runtime = external(a.build), external(a.runtime)
	env = clean_environment()
	llvm = discover('rpm', runtime, env)
	require(rhel9(llvm['os_release']), 'seed link requires UBI/RHEL 9')
	common = ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror']
	providers = {}
	for name in PROVIDERS+['compiler/docs/host.c']:
		source = verify(ROOT/name, sources[name])
		output = build/(source.stem+'.o')
		flags = []
		if source.name == 'capi.c':
			flags = shlex.split(subprocess.check_output([llvm['config'], '--cflags'], text=True, env=env))
		if source.name == 'host.c':
			flags = ['-DASTRA_DOC_BUILD_SHA256="'+provenance['doc_build_sha256']+'"']
		run([*common, *flags, '-c', name, '-o', output], runtime/('provider-'+source.stem), env, cwd=ROOT)
		providers[name] = output
	seed = build/Path(RHEL9_SEED_PATH).name
	run(['cc', '-no-pie', obj, *providers.values(), '-Wl,--wrap=LLVMGetInstructionOpcode', llvm['library']['path'], '-o', seed], runtime/'link', env)
	run(['strip', '--strip-debug', seed], runtime/'strip', env)
	audit_elf(seed, llvm, runtime, env)
	run([seed, '--help'], runtime/'help', env)
	verify(seed, pin)
	write(runtime/'result.json', dict(seed=identify(seed), producer=identify(obj), source_commit=provenance['source_commit'], source_tree=provenance['source_tree'], llvm=llvm, providers={name:identify(path) for name, path in providers.items()}))
	print('PINNED_RHEL9_SEED_REPRODUCED', pin['sha256'])


if __name__ == '__main__':
	main()
