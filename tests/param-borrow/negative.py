# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Both spellings share noescape, ownership, and conservative overlap rejection."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'tests/param-borrow/fixtures'
SEMANTIC = {
	'resource-conversion': ('u32 f(@R x){return x as u32;}', 'borrowed parameter'),
	'resource-return': ((FIXTURES/'param-borrow-invalid.astra').read_text().replace('(R resource', '(@R resource'), 'borrowed parameter'),
	'resource-local': ('void f(@R x){R copy=x;}', 'borrowed parameter'),
	'resource-var': ('void f(@R x){var copy=x;}', 'borrowed parameter'),
	'resource-store': ('void f(@R x){R local=null;local=x;}', 'borrowed parameter'),
	'resource-unmanaged-foreign': ('extern(C) void raw(R x);void f(@R x){raw(x);}', 'borrowed parameter'),
	'resource-owned-field': ('class Context{owned R r;init(@R x){this.r=x;}}', 'borrowed parameter'),
	'resource-owned-return': ('owned R f(@R x){return x;}', 'requires'),
	'resource-move-borrow': ('void sink(owned R x){}void f(@R x){sink(move x);}', 'must be an owned'),
	'resource-release-borrow': ('void f(@R x){release x;}', 'owned'),
	'resource-implicit-transfer': ('void sink(owned R x){}void f(owned R x){sink(x);}', 'explicit'),
	'class-return': ('class C{}C f(@C x){return x;}', 'results are unsupported'),
	'class-owned-return': ('class C{}owned C f(@C x){return x;}', 'borrowed references'),
	'class-field': ('class C{}class Holder{C field;init(@C x){this.field=x;}}', 'field'),
	'class-owner-alias': ('class C{}void f(owned C x){C copy=x;}', 'persistent alias'),
	'class-move-borrow': ('class C{}void sink(owned C x){}void f(@C x){sink(move x);}', 'nontransferable'),
	'class-implicit-transfer': ('class C{}void sink(owned C x){}void f(owned C x){sink(x);}', 'explicit'),
	'buffer-owned-field': ('class C{owned f64[] a;init(@f64[] x){this.a=x;}}', 'owned field transfer'),
	'buffer-implicit-transfer': ('void sink(owned f64[] x){}void f(owned f64[] x){sink(x);}', 'explicit'),
	'buffer-return': ('f64[] f(@f64[] x){return x;}', 'results are unsupported'),
	'resource-overload': ('void f(@R x){}void f(borrowed R x){}', 'duplicate function'),
	'class-overload': ('class C{}void f(@C x){}void f(borrowed C x){}', 'duplicate function'),
	'slice-overload': ('void f(@f64[] x){}void f(borrowed f64[] x){}', 'duplicate function'),
	'generic-plain-ownable': ('void f<T>(T x) where T:Ownable{}', 'plain T value transport'),
	'generic-borrowed-ownable-count': ('void f<T>(borrowed T x,borrowed T y) where T:Ownable{}', 'generic borrowing requires one borrowed T'),
	'generic-owned-unconstrained': ('void f<T>(owned T x){}', 'requires explicit capability Ownable'),
	'export-resource': ('export(C) void f(R x){}', 'export(C) of resource'),
	'foreign-class': ('class C{}extern(C) void f(C x);', 'unsupported at C boundaries'),
	'foreign-slice': ('extern(C) void f(f64[] x);', 'unsupported at C boundaries'),
	'parameter-var': ('void f(var x){}', 'reserved keyword'),
}
FLOW = {
	'class-owned-result-overlap': ('class C{}owned C relay(@C view,owned C owner){return move owner;}void f(owned C x){owned C result=relay(x,move x);}', 'cannot borrow moved'),
	'class-constructor-overlap': ('class C{}class Holder{init(@C view,owned C owner){}}void f(owned C x){Holder h=Holder.init(x,move x);}', 'cannot borrow moved'),
	'class-empty-baseline': ('class Empty{deinit(){}}void consume(@Empty a,owned Empty b){}void f(){owned Empty e={};consume(e,move e);}', 'cannot borrow moved'),
	'class-no-deinit-baseline': ('class Plain{int value;}int consume(@Plain view,owned Plain owner){owner.value=42;return view.value;}int main(){owned Plain p={value=1};return consume(p,move p);}', 'cannot borrow moved'),
	'class-input-overlap': ('class C{}void sink(@C view,owned C x){}void f(@C view,owned C x){sink(view,move x);}', 'cannot borrow moved'),
	'class-input-alias-overlap': ('class C{}void sink(@C view,owned C x){}void f(@C view,owned C x){C alias=view;sink(alias,move x);}', 'cannot borrow moved'),
	'class-receiver-overlap': ('class C{void sink(owned C x){}void f(owned C x){this.sink(move x);}}', 'cannot borrow moved'),
	'field-replacement-overlap': ('class C{owned R r;init(){this.r=resource(1);}int replace(){this.r=resource(2);return 0;}}void sink(@R r,int n){}void f(@C c){sink(c.r,c.replace());}', 'overlaps'),
}
for name, type_name, prefix in [('resource', 'R', ''), ('class', 'C', 'class C{}'), ('buffer', 'f64[]', '')]:
	FLOW[name+'-overlap'] = (prefix+f'void sink(@{type_name} view,owned {type_name} x){{}}void f(owned {type_name} x){{sink(x,move x);}}', 'cannot borrow moved')
	FLOW[name+'-reverse-overlap'] = (prefix+f'void sink(owned {type_name} x,@{type_name} view){{}}void f(owned {type_name} x){{sink(move x,x);}}', 'cannot borrow moved')
	FLOW[name+'-nested-consume'] = (prefix+f'int consume(owned {type_name} x){{return 0;}}void sink(@{type_name} view,int n){{}}void f(owned {type_name} x){{sink(x,consume(move x));}}', 'cannot borrow moved')
	FLOW[name+'-after-move'] = (prefix+f'void consume(owned {type_name} x){{}}void sink(@{type_name} view){{}}void f(owned {type_name} x){{consume(move x);sink(x);}}', 'cannot borrow moved')
for name, type_name in [('resource', 'R'), ('buffer', 'f64[]')]:
	FLOW[name+'-after-release'] = (f'void sink(@{type_name} view){{}}void f(owned {type_name} x){{release x;sink(x);}}', 'cannot borrow released')
FLOW['class-overlap'] = ((FIXTURES/'param-borrow-overlap.astra').read_text().replace('(C view', '(@C view'), 'cannot borrow moved')


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	records = []
	failures = []
	for cases, stages in [(SEMANTIC, ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']), (FLOW, ['cfg', 'ssa', 'nabi', 'cabi', 'llvm'])]:
		for name, (source, expected) in cases.items():
			messages = {}
			for spelling, qualifier in [('implicit', ''), ('explicit', 'borrowed ')]:
				path = out/(name+'-'+spelling+'.astra'); path.write_text(source.replace('@', qualifier)+'\n')
				for stage in stages:
					p = subprocess.run([str(compiler), '--dump-'+stage, str(path), '--vapi', str(FIXTURES/'runtime.vapi')], capture_output=True, text=True)
					if p.returncode != 1 or p.stdout or expected not in p.stderr:
						failures.append((name, spelling, stage, expected, p.returncode, p.stdout, p.stderr))
					message = p.stderr.split('error: ', 1)[-1]
					if spelling == 'implicit':
						messages[stage] = message
					elif message != messages[stage]:
						failures.append((name, stage, 'diagnostic spelling mismatch', message, messages[stage]))
					records.append(dict(name=name, spelling=spelling, stage=stage, diagnostic=p.stderr.replace(str(out), 'negative')))
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	assert not failures, json.dumps(failures, indent='\t')
	print(f'{len(records)} negative stage checks; {len(SEMANTIC)+len(FLOW)} cases; identical diagnostics for both spellings')


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
