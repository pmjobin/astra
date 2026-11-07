#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Separate C0-illegal constructors from legal, still-unimplemented shapes."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, sha, read, bounded_run


def corpus():
	return {
		'missing-required-base': (False, 'class Bad : Error { init() {} }\nint main() { var value = new Bad(); return 42; }\n'),
		'wrong-base-message-type': (False, 'class Bad : Error { init() : base(17) {} }\nint main() { var value = new Bad(); return 42; }\n'),
		'cyclic-error-ancestry': (False, 'class A : B { init() : base() {} }\nclass B : A { init() : base() {} }\nint main() { return 42; }\n'),
		'literal-constructor-extra-argument': (False, 'class Bad : Error { init() : base("literal") {} }\nint main() { var value = new Bad("other"); return 42; }\n'),
		'typed-parenthesized-construction': (False, 'class Parcel { init() {} }\nint main() { Parcel value = (new Parcel()); return 42; }\n'),
		'direct-null-Class-local': (False, 'class Parcel { init() {} }\nint main() { owned Parcel value = null; return 42; }\n'),
		'construction-return-expression': (False, 'class Parcel { init() {} }\nowned Parcel make() { return new Parcel(); }\nint main() { var value = make(); return 42; }\n'),
		'Class-local-call-rebinding': (False, 'class Parcel { init() {} }\nowned Parcel make() throws Error { var result = new Parcel(); return move result; }\nint main() { var value = new Parcel(); try { value = make(); return 42; } catch (Error caught) { return 4; } }\n'),
		'Class-local-null-call-rebinding': (False, 'class Parcel { init() {} }\nowned Parcel empty() throws Error { return null; }\nint main() { var value = new Parcel(); try { value = empty(); return 42; } catch (Error caught) { return 4; } }\n'),
		'Error-local-call-rebinding': (False, 'owned Error make() throws Error { var result = new Error("kept"); return move result; }\nint main() { var value = new Error("old"); try { value = make(); return 42; } catch (Error caught) { return 4; } }\n'),
		'receiver-consumes-owner': (False, 'class Parcel { init() {} int leaf(owned Parcel other) throws Error { return 42; } }\nint main() { var value = new Parcel(); try { return value.leaf(move value); } catch (Error caught) { return 3; } }\n'),
		'receiver-later-consumes-owner': (False, 'class Parcel { init() {} int leaf(int value) throws Error { return value; } }\nint dispose(owned Parcel value) { return 42; }\nint main() { var value = new Parcel(); try { return value.leaf(dispose(move value)); } catch (Error caught) { return 3; } }\n'),
		'borrowed-Class-argument-before-move': (False, 'class Parcel { init() {} }\nint inspect(borrowed Parcel view, owned Parcel owner) throws Error { return 42; }\nint main() { var value = new Parcel(); try { return inspect(value, move value); } catch (Error caught) { return 3; } }\n'),
		'borrowed-Class-argument-after-move': (False, 'class Parcel { init() {} }\nint inspect(owned Parcel owner, borrowed Parcel view) throws Error { return 42; }\nint main() { var value = new Parcel(); try { return inspect(move value, value); } catch (Error caught) { return 3; } }\n'),
		'checked-receiver-moved-argument-handler-reuse': (False, 'class Parcel { init() {} int leaf(owned int[] data, int extra) throws Error { return len(data) + extra; } }\nint fail() throws Error { throw new Error("kept"); }\nint main() { var value = new Parcel(); var data = new int[42]; try { value.leaf(move data, fail()); return 3; } catch (Error caught) { return len(data); } }\n'),
		'inferred-parenthesized-construction': (True, 'class Parcel { init() {} }\nint main() { var value = (new Parcel()); return 42; }\n'),
		'fielded-derived-Error': (True, 'class Detail : Error { int code; init(int code) : base("literal") { this.code = code; } }\nint main() { try { throw new Detail(42); } catch (Error caught) { return 42; } }\n'),
		'computed-base-message': (True, 'string message() { return "literal"; }\nclass Detail : Error { init() : base(message()) {} }\nint main() { try { throw new Detail(); } catch (Error caught) { return 42; } }\n'),
		'discarded-checked-scalar-result': (True, 'class Parcel { init() {} int leaf() throws Error { throw new Error("kept"); } }\nint main() { var value = new Parcel(); try { value.leaf(); return 3; } catch (Error caught) { if (caught.message == "kept") return 42; return 4; } }\n'),
	}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r3_policy_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r3-policy-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	if a.component:
		identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, name):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=120); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	for name, (legal, text) in corpus().items():
		source = leaf/(name+'.astra'); source.write_text(text); inputs = [source, ROOT/'lib/astra/base/errors.astra']; c0 = build/(name+'-C0'); result = run([C0, '-'+a.mode, *inputs, '-o', c0], name+'-C0-build'); assert result.returncode == (0 if legal else 1), (name, result.returncode, result.stderr[-2500:])
		if legal: assert run([c0], name+'-C0-execute').returncode == 42
		row = dict(name=name, source_sha256=sha(source), C0_legal=legal, C0_exit=result.returncode)
		if a.component:
			target = build/(name+'.ll'); target.write_text('Policy output sentinel\n'); before = sha(target); native = run([a.component, '--native', target, *inputs], name+'-Astra-attempt'); positive = name == 'inferred-parenthesized-construction'; assert (native.returncode == 0) == positive, (name, native.stdout, native.stderr)
			if positive:
				assert run(['opt', '-passes=verify', '-disable-output', target], name+'-verify').returncode == 0; obj = build/(name+'.o'); exe = build/(name+'-Astra'); assert run(['llc', '-filetype=obj', '-'+a.mode, target, '-o', obj], name+'-object').returncode == 0; assert run(['cc', '-no-pie', obj, '-o', exe], name+'-link').returncode == 0; assert run([exe], name+'-execute').returncode == 42
			else: assert sha(target) == before
			row.update(Astra_exit=native.returncode, destination_preserved=not positive, first_output=native.stdout.decode(), classification='C0-valid inferred construction executed' if positive else 'C0-valid source still deferred' if legal else 'C0-invalid source remains rejected')
		rows.append(row); (leaf/'result.json').write_text(json.dumps(dict(status='SEPARATE_C0_SOURCE_POLICY_CONTROLS', profile=a.mode, component_sha256=sha(a.component) if a.component else None, programs=rows, primary_corpus_credit=0), indent=2)+'\n'); print(a.mode, name, 'C0 legal' if legal else 'C0 rejected', flush=True)


if __name__ == '__main__':
	main()
