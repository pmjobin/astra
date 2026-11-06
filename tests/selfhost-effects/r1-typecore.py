#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent source-type controls; none count as Astra effect executables."""
import argparse
import json
from pathlib import Path
import time
from state import ROOT, C0, bounded_run, read, sha

BASE = ROOT.parent/'codex/work/astra'
ERROR = ROOT/'lib/astra/base/errors.astra'
FACTORY = 'int produce(int input) throws Error { return input; }\n'


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); p.add_argument('--full-cli', action='store_true'); a = p.parse_args()
	leaf = BASE/'runtime/effects25-r1'/('typecore-controls-'+a.version); leaf.mkdir(exist_ok=False)
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	cases = {
		'scalar': (FACTORY+'void relay() throws Error { var value = produce(42); }\nint main() { return 42; }\n', 0, True),
		'other-name': ('int unrelated(int input) throws RuntimeError { return input; }\nvoid forward() throws Error { var value = unrelated(42); }\nint main() { return 42; }\n', 0, True),
		'bool-argument': (FACTORY+'void relay() throws Error { var value = produce(true); }\nint main() { return 42; }\n', 1, False),
		'text-argument': (FACTORY+'void relay() throws Error { var value = produce("wrong"); }\nint main() { return 42; }\n', 1, False),
		'nominal-argument': ('class Parcel { init() {} }\n'+FACTORY+'void relay() throws Error { var parcel = new Parcel(); var value = produce(parcel); }\nint main() { return 42; }\n', 1, False),
		'unrelated-bound': ('class Pretender { init() {} }\nint produce(int input) throws Pretender { return input; }\nint main() { return 42; }\n', 1, False),
		'scalar-bound': ('int produce(int input) throws int { return input; }\nint main() { return 42; }\n', 1, False),
		'nonthrowing': ('int produce(int input) { return input; }\nint main() { return produce(42); }\n', 0, False),
		'caught': (FACTORY+'void relay() { try { produce(42); } catch (Error error) {} }\nint main() { return 42; }\n', 0, True),
		'unhandled': (FACTORY+'void relay() { produce(42); }\nint main() { return 42; }\n', 1, False),
		'open-bound': (FACTORY+'void relay() { try { produce(42); } catch (RuntimeError error) {} }\nint main() { return 42; }\n', 1, False),
		'catch-order': (FACTORY+'void relay() { try { produce(42); } catch (Error error) {} catch (RuntimeError narrow) {} }\nint main() { return 42; }\n', 1, False),
		'own-handler': (FACTORY+'void relay() { try { produce(42); } catch (Error error) { produce(42); } }\nint main() { return 42; }\n', 1, False),
		'sibling-handler': (FACTORY+'void relay() { try { produce(42); } catch (RuntimeError narrow) { produce(42); } catch (Error error) {} }\nint main() { return 42; }\n', 1, False),
		'rethrow': (FACTORY+'void relay() throws Error { try { produce(42); } catch (Error error) { throw; } }\nint main() { return 42; }\n', 0, True),
		'bare-outside': ('void relay() throws Error { throw; }\nint main() { return 42; }\n', 1, False),
		'borrowed-throw': (FACTORY+'void relay() throws Error { try { produce(42); } catch (Error error) { throw error; } }\nint main() { return 42; }\n', 1, False),
		'catch-move': (FACTORY+'void relay() throws Error { try { produce(42); } catch (Error error) { throw move error; } }\nint main() { return 42; }\n', 1, False),
		'new-error': ('void relay() throws Error { throw new RuntimeError("x"); }\nint main() { return 42; }\n', 0, False),
		'replacement': (FACTORY+'void relay() throws Error { try { produce(42); } catch (Error error) { throw new RuntimeError("replacement"); } }\nint main() { return 42; }\n', 0, True),
		'other-root': ('[ExceptionRoot] class Fault { readonly string bytes; init(string text) { this.bytes = text; } virtual property string message { get { return this.bytes; } } }\nint obtain(int input) throws Fault { return input; }\nvoid relay() throws Fault { var value = obtain(42); }\nint main() { return 42; }\n', 0, True),
	}
	commands = []; results = []
	for name, (source, expected, conditional) in cases.items():
		path = leaf/(name+'.astra'); path.write_text(source)
		inputs = [path] if name == 'other-root' else [path, ERROR]
		row = dict(name=name, sources=[dict(path=str(p), sha256=sha(p)) for p in inputs])
		option = ('--r1-type-mutations' if conditional else '--r1-types') if a.full_cli else ('--mutations' if conditional else '--check')
		for label, argv in [('C0', [C0, '--check', *inputs]), ('Typecore', [a.component, option, *inputs])]:
			start = time.monotonic(); r = bounded_run(list(map(str, argv)), cwd=ROOT, capture_output=True, timeout=120)
			out = leaf/(name+'-'+label+'.stdout'); err = leaf/(name+'-'+label+'.stderr'); out.write_bytes(r.stdout); err.write_bytes(r.stderr)
			commands.append(dict(name=name+'-'+label, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=sha(out), stderr_sha256=sha(err)))
			(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
			assert r.returncode == expected, (name, label, r.returncode, r.stderr[-2000:], r.stdout[-2000:])
			if label == 'Typecore':
				phase_codes = {'unhandled':4, 'open-bound':4, 'catch-order':3, 'own-handler':4, 'sibling-handler':4, 'bare-outside':5, 'borrowed-throw':6, 'catch-move':6}
				if name in phase_codes: assert ('EFFECT_SOURCE_FAILURE '+str(phase_codes[name])).encode() in r.stdout, (name, r.stdout[-2000:])
				assert (b'CONDITIONAL_CALL_VERIFIED; FLOW_EFFECT_PENDING' in r.stdout) == conditional
				if conditional: assert b'TYPECORE_EFFECT_MUTATIONS 12 VALID_RESTORED' in r.stdout
			row[label] = dict(exit=r.returncode, stdout_sha256=sha(out), stderr_sha256=sha(err))
		results.append(row)
		(leaf/'result.json').write_text(json.dumps(dict(status='TYPECORE_CONTROLS_ONLY', component_sha256=sha(a.component), cases=results, new_Astra_effect_programs=0, model_mutations=12, limitation='Independent nominal/argument checks only; Flow/Core/CFG/SSA/LLVM effect admission remains unqualified'), indent=2)+'\n')
		print(name, 'C0/Typecore matched', flush=True)


if __name__ == '__main__':
	main()
