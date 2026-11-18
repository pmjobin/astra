#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""One fresh source generation in the RPM buildroot using only the approved seed."""
import argparse
import json
from pathlib import Path
import shutil
import sys
from types import SimpleNamespace

from bootstrap import LIBRARIES, PROVIDERS
from common import ROOT, clean_environment, external, identify, require, run, sha, verify, write
from copr_source import SEED, seed_contract, verify_source
from package import build_payload
from system_llvm import audit_elf, audit_payload, discover, rhel9


def audit(stage):
	audit_payload(stage)
	private = stage/'usr/lib/astra'
	m = json.loads((private/'INSTALL.json').read_text())
	if 'python' in m:
		require(sys.executable == m['python'], 'audit interpreter differs from packaged Python')
		require((stage/'usr/bin/astrac').read_bytes().splitlines()[0] == ('#!'+m['python']+' -I').encode(), 'wrong launcher interpreter')
		if m['python'] == '/usr/bin/python3.11':
			for script in (stage/'usr/share/astra/tutorial').rglob('*.py'):
				require(script.read_bytes().splitlines()[0] == b'#!/usr/bin/python3.11', 'wrong tutorial interpreter: '+str(script))
			require((stage/'usr/share/astra/install/smoke.py').read_bytes().splitlines()[0] == b'#!/usr/bin/python3.11', 'wrong smoke interpreter')
	for name, pin in m['files'].items():
		verify(private/name, pin)
	seeds = {SEED['sha256']}
	if rhel9(m['system_llvm']['os_release']):
		seeds.add(seed_contract('rhel9')[0]['sha256'])
	for p in stage.rglob('*'):
		if p.is_file():
			require(sha(p) not in seeds, 'seed leaked into payload')
	print('SOURCE_RPM_PAYLOAD_AUDIT_PASS')


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--audit', type=Path)
	p.add_argument('--verify-only', action='store_true')
	p.add_argument('--commit')
	p.add_argument('--tree')
	p.add_argument('--rpm-version')
	for key in ('seed', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path)
	a = p.parse_args()
	require(sys.version_info >= (3, 11), 'Python 3.11 or newer required')
	if a.audit:
		audit(a.audit)
		return
	m = verify_source(a.commit, a.tree)
	seed = verify(a.seed, m['seed'])
	if a.verify_only:
		print('SOURCE_INPUTS_AUTHENTICATED', a.commit)
		return
	build, runtime = external(a.build), external(a.runtime)
	env = clean_environment()
	env['SOURCE_DATE_EPOCH'] = str(m['epoch'])
	llvm = discover('rpm', runtime, env)
	rhel_target = rhel9(llvm['os_release'])
	require(rhel_target == (m.get('target') == 'rhel9'), 'seed target differs from RPM buildroot')
	python = '/usr/bin/python3' if llvm['os_release']['ID'].strip('"') == 'fedora' else '/usr/bin/python3.11'
	require(sys.executable == python, 'source build must run with '+python)
	# Copy the exact seed only into the private build directory to set executable mode.
	tool = build/'bootstrap'
	shutil.copyfile(seed, tool)
	tool.chmod(0o755)
	run(['readelf', '-l', '-d', '-V', tool], runtime/'seed-elf', env)
	run(['ldd', tool], runtime/'seed-loader', env)
	if rhel_target:
		audit_elf(tool, llvm, runtime/'seed-link-audit', env)
	run([tool, '--help'], runtime/'seed-execution', env)
	sources = sorted(n for n in m['files'] if n.startswith('compiler/') and n.endswith('.astra'))
	sources += ['lib/astra/'+n+'.astra' for n in LIBRARIES]
	require(sources and all(n in m['files'] for n in sources), 'incomplete compiler/library inputs')
	obj = build/'astrac-O2.o'
	require(not obj.exists(), 'stale object refused')
	run([tool, '-c', '-O2', '-o', obj, *sources], runtime/'compile-current-source', env, cwd=ROOT, timeout=18000)
	require(obj.read_bytes()[:5] == b'\x7fELF\x02', 'source generation did not produce ELF64')
	write(runtime/'source-generation.json', dict(commit=a.commit, tree=a.tree, seed=m['seed'], compiler_sources=sources, compiler_object=identify(obj), manifest_sha256=sha(ROOT/'SOURCE-MANIFEST.json'), source_manifest=m, llvm=llvm, qualification='DEVELOPMENT_UNQUALIFIED'))
	provider_sources = PROVIDERS+['compiler/docs/host.c', 'compiler/driver/doc-guard.c', 'compiler/driver/doc-launch.c']
	handoff = dict(source_commit=a.commit, package_commit=a.commit, package_tree=a.tree, products={'O2':dict(object_sha256=sha(obj))}, sources={n:m['files'][n]['sha256'] for n in sources+provider_sources}, package_sources={n:r['sha256'] for n,r in m['files'].items()})
	write(runtime/'source-handoff.json', handoff)
	args = SimpleNamespace(object=obj, handoff=runtime/'source-handoff.json', mode='O2', kind='rpm', development=True, package_version=a.rpm_version)
	stage = build_payload(args, handoff, build, runtime, env, llvm, python=python)
	provenance = stage/'usr/share/astra'
	disclosure = provenance/'DEV-UNQUALIFIED.txt'
	disclosure.write_text(disclosure.read_text().replace('Unsigned development package.', 'COPR development package; verify its repository RPM signature separately.'))
	generation = json.loads((runtime/'source-generation.json').read_text())
	generation.update(build_python=dict(executable=python, version=sys.version), provider_objects={p.name:identify(p) for p in build.glob('*.o') if p != obj}, installed_images=json.loads((stage/'usr/lib/astra/INSTALL.json').read_text())['files'], signing_scope='Payload is unsigned at build time; COPR repository RPM signing must be verified independently after publication.')
	if rhel_target:
		require(set(generation['provider_objects']) == {Path(name).stem+'.o' for name in provider_sources}, 'incomplete RHEL 9 native provider set')
	write(runtime/'source-generation.json', generation)
	shutil.copyfile(runtime/'source-generation.json', provenance/'SOURCE-BUILD.json')
	shutil.copyfile(runtime/'docs-build-identity.json', provenance/'DOCS-BUILD.json')
	# Resource records and commands survive in the binary package and COPR logs.
	shutil.copytree(runtime/'compile-current-source', provenance/'source-compilation')
	for path in runtime.glob('provider-*'):
		shutil.copytree(path, provenance/'provider-compilation'/path.name)
	audit(stage)
	print('FRESH_SOURCE_GENERATION', a.commit, 'object', sha(obj), 'LLVM', llvm['version'], flush=True)
	print((runtime/'compile-current-source/time.txt').read_text(), flush=True)
	print((runtime/'compile-current-source/command.json').read_text(), flush=True)


if __name__ == '__main__':
	main()
