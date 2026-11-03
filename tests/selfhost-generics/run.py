#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent ELF, C0, LLVM and unsuppressed owner/memory observations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-llvm'))
from oracle import memory, inspect
from layout import check as check_layout


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('component', 'compiler', 'build', 'runtime', 'frozen'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--case', action='append')
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	a.build.mkdir(parents=True, exist_ok=True); a.runtime.mkdir(parents=True, exist_ok=False)
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256']
	assert all(sha(path) == digest for path, digest in identity['identity']['sources'].items())
	assert sha(a.compiler) == '908f8db9e524cf94b7651f36e9bf0ff32c98ef64cb7eacd737c3b5f680064b45'
	commands, results = [], []
	def run(argv, name, expected=0):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=a.build, capture_output=True, timeout=180, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, argv)), exit=r.returncode, name=name, monotonic_start=start, monotonic_end=time.monotonic(), stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr[-2000:].decode(errors='replace'))
		return r
	items = json.loads((a.frozen/'selection.json').read_text())
	for item in items:
		name = item['name']
		if a.case and name not in a.case:
			continue
		sources = [Path(s['path']) for s in item['sources']]
		assert all(sha(s['path']) == s['sha256'] for s in item['sources'])
		product = a.build/(name+'-'+a.mode)
		products = dict(raw=product.with_suffix('.raw.ll'), ir=product.with_suffix('.ll'), object=product.with_suffix('.o'), executable=product, reference=product.with_suffix('.c0'))
		admission = run([a.component, '--nativeabi-admit', a.mode, a.runtime/'unused', *sources], name+'-admit').stdout
		assert admission.startswith(b'astra-flow/4\nSTATUS 0 0\n')
		plans = run([a.component, '--generic-plan', a.mode, a.runtime/'unused', *sources], name+'-instances').stdout
		assert plans.startswith(b'astra-generics/1\n') and b'INSTANCE ' in plans
		ssa = run([a.component, '--nativeabi-ssa', a.mode, a.runtime/'unused', *sources], name+'-ssa').stdout
		abi = bytes.fromhex(run([a.component, '--abi-plan', a.mode, a.runtime/'unused', *sources], name+'-abi').stdout.decode().strip())
		products['ABI-plan'] = a.runtime/(name+'.abi'); products['ABI-plan'].write_bytes(abi)
		for command, suffix in [('--dump-nabi', 'nabi'), ('--dump-semantics', 'semantics')]:
			products['C0-'+suffix] = a.runtime/(name+'.'+suffix)
			products['C0-'+suffix].write_bytes(run([a.compiler, command, *sources], name+'-C0-'+suffix).stdout)
		for stage, key in [('--llvm-raw', 'raw'), ('--llvm-ir', 'ir'), ('--emit-obj', 'object')]:
			run([a.component, stage, a.mode, products[key], *sources], name+'-'+key)
		layout = check_layout(name, abi, products['C0-nabi'].read_bytes())
		text = products['raw'].read_text(); inspect(products['raw'].read_bytes(), ssa)
		assert (b'SIGNATURE Fn<' not in plans or 'astra.g.' in text) and not re.search(r'\b(?:noalias|nonnull|nocapture|readonly|fast|contract|undef|poison)\b', text)
		run(['llvm-as', products['raw'], '-o', product.with_suffix('.bc')], name+'-llvm-as')
		run(['opt', '-passes=verify', '-disable-output', products['ir']], name+'-verify')
		header = run(['readelf', '-h', products['object']], name+'-ELF').stdout
		assert b'ELF64' in header and b'Advanced Micro Devices X86-64' in header
		run(['nm', '-a', products['object']], name+'-symbols')
		run(['objdump', '-dr', products['object']], name+'-disassembly')
		run(['gcc', products['object'], '-o', product], name+'-link')
		actual = run([product], name+'-execute')
		assert actual.stdout == actual.stderr == b''
		run([a.compiler, '-'+a.mode, *sources, '-o', products['reference']], name+'-C0-build')
		reference = run([products['reference']], name+'-C0-execute')
		assert (actual.stdout, actual.stderr) == (reference.stdout, reference.stderr)
		memories = {}
		for label, executable in [('native', product), ('C0', products['reference'])]:
			v = run(['valgrind', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', executable], name+'-memory-'+label)
			assert v.stdout == actual.stdout
			memories[label] = memory(v.stderr)
		memory_contract = dict(kind='unsuppressed-memory-health')
		if name.startswith('owner-'):
			assert memories['native']['observed_trace'] == memories['C0']['observed_trace']
			assert memories['native']['observed_trace']
			memory_contract = dict(kind='exact-independent-owner-trace')
		if name.startswith('method-') or name == 'control':
			# C0 O2 may erase an unobserved empty Class. Astra's approved private
			# ABI requires its real allocation even when the receiver is unused.
			count = 2 if name == 'control' else 1
			native_class = [event for event in memories['native']['observed_trace'] if event[1] == 1]
			c0_class = [event for event in memories['C0']['observed_trace'] if event[1] == 1]
			assert native_class.count(['A', 1]) == native_class.count(['F', 1]) == count
			elided = c0_class != native_class
			assert not elided or a.mode == 'O2' and c0_class == []
			assert [event for event in memories['native']['observed_trace'] if event[1] != 1] == [event for event in memories['C0']['observed_trace'] if event[1] != 1]
			products['C0-main-disassembly'] = a.runtime/(name+'-C0-main-disassembly.stdout')
			machine = run(['objdump', '-dr', '--disassemble=main', products['reference']], name+'-C0-main-disassembly').stdout
			if elided and name != 'control': assert b'calloc' not in machine and b'free' not in machine
			memory_contract = dict(kind='approved-real-Class-allocation', native_allocations=count, native_once_only_frees=count, C0_O2_empty_Class_elided=elided, C0_class_trace=c0_class, native_class_trace=native_class, buffer_trace_exact=True, limit='C0 optimization may erase unobserved empty Classes; this does not erase the required real Astra object or change either raw memory result.')
		if name.startswith(('owner-', 'method-')) or name == 'control':
			for observed in memories.values():
				trace = observed['observed_trace']
				assert sum(size for action, size in trace if action == 'A') == sum(size for action, size in trace if action == 'F')
		results.append(dict(item, mode=a.mode, result='PASS', component_sha256=sha(a.component), c0_sha256=sha(a.compiler), instances_sha256=hashlib.sha256(plans).hexdigest(), ssa_sha256=hashlib.sha256(ssa).hexdigest(), admission_sha256=hashlib.sha256(admission).hexdigest(), memory=memories, memory_contract=memory_contract, layout=layout, products={k:dict(path=str(v), bytes=v.stat().st_size, sha256=sha(v)) for k, v in products.items()}))
		(a.runtime/'results.json').write_text(json.dumps(results, indent=2)+'\n')
		print(name, a.mode, 'PASS', flush=True)
	if not a.case:
		assert len(results) >= 12 and len({tuple(s['sha256'] for s in r['sources']) for r in results}) == len(results)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='DEVELOPMENT' if a.case else 'PASS', mode=a.mode, cases=results), indent=2)+'\n')


if __name__ == '__main__':
	main()
