#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""One fresh source generation in the RPM buildroot using only the approved seed."""
import argparse
import json
from pathlib import Path
import shutil
from types import SimpleNamespace

from bootstrap import LIBRARIES
from common import ROOT, clean_environment, external, identify, require, run, sha, verify, write
from copr_source import SEED, verify_source
from package import build_payload
from system_llvm import audit_payload, discover


def audit(stage):
	audit_payload(stage)
	private = stage/'usr/lib/astra'
	m = json.loads((private/'INSTALL.json').read_text())
	for name, pin in m['files'].items():
		verify(private/name, pin)
	for p in stage.rglob('*'):
		if p.is_file():
			require(sha(p) != SEED['sha256'], 'seed leaked into payload')
	print('SOURCE_RPM_PAYLOAD_AUDIT_PASS')


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--audit', type=Path)
	p.add_argument('--verify-only', action='store_true')
	p.add_argument('--commit')
	p.add_argument('--tree')
	for key in ('seed', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path)
	a = p.parse_args()
	if a.audit:
		audit(a.audit)
		return
	m = verify_source(a.commit, a.tree)
	seed = verify(a.seed, SEED)
	if a.verify_only:
		print('SOURCE_INPUTS_AUTHENTICATED', a.commit)
		return
	build, runtime = external(a.build), external(a.runtime)
	env = clean_environment()
	env['SOURCE_DATE_EPOCH'] = str(m['epoch'])
	llvm = discover('rpm', runtime, env)
	# Copy the exact seed only into the private build directory to set executable mode.
	tool = build/'bootstrap'
	shutil.copyfile(seed, tool)
	tool.chmod(0o755)
	run(['readelf', '-l', '-d', '-V', tool], runtime/'seed-elf', env)
	run(['ldd', tool], runtime/'seed-loader', env)
	run([tool, '--help'], runtime/'seed-execution', env)
	sources = sorted(n for n in m['files'] if n.startswith('compiler/') and n.endswith('.astra'))
	sources += ['lib/astra/'+n+'.astra' for n in LIBRARIES]
	require(sources and all(n in m['files'] for n in sources), 'incomplete compiler/library inputs')
	obj = build/'astrac-O2.o'
	require(not obj.exists(), 'stale object refused')
	run([tool, '-c', '-O2', '-o', obj, *sources], runtime/'compile-current-source', env, cwd=ROOT, timeout=18000)
	require(obj.read_bytes()[:5] == b'\x7fELF\x02', 'source generation did not produce ELF64')
	write(runtime/'source-generation.json', dict(commit=a.commit, tree=a.tree, seed=SEED, compiler_sources=sources, compiler_object=identify(obj), manifest_sha256=sha(ROOT/'SOURCE-MANIFEST.json'), source_manifest=m, llvm=llvm, qualification='DEVELOPMENT_UNQUALIFIED'))
	handoff = dict(source_commit=a.commit, package_commit=a.commit, package_tree=a.tree, products={'O2':dict(object_sha256=sha(obj))}, sources={n:r['sha256'] for n,r in m['files'].items() if n.startswith(('compiler/', 'lib/'))}, package_sources={n:r['sha256'] for n,r in m['files'].items()})
	write(runtime/'source-handoff.json', handoff)
	args = SimpleNamespace(object=obj, mode='O2', kind='rpm', development=True)
	stage = build_payload(args, handoff, build, runtime, env, llvm)
	provenance = stage/'usr/share/astra'
	shutil.copyfile(runtime/'source-generation.json', provenance/'SOURCE-BUILD.json')
	shutil.copyfile(runtime/'docs-build-identity.json', provenance/'DOCS-BUILD.json')
	# Resource records and commands survive in the binary package and COPR logs.
	shutil.copytree(runtime/'compile-current-source', provenance/'source-compilation')
	audit(stage)
	print('FRESH_SOURCE_GENERATION', a.commit, 'object', sha(obj), 'LLVM', llvm['version'], flush=True)
	print((runtime/'compile-current-source/time.txt').read_text(), flush=True)
	print((runtime/'compile-current-source/command.json').read_text(), flush=True)


if __name__ == '__main__':
	main()
