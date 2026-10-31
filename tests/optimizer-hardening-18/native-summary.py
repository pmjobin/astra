#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-hidden native summaries, matched allocation ablation and forged code."""
from pathlib import Path
import hashlib
import itertools
import os
import runpy
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence, identity


def main(compiler, build, runtime):
	build, runtime = Path(build).resolve(), Path(runtime).resolve()
	for path in [build, runtime]:
		assert not path.is_relative_to(ROOT)
		path.mkdir(parents=True, exist_ok=True)
	products = Path(tempfile.mkdtemp(prefix='native-summary-', dir=build))
	receipts = Path(tempfile.mkdtemp(prefix='native-summary-', dir=runtime))
	e = Evidence(compiler, receipts, 'native-summary')
	codec = runpy.run_path(str(ROOT / 'tests/structural-generics-15/units.py'))
	files = [HERE / f'optimizer-{name}.astra' for name in ['leaf', 'middle', 'consumer']]
	e.files(*files, Path(__file__), HERE / 'storage-observer.c', HERE / 'native-observer.c',
		ROOT / 'tests/structural-generics-15/units.py')
	production = sorted({p for prefix in ['bootstrap', 'lib', 'tools'] for p in (ROOT / prefix).rglob('*') if p.is_file() and p.suffix in ('.vala', '.vapi', '.c', '.h', '.py', '.astra')})
	production += [ROOT / 'meson.build', ROOT / 'meson.options']
	snapshot = {str(p.relative_to(ROOT)): identity(p) for p in production}
	e.data['production_snapshot'] = snapshot; e.save()
	def run(command, **kwargs):
		result = e.run(command, cwd=products, timeout=90, **kwargs)
		if kwargs.get('expected', 0) == 0 and not str(command[0]).endswith('valgrind'):
			assert not result.stderr, result
		return result
	observers = []
	for source in ['storage-observer.c', 'native-observer.c']:
		obj = products / (source + '.o')
		run(['clang', '-std=c11', '-O2', '-fno-builtin', '-Wall', '-Wextra', '-Werror', '-c', HERE / source, '-o', obj])
		observers += ['--link-object', obj]
	for renamed in [False, True]:
		leaf = 'Factors18' if renamed else 'OptimizerLeaf18'
		middle = 'Stage18' if renamed else 'OptimizerMiddle18'
		cell = 'Coefficient18' if renamed else 'Cell'
		inspect = 'evaluate_leaf18' if renamed else 'inspect'
		texts = [p.read_text().replace('OptimizerLeaf18', leaf).replace('OptimizerMiddle18', middle).replace('Cell', cell).replace('inspect', inspect) for p in files]
		levels = [*itertools.product('02', repeat=3), ('1', '1', '1')]
		for lp, lm, la in levels:
			case = products / (('renamed-' if renamed else 'original-') + lp + lm + la)
			case.mkdir()
			leaf_source, middle_source, consumer = [case / (name + '.astra') for name in ['leaf-hidden', 'middle-hidden', 'consumer']]
			for path, text in zip([leaf_source, middle_source, consumer], texts): path.write_text(text)
			e.files(leaf_source, middle_source, consumer)
			selectors = [leaf + '.' + name for name in [cell, inspect, 'combine', 'write', 'external']]
			args = list(itertools.chain.from_iterable(('--native-export', name) for name in selectors))
			run([e.compiler, '-O' + lp, '-c', leaf_source, '--module', leaf, *args, '--emit-interface', case / 'leaf.asti', '-o', case / 'leaf.o'])
			leaf_source.unlink()
			metadata = codec['metadata']((case / 'leaf.asti').read_text())
			assert metadata['abi']['schema'].endswith('runtime-units/6')
			assert all('optimizer' in group for name, group in metadata.items() if name.startswith('function '))
			assert metadata['function F:' + leaf + '.' + inspect]['optimizer'] == r'astra-optimizer-summary/1\nmemory|unknown\np|0|none|readonly'
			assert metadata['function F:' + leaf + '.external']['optimizer'] == r'astra-optimizer-summary/1\nmemory|unknown'
			run([e.compiler, '-O' + lm, '-c', middle_source, '--module', middle,
				'--native-export', middle + '.relay', '--native-export', middle + '.combine_local',
				'--import-module', case / 'leaf.asti', '--emit-interface', case / 'middle.asti', '-o', case / 'middle.o'])
			middle_source.unlink()
			assert sorted(p.name for p in case.glob('*.astra')) == ['consumer.astra']
			for mode in ['off', 'on']:
				env = dict(ASTRA_TEST_OPTIMIZATIONS=mode, ASTRA_EXPLAIN_OPTIMIZATIONS='1', DEBUGINFOD_URLS='')
				command = [e.compiler, '-O' + la, consumer, '--import-module', case / 'middle.asti', *observers]
				exe = case / ('consumer-' + mode)
				run([*command, '-o', exe], env=env)
				# Both independently checked library boundaries preserve capture facts.
				expected = 'opaque\nallocations=' + ('2' if mode == 'off' else '0') + ' retired=0\n'
				run([exe], stdout=expected)
				ir = case / (mode + '.ll'); ir.write_text(run([e.compiler, '-O' + la, consumer, '--import-module', case / 'middle.asti', '--dump-llvm'], env=env).stdout)
				assembly = case / (mode + '.asm'); assembly.write_text(run(['objdump', '-dr', exe]).stdout)
				if (lp, lm, la) == ('2', '2', '2'):
					memory = run(['valgrind', '--quiet', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--errors-for-leak-kinds=all', exe])
					assert memory.stdout.startswith('opaque\nallocations=') and memory.stdout.endswith(' retired=0\n')
					trace = case / (mode + '-opens.log')
					run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command, '-o', exe], env=env)
					opened = trace.read_text(); assert str(ROOT) not in opened and str(leaf_source) not in opened and str(middle_source) not in opened
					e.files(trace)
				e.files(exe, ir, assembly)
			if not renamed and (lp, lm, la) == ('2', '2', '2'):
				mutations(e, run, codec, case, leaf, inspect, consumer, observers)
			e.files(case / 'leaf.asti', case / 'leaf.o', case / 'middle.asti', case / 'middle.o')
	assert all(identity(ROOT / name) == row for name, row in snapshot.items())
	e.data['production_unchanged_during_ablation'] = True; e.save(); e.complete()


def mutations(e, run, codec, case, leaf, inspect, consumer, observers):
	weak = case / 'weak-binding'; weak.mkdir()
	groups = codec['metadata']((case / 'leaf.asti').read_text())
	symbol = groups['function F:' + leaf + '.' + inspect]['symbol']
	run(['objcopy', '--weaken-symbol=' + symbol, case / 'leaf.o', weak / 'leaf.o'])
	groups['object']['sha256'] = hashlib.sha256((weak / 'leaf.o').read_bytes()).hexdigest()
	(weak / 'leaf.asti').write_text(codec['reseal'](groups))
	client = weak / 'client.astra'; client.write_text('int main(){return 0;}\n')
	run([e.compiler, '-c', client, '--import-module', weak / 'leaf.asti', '-o', weak / 'refused.o'], expected=1,
		contains='optimizer claim is not proved by the exact supplied native object: F:' + leaf + '.' + inspect)
	assert not (weak / 'refused.o').exists(); e.files(weak / 'leaf.o', weak / 'leaf.asti')
	for name, payload, instructions in [
		('capture', r'astra-optimizer-summary/1\nmemory|unknown\np|0|none|unknown', 'movq %rdi,(%rdi)\nxorpd %xmm0,%xmm0\nret'),
		('readonly', r'astra-optimizer-summary/1\nmemory|unknown\np|0|none|readonly', 'xorpd %xmm0,%xmm0\nmovsd %xmm0,(%rdi)\nret'),
		('memory', r'astra-optimizer-summary/1\nmemory|none', 'movsd (%rdi),%xmm0\nret'),
		('ordinal', r'astra-optimizer-summary/1\nmemory|unknown\np|1|none|readonly', 'movsd (%rdi),%xmm0\nret'),
	]:
		bad = case / ('forged-' + name); bad.mkdir()
		groups = codec['metadata']((case / 'leaf.asti').read_text())
		for group, fields in groups.items():
			if group.startswith('function '): fields['optimizer'] = r'astra-optimizer-summary/1\nmemory|unknown'
		target = 'function F:' + leaf + '.' + inspect
		groups[target]['optimizer'] = payload
		groups['abi']['identity'] = codec['fingerprint'](groups, False)
		assembly = []
		for group, fields in groups.items():
			if not group.startswith('function '): continue
			symbol = 'astra_mod_' + groups['abi']['identity'] + '_' + hashlib.sha256(group[9:].encode()).hexdigest()
			fields['symbol'] = symbol
			assembly += ['.globl ' + symbol, '.type ' + symbol + ',@function', symbol + ':', instructions if group == target else 'ret', '.size ' + symbol + ',.-' + symbol]
		source = bad / 'forged.S'; source.write_text('.text\n' + '\n'.join(assembly) + '\n.section .note.GNU-stack,"",@progbits\n')
		run(['cc', '-c', source, '-o', bad / 'leaf.o'])
		groups['object']['sha256'] = hashlib.sha256((bad / 'leaf.o').read_bytes()).hexdigest()
		(bad / 'leaf.asti').write_text(codec['reseal'](groups))
		output = bad / 'refused'
		# The consumer source directly selects the forged leaf, with no middle
		# dependency fingerprints to mask the independent effect rejection.
		client = bad / 'client.astra'; client.write_text('using ' + leaf + '; int main(){ var c=new Cell(1.0); return 0; }')
		run([e.compiler, client, '--import-module', bad / 'leaf.asti', *observers, '-o', output], expected=1,
			contains='optimizer claim is not proved by the exact supplied native object: F:' + leaf + '.' + inspect)
		assert not output.exists(); e.files(source, bad / 'leaf.o', bad / 'leaf.asti')
		# Capture and access are independent dimensions in the approved schema.
		# Rebind honest native code to weaker summaries, with exact new symbols and
		# receipts, and check that readonly never acquires an unclaimed capture fact.
	for name, target, ordinal in [('parameter', 'F:' + leaf + '.' + inspect, 0),
		('receiver', 'C:' + leaf + '.Cell::read', -1)]:
		accepted = case / ('readonly-only-' + name); accepted.mkdir()
		groups = codec['metadata']((case / 'leaf.asti').read_text())
		groups['function ' + target]['optimizer'] = r'astra-optimizer-summary/1\nmemory|unknown\np|' + str(ordinal) + r'|unknown|readonly'
		groups['abi']['identity'] = codec['fingerprint'](groups, False)
		rebindings = []
		for group, fields in groups.items():
			if not group.startswith('function '): continue
			symbol = 'astra_mod_' + groups['abi']['identity'] + '_' + hashlib.sha256(group[9:].encode()).hexdigest()
			rebindings.append(fields['symbol'] + ' ' + symbol); fields['symbol'] = symbol
		mapping = accepted / 'symbols.txt'; mapping.write_text('\n'.join(rebindings) + '\n')
		run(['objcopy', '--redefine-syms=' + str(mapping), case / 'leaf.o', accepted / 'leaf.o'])
		groups['object']['sha256'] = hashlib.sha256((accepted / 'leaf.o').read_bytes()).hexdigest()
		(accepted / 'leaf.asti').write_text(codec['reseal'](groups))
		client = accepted / 'client.astra'; client.write_text('int main(){return 0;}\n')
		run([e.compiler, '-c', client, '--import-module', accepted / 'leaf.asti', '-o', accepted / 'accepted.o'])
		ir = run([e.compiler, '--dump-llvm', client, '--import-module', accepted / 'leaf.asti'],
			env=dict(ASTRA_TEST_OPTIMIZATIONS='on')).stdout
		declaration = next(line for line in ir.splitlines() if line.startswith('declare ') and groups['function ' + target]['symbol'] in line)
		assert 'readonly' in declaration and 'captures(' not in declaration, declaration
		e.files(mapping, accepted / 'leaf.asti', accepted / 'leaf.o', accepted / 'accepted.o')
	for name, field, replacement, diagnostic in [
		('version', 'optimizer', r'astra-optimizer-summary/9\nmemory|unknown', 'invalid optimizer summary'),
		('duplicate', 'optimizer', r'astra-optimizer-summary/1\nmemory|unknown\np|0|none|readonly\np|0|none|readonly', 'invalid optimizer summary'),
		('old-schema', 'schema', 'gnu-x86_64-lp64-runtime-units/5', 'version/schema/compiler fingerprint mismatch'),
	]:
		bad = case / ('metadata-' + name); bad.mkdir(); shutil.copyfile(case / 'leaf.o', bad / 'leaf.o')
		groups = codec['metadata']((case / 'leaf.asti').read_text())
		groups['abi' if field == 'schema' else 'function F:' + leaf + '.' + inspect][field] = replacement
		(bad / 'leaf.asti').write_text(codec['reseal'](groups))
		run([e.compiler, '--check', consumer, '--import-module', bad / 'leaf.asti'], expected=1, contains=diagnostic)
		e.files(bad / 'leaf.asti')


if __name__ == '__main__': main(*sys.argv[1:])
