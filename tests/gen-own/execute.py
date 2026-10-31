# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""GEN-OWN-1 concrete execution, exact owner identity and ABI differential audits."""
from pathlib import Path
import json
import os
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'tests/gen-own/fixtures'
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
CASES = {'drop-resource': 'AB', 'drop-object': 'AB', 'relay': 'AB', 'conditional': 'ABCD', 'recursive': 'AB', 'multi': 'VASVBSVCSVDS', 'null': '', 'class-nodeinit': '', 'property': 'ABC', 'struct': 'AB', 'loop': 'ABC', 'order': 'VCBAS', 'left-to-right': 'BA', 'short-circuit': 'AB', 'trap': ''}
FP_FLAGS = r'\b(?:reassoc|nnan|ninf|nsz|arcp|contract|afn|fast)\b|llvm\.(?:fma|fmuladd)|unsafe-fp|no-nans|no-infs|no-signed-zeros'


def run(argv, status=0, output=None):
	result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert result.returncode == status and not result.stderr and (output is None or result.stdout == output), (argv, result)
	return result.stdout


def inventory(text):
	return [dict(ordinal=int(m[0]), definition=int(m[1]), name=m[2], arguments=m[3].split(), requests=int(m[4])) for m in re.findall(r'\(generic-instance #(\d+) \(origin #(\d+) "([^"]+)"\) \(type-arguments (.*?)\) \(requests (\d+)\)', text)]


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	companion = out/'companion.o'
	run(['cc', '-std=c11', '-Werror', '-Wall', '-Wextra', '-c', ROOT/'tests/gen-own/companion.c', '-o', companion])
	records = dict(runs=[], inventory={}, deterministic=[], abi=[], identities=[], machine=[])
	dumps = {}

	def execute(name, ir, status=42, stdout='', mode='O0'):
		stem = name+'-'+mode
		if mode == 'callable-O2-fma':
			ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M)
		input_path = out/(stem+'-input.ll'); input_path.write_text(ir)
		path = out/(stem+'.ll'); obj = out/(stem+'.o'); exe = out/stem
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', input_path, '-o', path])
		run(['opt', '-passes=verify', '-disable-output', path])
		assert not re.search(FP_FLAGS, path.read_text()), stem
		run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'callable-O2-fma' else []), path, '-o', obj])
		run(['cc', obj, companion, '-o', exe]); run([exe], status, stdout)
		machine = run(['objdump', '-dr', obj]); (out/(stem+'.machine')).write_text(machine)
		assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b', machine), stem
		(out/(stem+'.symbols')).write_text(run(['readelf', '-h', '-Ws', obj]))
		records['runs'].append(dict(name=stem, status=status, output=stdout))

	for name, stdout in CASES.items():
		source = FIXTURES/f'gen-own-{name}.astra'; options = ['--vapi', FIXTURES/'ownership.vapi']
		status = -signal.SIGILL if name == 'trap' else 42
		run([compiler, source, *options, '--link-object', companion, '-o', out/name]); run([out/name], status, stdout)
		records['runs'].append(dict(name=name, status=status, output=stdout))
		stages = {stage: run([compiler, '--dump-'+stage, source, *([] if stage == 'syntax' else options)]) for stage in STAGES}
		dumps[name] = stages
		for stage, text in stages.items():
			(out/(name+'.'+stage)).write_text(text)
			assert text == run([compiler, '--dump-'+stage, source, *([] if stage == 'syntax' else options)]), (name, stage)
			records['deterministic'].append(name+':'+stage)
		rows = inventory(stages['instances']); records['inventory'][name] = rows
		assert len({(row['definition'], tuple(row['arguments'])) for row in rows}) == len(rows)
		for stage in ['instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
			assert not re.search(r'Ownable|type-parameter|generic-op|GEN1_PLAIN_COPY|ownership-contract', stages[stage]), (name, stage)
		ir = stages['llvm']
		assert not re.search(FP_FLAGS, ir)
		for pattern in [r'\b(?:malloc|calloc|realloc|free|atexit|landingpad|personality|invoke)\b', r'llvm\.memcpy|llvm\.memmove', r'alloca (?:ptr|i1)\b', r'dictionary|witness|type[._]descriptor|generic[._]cleanup|owner[._]header|type[._]switch|boxing']:
			assert not re.search(pattern, ir), (name, pattern)
		assert ir.count('alloca %astra.class.') == len(re.findall(r'^\t\t\((?:object-storage|candidate-storage) #', stages['ssa'], re.M)), name
		main_id = re.search(r'\(function #(\d+) "main" -> int', stages['ssa'])[1]
		wrapped = ir+'\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		for mode in ['O0', 'O2', 'callable-O2-fma']:
			execute(name, wrapped, status, stdout, mode)
		assert not re.search(r'libglib|libgobject|libLLVM', run(['ldd', out/name])), name
		for row in rows:
			if row['name'] not in {'dispose', 'relay', 'recurse', 'keep'}:
				continue
			symbol_name = f"astra.gen.{row['definition']}.{row['ordinal']}"
			ordinal = re.search(r'\(function #(\d+) "'+re.escape(symbol_name)+'"', stages['ssa'])[1]
			match = re.search(r'^define internal fastcc ([^\n]+?) @astra.fn.'+ordinal+r'\((.*?)\) \{\n(.*?)^}', ir, re.M | re.S)
			result, parameters, body = match.groups()
			if row['name'] in {'relay', 'recurse'}:
				is_class = row['arguments'][0] in {'Counter', 'Plain', 'Empty'}
				assert ('%result.storage' in parameters) == is_class and result == 'ptr'
				assert 'alloca ' not in body and 'llvm.mem' not in body
				records['abi'].append(dict(fixture=name, **row, symbol='astra.fn.'+ordinal, result=result, parameters=parameters))
			if name in {'drop-resource', 'drop-object', 'relay', 'recursive', 'multi'}:
				machine = (out/(name+'-callable-O2-fma.machine')).read_text()
				excerpt = re.search(r'^0+[0-9a-f]* <astra.fn.'+ordinal+r'>:\n.*?(?=\n\n|\Z)', machine, re.M | re.S)
				assert excerpt, (name, row)
				records['machine'].append(dict(fixture=name, definition=row['name'], arguments=row['arguments'], signature=parameters, assembly=excerpt[0]))

	def symbol(fixture, name, arguments):
		row = next(row for row in records['inventory'][fixture] if row['name'] == name and row['arguments'] == arguments)
		return 'astra.fn.'+re.search(r'\(function #(\d+) "astra.gen.'+str(row['definition'])+'.'+str(row['ordinal'])+'"', dumps[fixture]['ssa'])[1]

	for fixture, name, typename in [('relay', 'relay', 'Counter'), ('relay', 'relay', 'Resource'), ('recursive', 'recurse', 'Counter'), ('recursive', 'recurse', 'Resource'), ('recursive', 'left', 'Counter'), ('recursive', 'left', 'Resource'), ('class-nodeinit', 'relay', 'Empty')]:
		callee = symbol(fixture, name, [typename]); dispose = symbol(fixture, 'dispose', [typename])
		ir = dumps[fixture]['llvm']; resource = typename == 'Resource'; empty = typename == 'Empty'
		class_id = 1 if empty else 0
		lines = ['define i32 @main() {']
		if resource:
			lines += ['\t%incoming = call ptr @life_create(i32 73)']
		else:
			lines += [f'\t%incoming = alloca %astra.class.{class_id}', f'\t%candidate = alloca %astra.class.{class_id}', f'\tcall fastcc void @astra.ctor.{class_id}(ptr %incoming'+(')' if empty else ', i32 73)'), '\tstore i8 91, ptr %candidate']
		args = ([] if resource else ['ptr %candidate'])+([] if name == 'relay' else ['i32 5'])+['ptr %incoming']
		null_args = ([] if resource else ['ptr %candidate'])+([] if name == 'relay' else ['i32 3'])+['ptr null']
		lines += [f'\t%result = call fastcc ptr @{callee}('+', '.join(args)+')', '\t%same = icmp eq ptr %result, %incoming', f'\tcall fastcc void @{dispose}(ptr %result)', f'\t%null = call fastcc ptr @{callee}('+', '.join(null_args)+')', '\t%isnull = icmp eq ptr %null, null', f'\tcall fastcc void @{dispose}(ptr %null)', '\t%both = and i1 %same, %isnull']
		if not resource:
			lines += ['\t%sentinel = load i8, ptr %candidate', '\t%unused = icmp eq i8 %sentinel, 91', '\t%ok = and i1 %both, %unused']
		lines += ['\t%status = select i1 '+('%both' if resource else '%ok')+', i32 42, i32 1', '\tret i32 %status', '}']
		identity_name = 'identity-'+name+'-'+typename
		for mode in ['O0', 'O2', 'callable-O2-fma']:
			execute(identity_name, ir+'\n'+'\n'.join(lines)+'\n', 42, '' if empty else 'I', mode)
		records['identities'].append(dict(function=name, type=typename, original_pointer=True, null=True, unused_candidate=not resource))

	bits = [0, 0x8000000000000000, 1, 0x8000000000000001, 0x3ff0000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000042]
	callee = symbol('multi', 'keep', ['Resource', 'f64']); lines = ['define i32 @main() {']
	for i, value in enumerate(bits):
		lines += [f'\t%owner{i} = call ptr @life_create(i32 66)', f'\t%r{i} = call fastcc double @{callee}(ptr %owner{i}, double bitcast (i64 {value} to double))', f'\t%b{i} = bitcast double %r{i} to i64', f'\t%ok{i} = icmp eq i64 %b{i}, {value}', f'\tbr i1 %ok{i}, label %next{i}, label %bad', f'next{i}:', f'\t%mark{i} = call i32 @life_record(i32 83, i32 0)']
	lines += ['\tret i32 42', 'bad:', '\tret i32 1', '}']
	for mode in ['O0', 'O2', 'callable-O2-fma']:
		execute('f64-owner-bits', dumps['multi']['llvm']+'\n'+'\n'.join(lines)+'\n', 42, 'VBS'*len(bits), mode)
	(out/'unused.astra').write_text('void unused<T>(owned T value) where T : Ownable {}\n')
	for stage in STAGES:
		text = run([compiler, '--dump-'+stage, out/'unused.astra']); (out/('unused.'+stage)).write_text(text)
		assert text == run([compiler, '--dump-'+stage, out/'unused.astra'])
		if stage == 'instances':
			assert not inventory(text) and 'ownership-contract' not in text
		records['deterministic'].append('unused:'+stage)
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['identities'])} exact identity cases; {len(records['deterministic'])} fresh-process comparisons")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
