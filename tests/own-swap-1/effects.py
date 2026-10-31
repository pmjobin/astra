# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Terminal null checks, capture order and actual final LLVM phi predecessors."""
from pathlib import Path
import json
import re
import signal
import sys
sys.dont_write_bytecode = True
from execute import ROOT, instrument, run, trace

SOURCE = '''class C{owned int[] a;owned int[] b;init(int n){this.a=new int[n];this.b=new int[n+1];}}
int rotate(borrowed C a,borrowed C b){swap(a.a,b.a);return 0;}
int branch(borrowed C a,borrowed C b,bool flag){var n=1;if(flag){swap(a.a,b.a);n=len(a.a);}else{n=len(b.a);}return n;}
'''


def qualify(compiler, out):
	out.mkdir(parents=True, exist_ok=False); (out / 'input.astra').write_text(SOURCE)
	ssa = run([compiler, '--dump-ssa', 'input.astra'], out); ir = run([compiler, '--dump-llvm', 'input.astra'], out)
	(out / 'input.ssa').write_text(ssa); (out / 'input.llvm').write_text(ir)
	ids = {name: ordinal for ordinal, name in re.findall(r'\(function #(\d+) "([^"]+)"', ssa)}
	# Supplemental internal object emission preserves callable source functions.
	# This is not a new public compiler flag or a timed application configuration.
	for mode in ['O0', 'O2', 'O2-fma']:
		inp, optimized, obj = [out / ('unobserved-' + mode + extension) for extension in ['-input.ll', '.ll', '.o']]
		inp.write_text(re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M))
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp, '-o', optimized], out)
		run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'O2-fma' else []), optimized, '-o', obj], out)
		machine = run(['objdump', '-dr', obj], out); (out / ('unobserved-' + mode + '.machine')).write_text(machine)
		body = re.search(r'<astra.fn.' + ids['rotate'] + r'>:\n(.*?)(?=\n[0-9a-f]+ <|\Z)', machine, re.S)[1]
		assert not re.search(r'\bcall\w*\b|memcpy|memmove|calloc|free', body), body
		(out / ('unobserved-' + mode + '.symbols')).write_text(run(['readelf', '-h', '-Ws', '-r', obj], out))
	ctor = re.search(r'define internal fastcc void @astra.ctor.(\d+)\(', ir)[1]
	# Test-only probes are immediately before actual receiver guards, outside the
	# closed exchange. They do not claim new public receiver-expression syntax.
	function = re.search(r'define internal fastcc i32 @astra.fn.' + ids['rotate'] + r'\(.*?\n}', ir, re.S)[0]
	probed = re.sub(r'(?m)^(  %object.guard\d+.null = icmp eq ptr %p([01]), null)$', lambda m: '  call i32 @se_mark(i32 ' + str(100 + 100 * int(m[2])) + ')\n' + m[1], function)
	probed = probed.replace('  call void @llvm.trap()', '  call void @os_trap()\n  call void @llvm.trap()')
	ir = ir.replace(function, probed)
	wrapped, regions = instrument(ir)
	wrapped += '\ndeclare i32 @se_mark(i32)\ndeclare void @os_watch(ptr, ptr, ptr, ptr)\ndeclare void @os_trap()\ndeclare void @os_layout(ptr, ptr, ptr)\n'
	companions = {}
	for cc in ['gcc', 'clang']:
		companions[cc] = out / (cc + '.o'); run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', ROOT / 'tests/own-swap-1/observer.c', '-o', companions[cc]], out)
	records = []
	for name in ['distinct', 'same-slot', 'left-null', 'right-null', 'both-null', 'branch-true', 'branch-false']:
		left = 'null' if name in ['left-null', 'both-null'] else '%a'
		right = 'null' if name in ['right-null', 'both-null'] else '%a' if name == 'same-slot' else '%b'
		call = f'call fastcc i32 @astra.fn.{ids["branch"]}(ptr %a, ptr %b, i1 ' + ('true)' if name == 'branch-true' else 'false)') if name.startswith('branch') else f'call fastcc i32 @astra.fn.{ids["rotate"]}(ptr {left}, ptr {right})'
		entry = f'''
define i32 @main(){{
	%a=alloca %astra.class.0, align 8
	%b=alloca %astra.class.0, align 8
	call fastcc void @astra.ctor.{ctor}(ptr %a,i32 2)
	call fastcc void @astra.ctor.{ctor}(ptr %b,i32 5)
	%ac=getelementptr %astra.class.0,ptr %a,i32 0,i32 0,i32 1
	%bc=getelementptr %astra.class.0,ptr %b,i32 0,i32 0,i32 1
	%second=getelementptr %astra.class.0,ptr %a,i32 0,i32 1
	call void @os_layout(ptr %a,ptr %a,ptr %second)
	call void @os_watch(ptr %a,ptr %ac,ptr %b,ptr %bc)
	%result={call}
	call fastcc void @astra.dtor.0(ptr %b)
	call fastcc void @astra.dtor.0(ptr %a)
	ret i32 0
}}
'''
		status = -signal.SIGILL if name.endswith('null') else 0
		prefix = 'A1:2:4\nA2:3:4\nA3:5:4\nA4:6:4\nL0:16\n'
		middle = 'M100\n' + ('' if name in ['left-null', 'both-null'] else 'M200\n')
		if status:
			expected = prefix + middle + 'T-unchanged\n'
		else:
			swapped = name in ['distinct', 'branch-true']
			expected = prefix + ('' if name.startswith('branch') else middle) + ('X1:2:3:5\n' if swapped else 'X1:2:1:2\n' if name == 'same-slot' else '') + ('F4\nF1\nF2\nF3\n' if swapped else 'F4\nF3\nF2\nF1\n')
		for mode in ['O0', 'O2', 'O2-fma', 'preserved-O2']:
			stem = name + '-' + mode; inp, opt, obj = [out / (stem + ext) for ext in ['-input.ll', '.ll', '.o']]
			text = wrapped + entry
			if mode == 'preserved-O2':
				text = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', text, flags=re.M)
			inp.write_text(text)
			run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp, '-o', opt], out)
			run(['opt', '-passes=verify', '-disable-output', opt], out)
			run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'O2-fma' else []), opt, '-o', obj], out)
			for cc, observer in companions.items():
				binary = out / (stem + '-' + cc); run([cc, obj, observer, '-Wl,--wrap=calloc,--wrap=free', '-o', binary], out)
				observed = run([binary], out, status); (out / (binary.name + '.stdout')).write_text(observed); assert observed == expected, (binary.name, observed, expected)
				records.append(dict(name=binary.name, status=status, category='normal' if not status else 'fatal-nonunwinding', **trace(observed, status == 0)))
			(out / (stem + '.machine')).write_text(run(['objdump', '-dr', obj], out))
			# Retain the unmodified source emission's actual phi inputs. LLVM verifies
			# that guard continuation blocks, rather than pre-split source blocks, feed it.
	phis = [line.strip() for line in ir.splitlines() if ' = phi ' in line]
	assert phis and any('object.guard' in line for line in phis), phis
	(out / 'results.json').write_text(json.dumps(dict(runs=records, regions=regions, phi_edges=phis), indent='\t') + '\n')
	print(f'{len(records)} ordered effect/terminal-trap executions; {len(phis)} raw final phi witnesses')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
