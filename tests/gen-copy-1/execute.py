# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact value transport, ordinary controls and independent scalar observers."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import signal
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/support'))
from pipeline import observations, machine_objects
spec = importlib.util.spec_from_file_location('elements', ROOT/'tests/struct-elem-1/execute.py')
elements = importlib.util.module_from_spec(spec)
spec.loader.exec_module(elements)
run = elements.run
FIXTURES = ROOT/'tests/gen-copy-1/fixtures'
HELPERS = '''struct Box<T>{T value;}
T identity<T>(T value){return value;}
T choose<T>(bool take,T a,T b){T local=b;if(take){local=a;}int i=0;while(i<2){T saved=local;local=saved;i=i+1;}return local;}
T through_box<T>(T input){Box<T> first={value=input};Box<T> second=first;T saved=second.value;second.value=input;return identity(saved);}
T constructed<T>(T input){Box<T> box={value=input};Box<T> copied=identity(box);return through_box(copied.value);}
'''


def matrix():
	parts = [elements.IMPORTS, HELPERS]
	for number, leaf in enumerate(elements.LEAVES):
		base = leaf.split('<')[0]
		lanes = int(leaf.split('<')[1][:-1]) if '<' in leaf else 1
		value = '{'+','.join(elements.scalar_value(base, f'pattern+{lane}') for lane in range(lanes))+'}' if '<' in leaf else elements.scalar_value(base, 'pattern')
		def checks(value):
			return '&&'.join(elements.scalar_check(base, value+(f'[{lane}]' if '<' in leaf else ''), f'pattern+{lane}') for lane in range(lanes))
		parts.append(f'''struct Leaf{number}{{{leaf} value;}}
struct Record{number}{{Leaf{number} first;Leaf{number} second;void* token;}}
Record{number} native_id{number}(Record{number} value){{return value;}}
Record{number} native_choose{number}(bool take,Record{number} a,Record{number} b){{Record{number} local=b;if(take){{local=a;}}int i=0;while(i<2){{Record{number} saved=local;local=saved;i=i+1;}}return local;}}
Record{number} native_box{number}(Record{number} input){{Box<Record{number}> first={{value=input}};Box<Record{number}> second=first;Record{number} saved=second.value;second.value=input;return native_id{number}(saved);}}
int matrix{number}(int pattern){{
	{leaf} initial={value};
	{leaf} scalar=identity<{leaf}>(through_box(choose(true,initial,initial)));
	if(!({checks('scalar')})){{return 1;}}
	Record{number} record={{first={{value=initial}},second={{value=initial}},token=se_pointer()}};
	var direct=identity<Record{number}>(record);var inferred=identity(record);
	var choice=choose(true,direct,inferred);var boxed=through_box(choice);var whole=constructed(boxed);
	var ordinary=native_box{number}(native_choose{number}(true,native_id{number}(record),record));
	Record{number}[2] array={{record,identity(record)}};
	array[1]=identity(array[0]);var saved=identity(array[1]);
	if(!({checks('whole.first.value')}&&{checks('whole.second.value')}&&{checks('ordinary.first.value')}&&{checks('ordinary.second.value')}&&{checks('saved.first.value')}&&{checks('saved.second.value')})||whole.token!=se_pointer()){{return 2;}}
	return 0;
}}
''')
	parts.append('int main(){int pattern=0;while(pattern<12){'+''.join(f'if(matrix{i}(pattern)!=0){{return {i+1};}}' for i in range(34))+'pattern=pattern+1;}return 0;}')
	return '\n'.join(parts)+'\n'


def all_leaves():
	parts=[elements.IMPORTS,HELPERS,'struct AllLeaves{'+''.join(f'{leaf} field{i};' for i,leaf in enumerate(elements.LEAVES))+'}']
	parts.append('AllLeaves concrete(AllLeaves value){AllLeaves local=value;return local;}')
	declarations=[];checks=[]
	for i,leaf in enumerate(elements.LEAVES):
		base=leaf.split('<')[0];lanes=int(leaf.split('<')[1][:-1]) if '<' in leaf else 1
		value='{'+','.join(elements.scalar_value(base,f'pattern+{lane}') for lane in range(lanes))+'}' if '<' in leaf else elements.scalar_value(base,'pattern')
		declarations.append(f'{leaf} v{i}={value};')
		for root in ['saved','ordinary']:
			for lane in range(lanes):checks.append(elements.scalar_check(base,f'{root}.field{i}'+(f'[{lane}]' if '<' in leaf else ''),f'pattern+{lane}'))
	parts.append('int main(){int pattern=0;while(pattern<12){'+''.join(declarations)+'AllLeaves source={'+','.join(f'field{i}=v{i}' for i in reversed(range(34)))+'};var saved=through_box(identity(source));var ordinary=concrete(source);'+''.join('if(!('+ '&&'.join(checks[i:i+16])+')){return 1;}' for i in range(0,len(checks),16))+'pattern=pattern+1;}return 0;}')
	return '\n'.join(parts)+'\n'


def deep():
	source = elements.deep(64)
	# Keep the ordinary copy and add the generic/control comparison at full depth.
	source = source.replace('int main()', HELPERS+'int main()').replace('var saved=a[1];', 'var original=a[1];var saved=through_box(identity(original));')
	return source


def qualify(compiler, out, collector=None):
	collector = collector or compiler.parent / 'tests/support/astra-stage-collector'
	out.mkdir(parents=True, exist_ok=False)
	companions = {}
	for cc in ['gcc', 'clang']:
		companions[cc] = out/(cc+'-observer.o')
		run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'tests/struct-elem-1/companion.c', '-o', companions[cc]])
	(out/'matrix.astra').write_text(matrix())
	(out/'deep-64.astra').write_text(deep())
	(out/'all-leaves.astra').write_text(all_leaves())
	cases = [('matrix',out/'matrix.astra',0,''),('deep-64',out/'deep-64.astra',0,'A1:2:16\nF1\n'),('transport',FIXTURES/'transport.astra',0,''),('all-leaves',out/'all-leaves.astra',0,'')]
	trace = 'A1:2:16 M0 M20 M0 M20 M0 M20 M0 M20 M30 M31 M40 M41 M42 M43 M44 M50 M51 M0 F1 A2:2:16 M0 F2 A3:2:16 M0 M80 A4:3:16 F3 A5:2:16 M0 M80 A6:3:16 F5 A7:2:16 M0 F7 A8:2:16 M0 F8 R+1 R-1 F6 F4'
	cases.append(('effects',FIXTURES/'effects.astra',0,''.join(event+'\n' for event in trace.split())))
	prelude = 'extern(C) int se_mark(int value);struct S{int x;f64 y;}void discard<T>(T value){}void concrete(S value){}T id<T>(T value){return value;}S control(S value){return value;}struct H{int tag;S payload;int later;}S make(){se_mark(99);S s={x=1,y=2.0d};return s;}'
	for name, body, trace in [
		('discard-bounds','var a=new S[2];discard(a[se_mark(2)]);','A1:2:16 M2'),
		('concrete-discard-bounds','var a=new S[2];concrete(a[se_mark(2)]);','A1:2:16 M2'),
		('discard-null','S* p=null;discard(*p);',''),
		('concrete-discard-null','S* p=null;concrete(*p);',''),
		('destination-bounds','var a=new S[2];a[se_mark(2)]=id(make());','A1:2:16 M2'),
		('source-bounds','var a=new S[2];a[se_mark(0)]=id(a[se_mark(2)]);','A1:2:16 M0 M2'),
		('field-entry-trap','S* p=null;H value={tag=se_mark(11),payload=id(*p),later=se_mark(12)};','M11'),
		('concrete-field-entry-trap','S* p=null;H value={tag=se_mark(11),payload=control(*p),later=se_mark(12)};','M11')]:
		path=out/(name+'.astra');path.write_text(prelude+'int main(){'+body+'return 0;}\n')
		cases.append((name,path,-signal.SIGILL,''.join(event+'\n' for event in trace.split())))
	records = dict(compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), shapes=elements.LEAVES, runs=[], stages=[], machines=[])
	for name, path, status, expected in cases:
		dumps = observations(compiler, collector, [path, *(['--vapi', ROOT / 'tests/struct-elem-1/fixtures/runtime.vapi'] if name == 'effects' else [])], out, name, run, ROOT, public=name in ['basic', 'transport', 'identity', 'mixed', 'boundary', 'effects'])
		for stage in elements.STAGES:
			if stage in ['cfg', 'ssa', 'nabi', 'llvm']:
				assert not re.search(r'GEN1_PLAIN_COPY|type-parameter|generic-call|generic-op', dumps[stage]), (name, stage)
			records['stages'].append(name + ':' + stage)
		ordinal=re.search(r'\(function #(\d+) "main" -> int',dumps['ssa'])[1]
		wrapped=dumps['llvm']+'\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+ordinal+'()\n\tret i32 %r\n}\n'
		for mode, stem, obj in machine_objects(wrapped, out, name, run):
			for cc, observer in companions.items():
				binary=out/(stem+'-'+cc);run([cc,obj,observer,'-Wl,--wrap=calloc,--wrap=free','-o',binary])
				observed=run([binary],status=status);(out/(binary.name+'.stdout')).write_text(observed)
				assert observed==expected,(binary.name,observed,expected)
				records['runs'].append(dict(name=binary.name,status=status,output=observed))
			machine=run(['objdump','-dr',obj]);(out/(stem+'.machine')).write_text(machine)
			if mode=='preserved-O2' and status==0:
				assert 'call' in machine and ('R_X86_64_PC32' in machine or 'R_X86_64_PLT32' in machine),(name,machine)
			(out/(stem+'.symbols')).write_text(run(['readelf','-h','-Ws','-r',obj]))
			(out/(stem+'.size')).write_text(run(['size','-A',obj]));records['machines'].append(stem)
	(out/'results.json').write_text(json.dumps(records,indent='\t')+'\n')
	print(f"{len(records['runs'])} executions, {len(records['stages'])} repeated stages, 34 old value and record shapes")


if __name__=='__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	qualify(Path(sys.argv[1]).resolve(), fresh_output(sys.argv[2]), Path(sys.argv[3]).resolve(strict=True) if len(sys.argv) == 4 else None)
