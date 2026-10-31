# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native owning payload values, exact floating bits, and active drop order."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import re
import signal
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('enum_own_elements', ROOT / 'tests/struct-elem-1/execute.py')
elements = importlib.util.module_from_spec(spec)
spec.loader.exec_module(elements)

def run(command, output, expected_status=0):
	result = subprocess.run(list(map(str, command)), cwd=output, capture_output=True, env={**os.environ,'CCACHE_DISABLE':'1'})
	assert result.returncode == expected_status and not result.stderr, (command,result.returncode,result.stderr.decode())
	return result.stdout.decode()

def matrix():
	parts = [elements.IMPORTS]; expected = []; owner = 0
	for i, leaf in enumerate(elements.LEAVES):
		base = leaf.split('<')[0]; lanes = int(leaf.split('<')[1][:-1]) if '<' in leaf else 1
		value = '{'+','.join(elements.scalar_value(base,f'pattern+{lane}') for lane in range(lanes))+'}' if lanes > 1 else elements.scalar_value(base,'pattern')
		def check(name):
			return '&&'.join(elements.scalar_check(base,name+(f'[{lane}]' if lanes>1 else ''),f'pattern+{lane}') for lane in range(lanes))
		parts.append(f'''struct R{i}{{u8 before;{leaf} value;u8 after;}}
enum E{i}{{Ready(owned {leaf}[] first,owned R{i}[] second),Empty}}
enum Outer{i}{{Child(E{i} child),Empty}}
E{i} relay{i}(E{i} input){{return move input;}}
owned {leaf}[] take{i}(Outer{i} input){{match(move input){{case Outer{i}.Child(child):{{match(move child){{case E{i}.Ready(first,_):{{return move first;}}else:{{return new {leaf}[0];}}}}}}else:{{return new {leaf}[0];}}}}}}
int shape{i}(int n){{int pattern=0;while(pattern<12){{
	owned {leaf}[] first=new {leaf}[n];owned R{i}[] second=new R{i}[n];
	if(n>0){{{leaf} expected={value};first[n-1]=expected;second[n-1].value=expected;second[n-1].before=91;second[n-1].after=117;}}
	var owner=E{i}.Ready(move first,move second);owner=relay{i}(move owner);
	match(owner){{case E{i}.Ready(a,b):{{if(len(a)!=n||len(b)!=n){{return 1;}}if(n>0){{var saved=b[n-1];if(!({check('a[n-1]')}&&{check('saved.value')})||saved.before!=91||saved.after!=117){{return 2;}}}}}}else:{{return 3;}}}}
	var outer=Outer{i}.Child(move owner);owned {leaf}[] returned=take{i}(move outer);
	if(len(returned)!=n){{return 4;}}if(n>0&&!({check('returned[n-1]')})){{return 5;}}
	pattern=pattern+1;
}}return 0;}}
''')
	parts.append('int main(){'+''.join(f'if(shape{i}(0)!=0||shape{i}(2)!=0||shape{i}(17)!=0){{return {i+1};}}' for i in range(len(elements.LEAVES)))+'return 0;}')
	for leaf in elements.LEAVES:
		info=elements.layout(leaf)
		for n in [2,17]:
			for _ in range(12):
				owner+=2; expected += [f'A{owner-1}:{n}:{info["size"]}',f'A{owner}:{n}:{info["stride"]}',f'F{owner}',f'F{owner-1}']
	return '\n'.join(parts)+'\n', '\n'.join(expected)+'\n'

LIFECYCLE = '''enum S{Ready(owned int[] a,owned int[] b),Empty} enum O{Child(S child,owned int[] tail),Empty}
S relay(S value){return move value;}
int main(){
	{var state=S.Ready(new int[2],new int[3]);}
	{var state=S.Ready(new int[4],new int[5]);state=S.Ready(new int[6],new int[7]);state=relay(move state);}
	{var outer=O.Child(S.Ready(new int[8],new int[9]),new int[10]);match(move outer){case O.Child(child,_):{match(move child){case S.Ready(a,_):{if(len(a)!=8){return 1;}}else:{return 2;}}}else:{return 3;}}}
	{var state=S.Ready(new int[11],new int[12]);match(move state){else:{}}}
	return 0;
}'''
LIFECYCLE_TRACE = 'A1:2:4 A2:3:4 F2 F1 A3:4:4 A4:5:4 A5:6:4 A6:7:4 F4 F3 F6 F5 A7:8:4 A8:9:4 A9:10:4 F9 F8 F7 A10:11:4 A11:12:4 F11 F10'

def main(compiler, output):
	output.mkdir(parents=True,exist_ok=True)
	observer=output/'observer.o'; run(['gcc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',ROOT/'tests/struct-elem-1/companion.c','-o',observer],output)
	code, expected=matrix(); records=[]
	for name,code,expected in [('matrix',code,expected),('lifecycle',LIFECYCLE,'\n'.join(LIFECYCLE_TRACE.split())+'\n')]:
		path=output/(name+'.astra'); path.write_text(code)
		ir=run([compiler,'--dump-llvm',path],output); ssa=run([compiler,'--dump-ssa',path],output)
		ordinal=re.search(r'\(function #(\d+) "main" -> int',ssa)[1]
		ir += '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+ordinal+'()\n\tret i32 %r\n}\n'
		for mode in ['O0','O2','O2-fma','preserved-O2']:
			input_ir=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M) if mode=='preserved-O2' else ir
			inp=output/'input.ll'; final=output/'optimized.ll'; obj=output/'program.o'; inp.write_text(input_ir)
			run(['opt','-passes=verify' if mode=='O0' else '-passes=default<O2>','-S',inp,'-o',final],output)
			run(['opt','-passes=verify','-disable-output',final],output)
			run(['llc','-O0' if mode=='O0' else '-O2','-filetype=obj','-relocation-model=pic',*(['-mattr=+fma'] if mode=='O2-fma' else []),final,'-o',obj],output)
			for cc in ['gcc','clang']:
				binary=output/(name+'-'+mode+'-'+cc); run([cc,obj,observer,'-Wl,--wrap=calloc,--wrap=free','-o',binary],output)
				observed=run([binary],output); assert observed==expected, (name,mode,cc,observed[:500],expected[:500])
				records.append({'name':name,'mode':mode,'linker':cc,'exit':0,'allocations':sum(line.startswith('A') for line in observed.splitlines()),'trace_sha256':hashlib.sha256(observed.encode()).hexdigest(),'binary_bytes':binary.stat().st_size})
	path=output/'fatal-prefix.astra'; path.write_text('extern(C) void se_fail(); enum E{Ready(owned int[] a,owned int[] b)} int fail_count(){se_fail();return 3;} int main(){var owner=E.Ready(new int[2],new int[fail_count()]);return 0;}')
	ir=run([compiler,'--dump-llvm',path],output); ssa=run([compiler,'--dump-ssa',path],output); ordinal=re.search(r'\(function #(\d+) "main" -> int',ssa)[1]
	ir += '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+ordinal+'()\n\tret i32 %r\n}\n'; inp=output/'input.ll'; final=output/'optimized.ll'; obj=output/'program.o'; inp.write_text(ir)
	for mode in ['O0','O2']:
		run(['opt','-passes=verify' if mode=='O0' else '-passes=default<O2>','-S',inp,'-o',final],output); run(['llc','-O0' if mode=='O0' else '-O2','-filetype=obj','-relocation-model=pic',final,'-o',obj],output)
		binary=output/('fatal-prefix-'+mode); run(['gcc',obj,observer,'-Wl,--wrap=calloc,--wrap=free','-o',binary],output); observed=run([binary],output,-signal.SIGILL); assert observed=='A1:2:4\nOOM\n'
		records.append({'name':'fatal-prefix','mode':mode,'category':'fatal-nonunwinding','exit':-signal.SIGILL,'allocations':1,'trace_sha256':hashlib.sha256(observed.encode()).hexdigest()})
	(output/'checks.json').write_text(json.dumps({'shapes':elements.LEAVES,'array_and_record_elements':68,'floating_patterns':12,'runs':records},indent=2)+'\n')
	print(json.dumps({'normal_native_runs':sum(row.get('category')!='fatal-nonunwinding' for row in records),'fatal_prefix_runs':2,'element_shapes':68,'matrix_allocations_per_run':1632,'lifecycle_allocations_per_run':11}))

if __name__=='__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
