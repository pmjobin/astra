#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-bound actual LLVM signature probes; explicitly no effect ELF count."""
import argparse
import json
from pathlib import Path
import time
from state import ROOT, C0, sha, read, load_module, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', default='final'); a = p.parse_args(); assert a.version.isalnum()
	state = load_module('r2_abi_qualify_state', ROOT/'tests/selfhost-effects/r2-state.py')
	leaf = state.RUNTIME/('abi-controls-'+a.version+'-'+a.mode); build = state.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(p) == expected for group in ('sources', 'tools') for p, expected in identity['identity'][group].items())
	fault = '[ExceptionRoot] class Fault { readonly string bytes; init(string text) { this.bytes = text; } virtual property string message { get { return this.bytes; } } }\n'
	cases = {
		'scalar': ('int obtain(int input) throws Error { return input; }\n', True),
		'void': ('void obtain(bool input) throws Error { if (input) { throw new Error("x"); } }\n', True),
		'zero-void': ('void obtain() throws Error { throw new Error("x"); }\n', True),
		'zero-scalar': ('int obtain() throws Error { return 42; }\n', True),
		'mixed': ('f64 obtain(i8 a, u16 b, i64 c, f32 d, f64 e, bool f) throws Error { return e; }\n', True),
		'other-root': (fault+'int obtain(int input) throws Fault { return input; }\n', True),
		'owned-buffer': ('owned int[] obtain() throws Error { return new int[2]; }\n', False),
		'record': ('struct Pair { int left; int right; }\nPair obtain() throws Error { Pair p = {left = 20, right = 22}; return p; }\n', False),
		'heap-class': ('class Parcel { init() {} }\nowned Parcel obtain() throws Error { var p = new Parcel(); return move p; }\n', False),
		'generic': ('T obtain<T>(T input) throws Error { return input; }\n', False),
		'nonthrowing': ('int obtain(int input) { return input; }\n', False),
	}
	commands = []; results = []
	def run(argv, label, expected):
		start = time.monotonic(); argv = list(map(str, argv))
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *argv], cwd=ROOT, capture_output=True, timeout=180)
		(leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=label, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(label+'.stdout')), stderr_sha256=sha(leaf/(label+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == expected, (label, r.returncode, r.stderr[-2500:], r.stdout[-1000:]); return r
	for name, (source, admitted) in cases.items():
		path = leaf/(name+'.astra'); path.write_text(source+'int main() { return 42; }\n')
		inputs = [path] if name == 'other-root' else [path, ROOT/'lib/astra/base/errors.astra']
		run([C0, '--check', *inputs], name+'-C0', 0)
		r = run([a.component, '--r2-abi', *inputs], name+'-Astra-ABI', 0 if admitted else 3)
		row = dict(name=name, source_sha256=sha(path), declaration_shape_admitted=admitted, effect_ELF=False)
		if admitted:
			lines = r.stdout.decode().splitlines(); hex_lines = [s.split()[1] for s in lines if s.startswith('LLVM_HEX ')]
			assert len(hex_lines) == 1
			ir = bytes.fromhex(hex_lines[0]); irpath = build/(name+'.ll'); irpath.write_bytes(ir)
			run(['llvm-as', irpath, '-o', build/(name+'.bc')], name+'-assemble', 0)
			run(['opt', '-passes=verify', '-disable-output', irpath], name+'-verify', 0)
			assert lines.count('CHECKED_ABI_MODEL_MUTATIONS 13 VALID_RESTORED') == 1
			assert len([s for s in lines if s.startswith('CHECKED_ABI_PHYSICAL_REJECT ')]) == 7
			assert 'SIGNATURES_ONLY; FLOW_ERROR_CONTROL_PENDING' in lines
			row.update(LLVM_sha256=sha(irpath), model_mutations=13, LLVM_valid_signature_alternatives=7)
		results.append(row)
		(leaf/'result.json').write_text(json.dumps(dict(status='SIGNATURE_CONTRACT_ONLY', programs=results, component_sha256=sha(a.component), new_Astra_effect_ELFs=0, new_cross_stage_effect_mutation_categories=0, new_error_path_physical_alternatives=0, limitation='Actual LLVM declaration shapes and source/plan correspondence only. Fixture bodies are unreachable. Alternatives do not implement or qualify success publication, ownership, error allocation, calls or cleanup.'), indent=2)+'\n')
		print(a.mode, name, 'physical signature admitted' if admitted else 'signature subset deferred', flush=True)


if __name__ == '__main__':
	main()
