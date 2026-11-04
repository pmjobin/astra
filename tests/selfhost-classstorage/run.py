#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-bound native/C0/ABI/memory baselines; mutations are a separate gate."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('storage_probe', Path(__file__).with_name('abi-probe.py'))
probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def compare_layouts(text, observations):
	layouts, fields = {}, {}
	for line in observations:
		r = line.split()
		if r[0] == 'LAYOUT': layouts[r[1]] = tuple(map(int, r[2:]))
		if r[0] == 'FIELD': fields[(r[1], r[2])] = tuple(map(int, r[3:]))
	actual = {}; count = 0
	for line in text.splitlines():
		r = line.split()
		if not r: continue
		if r[0] == 'PAYLOAD':
			name = bytes.fromhex(r[4]).decode(); size, alignment, members, machine_size, machine_alignment = map(int, r[5:10])
			assert layouts[name] == (size, alignment, members) and (machine_size, machine_alignment) == (size, alignment), r
			actual[int(r[1])] = name
		if r[0] == 'PAYLOAD_FIELD':
			name = actual[int(r[1])]; member = bytes.fromhex(r[8]).decode(); planned, measured = map(int, r[6:8])
			assert fields[(name, member)][0] == planned == measured, r
			count += 1
	assert actual, 'no physical payload observations'
	return dict(payloads=len(actual), fields=count)


def main():
	p = argparse.ArgumentParser()
	for name in ('component', 'compiler', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--selection', action='append', type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--case', action='append', help='Explicit focused selection; omissions remain visible in the manifest')
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256'] and all(sha(path) == value for path, value in identity['identity']['sources'].items()) and all(sha(path) == value for path, value in identity['identity']['tools'].items())
	assert sha(a.compiler) == a.compiler_sha256
	implementation_modes = [arg for arg in identity['identity']['argv'] if arg in ('-O0', '-O2')]
	commands, results = [], []
	tools = {name: dict(path=str(Path(shutil.which(name)).resolve()), sha256=sha(shutil.which(name))) for name in ('gcc', 'g++', 'llvm-as', 'opt', 'readelf', 'nm', 'objdump', 'valgrind')}
	environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('VALGRIND_OPTS', None)
	def run(argv, name, expected=0):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=a.build, capture_output=True, timeout=180, env=environment)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr.decode(errors='replace')[-1200:])
		return r
	items = [item for path in a.selection for item in json.loads(path.read_text())]
	assert len(items) == len({item['name'] for item in items})
	manifest = dict(mode=a.mode, component_sha256=sha(a.component), component_implementation_modes=implementation_modes, compiler_sha256=sha(a.compiler), selections={str(path):sha(path) for path in a.selection}, omitted=[item['name'] for item in items if a.case and item['name'] not in a.case], tools=tools, VALGRIND_OPTS='removed; --command-line-only=yes excludes implicit rc options', recipes={str(path):sha(path) for path in (Path(__file__), Path(__file__).with_name('abi-probe.py'))})
	(a.runtime/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
	for item in items:
		name = item['name']
		if a.case and name not in a.case: continue
		row = dict(name=name, mode=a.mode, sources=item['sources'], baseline_complete=False, mutation_gate='NOT_PERFORMED_BY_THIS_RUNNER')
		try:
			sources = [Path(source['path']) for source in item['sources']]
			assert all(sha(source['path']) == source['sha256'] for source in item['sources'])
			for source in item['sources']: assert Path(source['path']).stat().st_size == source['bytes']
			prefix = a.build/(name+'-'+a.mode); unused = a.build/'unused'
			admission = run([a.component, '--classstorage-admit', a.mode, unused, *sources], name+'-admit').stdout
			assert admission.startswith(b'astra-flow/4\nSTATUS 0 0\n')
			ssa = run([a.component, '--classstorage-ssa', a.mode, unused, *sources], name+'-ssa').stdout
			assert ssa.startswith(b'astra-ssa/1\n')
			abi = run([a.component, '--classstorage-abi-plan', a.mode, unused, *sources], name+'-abi').stdout.decode()
			head, physical = abi.split('\nastra-classstorage-physical/1\n', 1)
			plan = bytes.fromhex(head.strip()).decode(); assert plan.startswith('astra-nativeabi/1')
			(a.runtime/(name+'.abi')).write_text(plan+'\nastra-classstorage-physical/1\n'+physical)
			probe_runtime = a.runtime/(name+'-independent-ABI'); probe_build = a.build/(name+'-independent-ABI')
			run([sys.executable, '-B', Path(__file__).with_name('abi-probe.py'), '--compiler', a.compiler, '--compiler-sha256', a.compiler_sha256, '--build', probe_build, '--runtime', probe_runtime, *sources], name+'-ABI-probe')
			measured = json.loads((probe_runtime/'result.json').read_text()); row['layout_comparison'] = compare_layouts(physical, measured['observations'])
			products = {key: Path(str(prefix)+suffix) for key, suffix in (('raw', '.raw.ll'), ('ir', '.ll'), ('object', '.o'), ('native', ''), ('C0', '.c0'))}
			for command, key in (('--classstorage-llvm-raw', 'raw'), ('--classstorage-llvm-ir', 'ir'), ('--classstorage-emit-obj', 'object')):
				run([a.component, command, a.mode, products[key], *sources], name+'-'+key)
			text = products['raw'].read_text()
			assert re.search(r'target triple = "x86_64-[^"]*linux', text)
			assert not re.search(r'\b(?:nsw|nuw|exact|inbounds|noalias|nonnull|dereferenceable|readonly|nocapture|fast|reassoc|nnan|ninf|nsz|arcp|afn|undef|poison)\b', text)
			assert not re.search(r'@(?:astra_c0|valac|system|exec|popen|dlopen)', text)
			run(['llvm-as', products['raw'], '-o', Path(str(prefix)+'.bc')], name+'-llvm-as')
			run(['opt', '-passes=verify', '-disable-output', products['ir']], name+'-LLVM-verify')
			elf = run(['readelf', '-h', products['object']], name+'-ELF').stdout
			assert b'ELF64' in elf and b'Advanced Micro Devices X86-64' in elf and b'REL (Relocatable file)' in elf
			run(['nm', '-a', products['object']], name+'-symbols'); run(['objdump', '-dr', products['object']], name+'-disassembly')
			run(['gcc', products['object'], '-o', products['native']], name+'-link')
			run([a.compiler, '-'+a.mode, *sources, '-o', products['C0']], name+'-C0-build')
			expected = item['expected_exit']; actual = run([products['native']], name+'-native-execute', expected); oracle = run([products['C0']], name+'-C0-execute', expected)
			assert actual.stdout == oracle.stdout == b'' and actual.stderr == oracle.stderr == b''
			memory = {}
			for label in ('native', 'C0'):
				xml = a.runtime/(name+'-'+label+'.xml')
				checked = run(['valgrind', '--command-line-only=yes', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--track-origins=yes', '--xml=yes', '--xml-file='+str(xml), products[label]], name+'-memory-'+label, expected)
				assert checked.stdout == actual.stdout
				root = ET.parse(xml).getroot(); assert root.find('error') is None and root.findall('./status/state')[-1].text == 'FINISHED'
				memory[label] = dict(xml_sha256=sha(xml), source_visible_result_matches=True, trace_sha256=hashlib.sha256(checked.stderr).hexdigest())
			assert all(sha(source['path']) == source['sha256'] for source in item['sources'])
			row.update(baseline_complete=True, memory=memory, products={key:dict(path=str(path),sha256=sha(path)) for key,path in products.items()}, limitation='C0 may elide unobservable allocations. Allocation traces are retained separately; equal allocation counts are not asserted. Mutation and inherited regression gates remain separate.')
		except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
			row['failure'] = str(error)
		results.append(row); (a.runtime/'results.json').write_text(json.dumps(results, indent=2)+'\n')
		print(name, 'BASELINE_COMPLETE' if row['baseline_complete'] else 'INCOMPLETE', row.get('failure',''), flush=True)
	assert all(sha(path) == value for path,value in manifest['recipes'].items())
	print(sum(row['baseline_complete'] for row in results), '/', len(results), 'source-bound baselines complete; milestone mutation/regression/report gates are not implied')
	raise SystemExit(0 if results and all(row['baseline_complete'] for row in results) else 1)


if __name__ == '__main__':
	main()
