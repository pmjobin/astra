#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent executable C0 witnesses; Astra refusal is recorded separately."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import bounded_run, ROOT, RUNTIME, BUILD, C0, sha

FAIL = 'int leaf(int mode) throws Error { if (mode < 0) { throw new Error("recover"); } return mode + 40; }\n'
CLASS = 'class Parcel { int value; init(int value) { this.value = value; } }\n'
FACTORY = CLASS+'owned Parcel make(int value) throws Error { var parcel = new Parcel(value); if (value < 0) { throw new Error("factory"); } return move parcel; }\n'


def corpus():
	return {
		'direct': FAIL+'int main() { try { leaf(-1); } catch (Error error) { if (error.message == "recover") return leaf_ok(); } return 1; }\nint leaf_ok() { return 42; }\n',
		'forward': FAIL+'int relay(int mode) throws Error { return leaf(mode); }\nint main() { try { relay(-1); } catch (Error error) { if (error.message.byte_length == 7) return 42; } return 1; }\n',
		'nested-catch': FAIL+'int relay() throws Error { try { return leaf(-1); } catch (RuntimeError error) { return 1; } }\nint main() { try { relay(); } catch (Error error) { if (error.message == "recover") return 42; } return 2; }\n',
		'rethrow': FAIL+'int relay() throws Error { try { return leaf(-1); } catch (Error error) { if (error.message != "recover") return 1; throw; } }\nint main() { try { relay(); } catch (Error error) { if (error.message == "recover") return 42; } return 2; }\n',
		'replacement': FAIL+'void relay() throws Error { try { leaf(-1); } catch (Error error) { throw new RuntimeError(error.message); } }\nint main() { try { relay(); } catch (RuntimeError error) { if (error.message == "recover") return 42; } catch (Error error) { return 1; } return 2; }\n',
		'buffer-error': 'owned int[] make(bool fail) throws Error { var data = new int[3]; data[0] = 42; if (fail) { throw new Error("buffer"); } return move data; }\nint main() { var old = new int[2]; old[0] = 17; bool caught = false; try { old = make(true); } catch (Error error) { caught = true; if (len(old) != 2 || old[0] != 17) return 1; } if (!caught) return 3; try { old = make(false); return old[0]; } catch (Error error) { return 2; } }\n',
		'class-error': FACTORY+'int main() { try { var parcel = make(-1); return 1; } catch (Error error) { if (error.message != "factory") return 2; } try { var parcel = make(42); return parcel.value; } catch (Error error) { return 3; } }\n',
		'reservation-abort': FAIL+'int take(owned int[] data, int value) { return len(data) + value; }\nint main() { var data = new int[2]; try { take(move data, leaf(-1)); } catch (Error error) { if (len(data) != 2) return 1; return take(move data, 40); } return 2; }\n',
		'nested-reservation': FAIL+'int take(owned int[] data, int value) { return len(data) + value; }\nint main() { var left = new int[2]; var right = new int[3]; try { take(move left, take(move right, leaf(-1))); } catch (Error error) { return take(move left, take(move right, 37)); } return 1; }\n',
		'inner-cleanup': FACTORY+'int relay() throws Error { var outer = new int[2]; { var inner = new int[3]; var parcel = make(-1); } return len(outer); }\nint main() { var survivor = new int[4]; survivor[0] = 38; try { relay(); } catch (Error error) { return survivor[0] + len(survivor); } return 1; }\n',
		'empty-error': 'int leaf() throws Error { throw new Error(""); }\nint main() { try { leaf(); } catch (Error error) { if (error.message.byte_length == 0) return 42; } return 1; }\n',
		'success-forward': FACTORY+'owned Parcel forward(int value) throws Error { return make(value); }\nint take(owned Parcel parcel) { return parcel.value; }\nint main() { try { var parcel = forward(42); return take(move parcel); } catch (Error error) { return 1; } }\n',
	}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--component', type=Path); p.add_argument('--mode', choices=('O0', 'O2')); a = p.parse_args()
	leaf = RUNTIME/('candidates-'+a.version); build = BUILD/leaf.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	commands = []; results = []
	def run(argv, name, expected):
		start = time.monotonic(); r = bounded_run(list(map(str, argv)), cwd=build, capture_output=True, timeout=120)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in expected, (name, r.returncode, r.stderr[-3000:]); return r
	for name, source in corpus().items():
		path = leaf/(name+'.astra'); path.write_text(source); inputs = [path, ROOT/'lib/astra/base/errors.astra']; profiles = {}
		for mode in ([a.mode] if a.mode else ['O0', 'O2']):
			exe = build/(name+'-'+mode)
			run([C0, '-'+mode, *inputs, '-o', exe], name+'-'+mode+'-C0-build', {0}); run([exe], name+'-'+mode+'-C0-run', {42})
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-'+mode+'-C0-memory', {42})
			assert b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
			profiles[mode] = dict(C0_ELF_sha256=sha(exe), C0_exit=42, C0_memory='zero live allocations/errors/suppressions')
			if a.component:
				target = build/(name+'-'+mode+'.ll'); target.write_bytes(b'preserve the pre-existing EFFECTS-25 negative destination\n'); before = sha(target)
				r = run([a.component, '--classstorage-llvm-raw', mode, target, *inputs], name+'-'+mode+'-Astra', {1, 2, 3})
				assert sha(target) == before and b'LLVM_INVALID_UPSTREAM' in r.stderr
				profiles[mode].update(Astra_exit=r.returncode, Astra_native_qualified=False, destination_preserved=True, destination_sha256=before)
		results.append(dict(name=name, sources=[dict(path=str(s), sha256=sha(s)) for s in inputs], profiles=profiles)); (leaf/'result.json').write_text(json.dumps(dict(status='C0_ORACLES_ONLY', Astra_new_native_programs=0, programs=results, limitation='These are executable C0 error/success oracles. Astra refusal is not a passing recoverable-effect implementation.'), indent=2)+'\n')
		print(name, 'C0 '+(a.mode or 'O0/O2')+' native/memory', 'Astra refusal retained' if a.component else 'Astra qualification pending', flush=True)


if __name__ == '__main__':
	main()
