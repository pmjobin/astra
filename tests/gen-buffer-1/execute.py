# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact values, independent allocation and unchanged-pointer ownership transport."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import shutil
import signal
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/support'))
from pipeline import observations, machine_objects
spec = importlib.util.spec_from_file_location('elements', ROOT / 'tests/struct-elem-1/execute.py')
elements = importlib.util.module_from_spec(spec)
spec.loader.exec_module(elements)
run = elements.run
LIBRARIES = ['slices.astra', 'buffers.astra']
HELPERS = '''struct Box<T>{T value;}
owned T[] make<T>(int n){return new T[n];}
owned T[] relay<T>(owned T[] a){return move a;}
owned T[] forward<T>(owned T[] a){return relay(move a);}
T snapshot<T>(T[] a,int i){return a[i];}
extern(C) int gb_word(int i);
extern(C) int gb_generation();
extern(C) void gb_unchanged(int generation);
extern(C) void gb_distinct();
extern(C) void gb_live(int expected);
extern(C) void gb_zero(int value);
extern(C) void gb_check_word(int value,int index);
'''

def scalar_value(base, ordinal):
	if base not in ['bool', 'void*', 'f32', 'f64']:
		return f'gb_word({ordinal}) as {base}'
	return elements.scalar_value(base, ordinal)

def matrix():
	parts = [elements.IMPORTS, HELPERS]
	for number, leaf in enumerate(elements.LEAVES):
		base = leaf.split('<')[0]
		lanes = int(leaf.split('<')[1][:-1]) if '<' in leaf else 1
		def value(ordinal):
			return '{' + ','.join(scalar_value(base, f'{ordinal}+{lane}') for lane in range(lanes)) + '}' if '<' in leaf else scalar_value(base, ordinal)
		def checks(name, ordinal=None):
			terms = []
			for lane in range(lanes):
				field = name + (f'[{lane}]' if '<' in leaf else '')
				index = None if ordinal is None else f'{ordinal}+{lane}'
				terms.append(elements.scalar_check(base, field, index) if index is None or base in ['bool', 'void*', 'f32', 'f64'] else f'{field}==({scalar_value(base,index)})')
			return '&&'.join(terms)
		parts.append(f'''struct R{number}{{u8 before;{leaf} value;u8 after;}}
int matrix{number}(int n){{
	var original=make<{leaf}>(n);var record=make<R{number}>(n);
	var i=0;while(i<n){{if(!({checks('original[i]')}&&{checks('record[i].value')})||record[i].before!=0||record[i].after!=0){{return 1;}}i=i+1;}}
	var pattern=0;while(pattern<12){{
		{leaf} expected={value('pattern')};{leaf} replacement={value('pattern+1')};
		R{number} r={{before=91,value=expected,after=117}};
		fill(original,expected);fill(record,r);
		var a=clone_array(original);var b=clone_array(record);
		var filled=filled_array(n,expected);var records=filled_array(n,r);
		Box<R{number}> box={{value=r}};var boxes=filled_array(n,box);var cloned_boxes=clone_array(boxes);
		gb_distinct();var generation=gb_generation();
		a=forward(move a);b=relay(move b);gb_unchanged(generation);
		if(n>0){{
			original[0]=replacement;record[0].before=3;
			var snapshot_value=snapshot(b,n-1);
			if(!({checks('snapshot_value.value','pattern')})){{return 2;}}
			i=0;while(i<n){{if(!({checks('a[i]','pattern')}&&{checks('filled[i]','pattern')}&&{checks('b[i].value','pattern')}&&{checks('records[i].value','pattern')}&&{checks('cloned_boxes[i].value.value','pattern')})||b[i].before!=91||b[i].after!=117){{return 3;}}i=i+1;}}
			a[0]=replacement;b[0].before=11;
			if(!({checks('filled[0]','pattern')})||records[0].before!=91||snapshot_value.before!=91){{return 4;}}
		}}
		release a;release b;release boxes;
		if(n>0){{if(!({checks('filled[n-1]','pattern')}&&{checks('cloned_boxes[n-1].value.value','pattern')})){{return 5;}}}}
		pattern=pattern+1;
	}}
	return 0;
}}
''')
	parts.append('int main(){int j=0;while(j<2){int n=se_count(j*3);' + ''.join(f'if(matrix{i}(n)!=0){{return {i+1};}}gb_live(0);' for i in range(34)) + 'j=j+1;}return 0;}')
	return '\n'.join(parts) + '\n'

def validate_trace(text):
	live = {}
	allocations = []
	for line in text.splitlines():
		if line.startswith('A'):
			owner, count, stride = map(int, line[1:].split(':'))
			assert owner not in live and count > 0 and stride > 0
			live[owner] = (count, stride)
			allocations.append((count, stride))
		elif line.startswith('F'):
			assert live.pop(int(line[1:]), None) is not None
	assert not live, live
	return allocations

def qualify(compiler, out, collector=None):
	collector = collector or compiler.parent / 'tests/support/astra-stage-collector'
	out.mkdir(parents=True, exist_ok=False)
	for name in LIBRARIES:
		shutil.copyfile(ROOT / 'lib/astra/base' / name, out / name)
	companions = {}
	for cc in ['gcc', 'clang']:
		companions[cc] = out / (cc + '-observer.o')
		run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', ROOT / 'tests/gen-buffer-1/companion.c', '-o', companions[cc]])
	(out / 'matrix.astra').write_text(matrix())
	deep = elements.deep(64).replace('int main()', HELPERS + 'int main()').replace('var a=new D63[2];a[1]=fixed[0];', 'var a=filled_array(2,fixed[0]);a=clone_array(a);a=forward(move a);')
	(out / 'deep-64.astra').write_text(deep)
	shutil.copyfile(ROOT / 'tests/gen-buffer-1/fixtures/basic.astra', out / 'basic.astra')
	cases = [('matrix', 0, None), ('deep-64', 0, 'A1:2:16\nA2:2:16\nF1\nF2\n'), ('basic', 0, None)]
	large = elements.IMPORTS + HELPERS + 'struct Large{' + ''.join(f'int f{i};' for i in range(256)) + '}int main(){int n=se_count(2);var a=make<Large>(n);'
	large += ''.join(f'gb_zero(a[1].f{i});a[1].f{i}=gb_word({i});' for i in range(256))
	large += 'var b=clone_array(a);Large snapshot=b[1];release a;b=forward(move b);release b;'
	large += ''.join(f'gb_check_word(snapshot.f{i},{i});' for i in range(256)) + 'return 0;}\n'
	(out / 'large.astra').write_text(large)
	cases.append(('large', 0, 'A1:2:1024\nA2:2:1024\nF1\nF2\n'))
	metadata = elements.IMPORTS + HELPERS + '''
owned T[] meta_relay<T>(owned T[] values,string expected,int expected_line,[CallerFilePath] string file,[CallerLineNumber] int line,[CallerArgumentExpression("values")] string expression){if(file!="metadata.astra"||line!=expected_line||expression!=expected){se_mark(99);}return move values;}
owned T[] meta_definition<T>(owned T[] values){return meta_relay(move values,"move values",CALL_LINE);}
owned T[] meta_forward<T>(owned T[] values,int expected_line,[CallerFilePath] string file,[CallerLineNumber] int line,[CallerArgumentExpression("values")] string expression){return meta_relay<T>(move values,"move b",expected_line,file,line,expression);}
T meta_value<T>(T value,[CallerArgumentExpression("value")] string expression){if(expression!="b[0]"){se_mark(99);}return value;}
int main(){
	var a=make<int>(2);
	var b=meta_relay(move a,"move a",CALL_LINE);
	b=meta_definition(move b);
	b=meta_forward(move b,CALL_LINE);
	var saved=meta_value(b[0]);var copy=clone_array(b);release b;
	if(saved!=0||copy[0]!=0){return 1;}return 0;
}
'''
	metadata = '\n'.join(line.replace('CALL_LINE', str(number)) for number, line in enumerate(metadata.splitlines(), 1)) + '\n'
	(out / 'metadata.astra').write_text(metadata)
	cases.append(('metadata', 0, 'A1:2:4\nA2:2:4\nF1\nF2\n'))
	shutil.copyfile(ROOT / 'tests/gen-buffer-1/fixtures/mixed.astra', out / 'mixed.astra')
	mixed_trace = 'A1:2:16 A2:2:16 R+1 A3:2:16 M70 A4:2:16 F2 M71 F4 R-1 M70 A5:2:16 A6:2:16 M70 A7:2:16 F5 M71 F7 M71 F6 F3 F1'
	cases.append(('mixed', 0, ''.join(event + '\n' for event in mixed_trace.split())))
	prelude = elements.IMPORTS + HELPERS + 'extern(C) void gs_watch();struct S{int x;f64 y;}S seed(){se_mark(91);S value={x=7,y=2.0d};return value;}int checked_index(owned S[] a,S value){se_mark(99);return value.x;}'
	for name, body, status, trace in [
		('eager-empty', 'var a=filled_array(se_mark(0),seed());', 0, 'M0 M91'),
		('negative-count', 'var a=filled_array(se_mark(-1),seed());', -signal.SIGILL, 'M-1 M91'),
		('oom-new', 'se_fail();var a=make<S>(se_mark(2));', -signal.SIGILL, 'M2 OOM'),
		('oom-replacement', 'var a=make<S>(2);a[0].x=17;gs_watch();se_fail();a=clone_array(a);', -signal.SIGILL, 'A1:2:16 OOM'),
		('later-argument-trap', 'var a=make<S>(2);var empty=make<S>(0);var n=checked_index(move a,snapshot(empty,se_mark(0)));', -signal.SIGILL, 'A1:2:16 M0'),
		('copied-before-move', 'var a=filled_array(2,seed());S saved=snapshot(a,0);var b=forward(move a);if(saved.x!=7||b[0].x!=7){return 1;}', 0, 'M91 A1:2:16 F1'),
	]:
		(out / (name + '.astra')).write_text(prelude + 'int main(){' + body + 'return 0;}\n')
		cases.append((name, status, ''.join(event + '\n' for event in trace.split())))
	records = dict(compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), shapes=elements.LEAVES, runs=[], stages=[], layouts=elements.c_layouts(out, [elements.layout(leaf) for leaf in elements.LEAVES]))
	for name, status, expected in cases:
		dumps = observations(compiler, collector, [*LIBRARIES, name + '.astra', *(['--vapi', ROOT / 'tests/struct-elem-1/fixtures/runtime.vapi'] if name == 'mixed' else [])], out, name, run, out, public=name in ['basic', 'transport', 'identity', 'mixed', 'boundary', 'effects'])
		for stage in elements.STAGES:
			records['stages'].append(name + ':' + stage)
		ordinal = re.search(r'\(function #(\d+) "main" -> int', dumps['ssa'])[1]
		wrapped = dumps['llvm'] + '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.' + ordinal + '()\n\tret i32 %r\n}\n'
		canonical = expected
		for mode, stem, obj in machine_objects(wrapped, out, name, run):
			for cc, observer in companions.items():
				binary = out / (stem + '-' + cc)
				run([cc, obj, observer, '-Wl,--wrap=calloc,--wrap=free', '-o', binary])
				observed = run([binary], status=status)
				(out / (binary.name + '.stdout')).write_text(observed)
				if status == 0:
					allocations = validate_trace(observed)
					if name == 'matrix':
						strides = {stride for count, stride in allocations}
						assert {elements.layout(leaf)['size'] for leaf in elements.LEAVES} <= strides
				if canonical is None:
					canonical = observed
				assert observed == canonical, (binary.name, observed, canonical)
				records['runs'].append(dict(name=binary.name, category='normal' if status == 0 else 'fatal-nonunwinding', status=status, output_sha256=hashlib.sha256(observed.encode()).hexdigest()))
			for suffix, command in [('machine', ['objdump', '-dr']), ('symbols', ['readelf', '-h', '-Ws', '-r']), ('size', ['size', '-A']), ('undefined', ['nm', '-u'])]:
				(out / (stem + '.' + suffix)).write_text(run([*command, obj]))
	(out / 'results.json').write_text(json.dumps(records, indent='\t') + '\n')
	print(f"{len(records['runs'])} native runs; {len(records['stages'])} repeated stages; all 34 elements and recursive records")

if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	qualify(Path(sys.argv[1]).resolve(), fresh_output(sys.argv[2]), Path(sys.argv[3]).resolve(strict=True) if len(sys.argv) == 4 else None)
