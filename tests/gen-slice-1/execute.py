# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Ordinary source algorithms, exact leaves, guarded owners and separate observers."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import signal
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/support'))
from pipeline import observations, machine_objects
spec = importlib.util.spec_from_file_location('elements', ROOT / 'tests/struct-elem-1/execute.py')
elements = importlib.util.module_from_spec(spec)
spec.loader.exec_module(elements)
run = elements.run
LIBRARY = ROOT / 'lib/astra/base/slices.astra'
FIXTURES = ROOT / 'tests/gen-slice-1/fixtures'
HELPERS = '''struct Box<T>{T value;}
T element_at<T>(T[] values,int index){return values[index];}
void seed_capture<T>(T[] values,T seed,T replacement){values[0]=replacement;fill(values,seed);}
T through<T>(T[] first,T[] second,int index){T saved=element_at(first,index);Box<T> box={value=second[index]};return box.value;}
'''


def matrix():
	parts = [elements.IMPORTS, HELPERS]
	for number, leaf in enumerate(elements.LEAVES):
		base = leaf.split('<')[0]
		lanes = int(leaf.split('<')[1][:-1]) if '<' in leaf else 1
		def value(ordinal):
			return '{'+','.join(elements.scalar_value(base, f'{ordinal}+{lane}') for lane in range(lanes))+'}' if '<' in leaf else elements.scalar_value(base, ordinal)
		def checks(value, ordinal):
			return '&&'.join(elements.scalar_check(base, value+(f'[{lane}]' if '<' in leaf else ''), f'{ordinal}+{lane}') for lane in range(lanes))
		parts.append(f'''struct Record{number}{{u8 before;{leaf} value;u8 after;}}
int matrix{number}(int n){{
	var scalars=new {leaf}[n];var records=new Record{number}[n];
	int pattern=0;while(pattern<12){{
		{leaf} one={value('pattern')};{leaf} two={value('pattern+1')};
		Record{number} record={{before=91,value=one,after=117}};
		fill<{leaf}>(scalars,one);fill(records,record);
		if(n>0){{
			scalars[n-1]=two;swap_elements(scalars,0,n-1);
			var swapped=element_at(scalars,0);if(!({checks('swapped','pattern+1')})){{return 1;}}
			fill(scalars,one);fill(records,records[0]);Record{number} replacement={{before=91,value=two,after=117}};seed_capture(records,records[0],replacement);swap_elements(records,0,n-1);
			int i=0;while(i<n){{var s=through(scalars,scalars,i);var r=through(records,records,i);
				if(!({checks('s','pattern')}&&{checks('r.value','pattern')})||r.before!=91||r.after!=117){{return 2;}}i=i+1;}}
			var saved=element_at(records,n-1);Box<Record{number}> boxed={{value=saved}};Box<Record{number}>[2] boxes={{boxed,boxed}};
			fill(slice(boxes),boxed);swap_elements(slice(boxes),0,1);var result=element_at(slice(boxes),1);
			if(!({checks('result.value.value','pattern')})){{return 3;}}
		}}
		pattern=pattern+1;
	}}
	if(n>0){{var saved=element_at(records,n-1);release records;
		if(!({checks('saved.value','11')})||saved.before!=91||saved.after!=117){{return 4;}}}}
	return 0;
}}
''')
	parts.append('int main(){int j=0;while(j<4){int n=se_count(j);'+''.join(f'if(matrix{i}(n)!=0){{return {i+1};}}' for i in range(34))+'j=j+1;}return 0;}')
	trace = []; owner = 0
	for count in [1, 2, 17]:
		for leaf in elements.LEAVES:
			stride = elements.layout(leaf)['size']; owner += 2
			trace += [f'A{owner-1}:{count}:{stride}', f'A{owner}:{count}:{3*stride}', f'F{owner}', f'F{owner-1}']
	return '\n'.join(parts)+'\n', '\n'.join(trace)+'\n'


def qualify(compiler, out, collector=None):
	collector = collector or compiler.parent / 'tests/support/astra-stage-collector'
	out.mkdir(parents=True, exist_ok=False)
	shutil.copyfile(LIBRARY, out/'slices.astra')
	companions = {}
	for cc in ['gcc','clang']:
		companions[cc] = out/(cc+'-observer.o')
		run([cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-c',ROOT/'tests/gen-slice-1/companion.c','-o',companions[cc]])
	text, trace = matrix(); (out/'matrix.astra').write_text(text)
	deep = elements.deep(64).replace('int main()', HELPERS+'int main()').replace('a[1]=fixed[0];var saved=a[1];','fill(a,fixed[0]);swap_elements(a,0,1);var saved=element_at(a,1);')
	(out/'deep-64.astra').write_text(deep)
	cases = [('matrix',out/'matrix.astra',0,trace),('deep-64',out/'deep-64.astra',0,'A1:2:16\nF1\n'),('basic',FIXTURES/'basic.astra',0,''),('capabilities',FIXTURES/'capabilities.astra',0,'A1:2:1\nF1\n')]
	trace = 'A1:2:16 M7 M0 M1 M0 M1 A2:3:16 F1 M2 F2 A3:2:16 M0 M80 A4:3:16 F3 M0 M2 M0 M3 M11 M19 M1 M4 M0 M23 M70 M71 F4'
	cases.append(('effects',FIXTURES/'effects.astra',0,''.join(event+'\n' for event in trace.split())))
	prelude = 'extern(C) void gs_watch();extern(C) int se_mark(int n);struct S{int x;f64 y;}T at<T>(T[] a,int i){return a[i];}void discard<T>(T x){}void saved_count<T>(T[] a,T[] b){T[] alias=a;T[] saved=alias;alias=b;T value=saved[1];}S make(){se_mark(99);S value={x=1,y=2.0d};return value;}'
	for name, body, trace in [
		('saved-view-count','S[2] fixed={{x=1,y=1.0d},{x=2,y=2.0d}};saved_count(slice(fixed,0,1),slice(fixed));',''),
		('negative-index','var a=new S[2];discard(at(a,se_mark(-1)));','A1:2:16 M-1'),
		('count-index','var a=new S[2];discard(at(a,se_mark(2)));','A1:2:16 M2'),
		('empty-index','var a=new S[0];discard(at(a,se_mark(0)));','M0'),
		('swap-first','var a=new S[2];a[0].x=11;a[1].x=17;gs_watch();swap_elements(a,se_mark(2),se_mark(0));','A1:2:16 M2 M0'),
		('swap-second','var a=new S[2];a[0].x=11;a[1].x=17;gs_watch();swap_elements(a,se_mark(0),se_mark(2));','A1:2:16 M0 M2'),
		('swap-same-invalid','var a=new S[2];a[0].x=11;a[1].x=17;gs_watch();swap_elements(a,se_mark(2),se_mark(2));','A1:2:16 M2 M2'),
		('destination','var a=new S[2];a[se_mark(2)]=at(a,se_mark(0));','A1:2:16 M2'),
		('source','var a=new S[2];a[0].x=11;a[1].x=17;gs_watch();a[se_mark(0)]=at(a,se_mark(2));','A1:2:16 M0 M2'),
		('empty-fill-value','var a=new S[0];fill(a,make());','M99'),
		('short-circuit','var a=new int[0];if(false&&at(a,se_mark(0))==0){return 1;}',''),
	]:
		path=out/(name+'.astra');path.write_text(prelude+'int main(){'+body+'return 0;}\n')
		cases.append((name,path,0 if name in ['empty-fill-value','short-circuit'] else -signal.SIGILL,''.join(event+'\n' for event in trace.split())))
	records=dict(compiler=str(compiler),compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),shapes=elements.LEAVES,runs=[],stages=[],machines=[])
	for name,path,status,expected in cases:
		if path.parent != out:
			shutil.copyfile(path,out/(name+'.astra'));path=out/(name+'.astra')
		dumps = observations(compiler, collector, ['slices.astra', path.name], out, name, run, out, public=name in ['basic', 'transport', 'identity', 'mixed', 'boundary', 'effects'])
		for stage in elements.STAGES:
			if stage in ['cfg', 'ssa', 'nabi', 'llvm']:
				assert not re.search(r'GEN1_PLAIN_COPY|type-parameter|generic-call|generic-op|slice-element #', dumps[stage]), (name, stage)
			records['stages'].append(name + ':' + stage)
		ordinal=re.search(r'\(function #(\d+) "main" -> int',dumps['ssa'])[1]
		wrapped=dumps['llvm']+'\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+ordinal+'()\n\tret i32 %r\n}\n'
		for mode, stem, obj in machine_objects(wrapped, out, name, run):
			for cc,observer in companions.items():
				binary=out/(stem+'-'+cc);run([cc,obj,observer,'-Wl,--wrap=calloc,--wrap=free','-o',binary])
				observed=run([binary],status=status);(out/(binary.name+'.stdout')).write_text(observed)
				assert observed==expected,(binary.name,observed,expected)
				records['runs'].append(dict(name=binary.name,status=status,output=observed))
			machine=run(['objdump','-dr',obj]);(out/(stem+'.machine')).write_text(machine)
			if mode=='preserved-O2' and name in ['matrix','effects','deep-64']:
				assert 'call' in machine and ('R_X86_64_PC32' in machine or 'R_X86_64_PLT32' in machine)
			(out/(stem+'.symbols')).write_text(run(['readelf','-h','-Ws','-r',obj]));(out/(stem+'.size')).write_text(run(['size','-A',obj]));records['machines'].append(stem)
	(out/'results.json').write_text(json.dumps(records,indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['stages'])} repeated stages; exact 34-element matrix")


if __name__=='__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	qualify(Path(sys.argv[1]).resolve(), fresh_output(sys.argv[2]), Path(sys.argv[3]).resolve(strict=True) if len(sys.argv) == 4 else None)
