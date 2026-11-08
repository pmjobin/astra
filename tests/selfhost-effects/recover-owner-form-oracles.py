#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent unchanged C0 owned result, receiver and derived Error policy."""
import argparse
import json
import os
import time
from state import ROOT, C0, load_module, bounded_run, sha

CASES = {
	'derived-error-field': 'class Detail : Error { private int code; init(int code) : base("detail") { this.code = code; } int read() { return this.code; } }\nint main() { try { throw new Detail(42); } catch (Detail caught) { if (caught.message != "detail") return 3; return caught.read(); } }\n',
	'derived-error-computed-base': 'string label(int code) { if (code == 42) return "computed"; return "other"; }\nclass Detail : Error { private int code; init(int code) : base(label(code)) { this.code = code; } int read() { return this.code; } }\nint main() { try { throw new Detail(42); } catch (Detail caught) { if (caught.message != "computed") return 3; return caught.read(); } }\n',
	'derived-error-snapshot': 'class Detail : Error { private int code; init(string text, int code) : base(text) { this.code = code; } int read() { return this.code; } }\nint main() { try { throw new Detail("snapshot", 42); } catch (Detail caught) { if (caught.message != "snapshot") return 3; return caught.read(); } }\n',
	'owned-result-discard': 'class Value { private int number; init(int number) { this.number = number; } int read() { return this.number; } }\nowned Value make(int number) { var value = new Value(number); return move value; }\nint main() { make(42); return 42; }\n',
	'owned-result-replacement': 'class Value { private int number; init(int number) { this.number = number; } int read() { return this.number; } }\nowned Value make(int number) { var value = new Value(number); return move value; }\nint main() { var value = make(21); value = make(42); return value.read(); }\n',
	'owned-result-transfer': 'class Value { private int number; init(int number) { this.number = number; } int read() { return this.number; } }\nowned Value make(int number) { var value = new Value(number); return move value; }\nint consume(owned Value value) { return value.read(); }\nint main() { return consume(make(42)); }\n',
	'rvalue-call-receiver': 'class Value { private int number; init(int number) { this.number = number; } int read() { return this.number; } }\nowned Value make(int number) { var value = new Value(number); return move value; }\nint main() { return make(42).read(); }\n',
	'rvalue-new-receiver': 'class Value { private int number; init(int number) { this.number = number; } int read() { return this.number; } }\nint main() { return new Value(42).read(); }\n',
	'field-receiver': 'class Value { private int number; init(int number) { this.number = number; } int read() { return this.number; } }\nclass Box { private owned Value item; init(owned Value item) { this.item = move item; } int read() { return this.item.read(); } }\nint main() { var item = new Value(42); var box = new Box(move item); return box.read(); }\n',
	'owned-result-rearm': 'class Value { private int number; init(int number) { this.number = number; } int read() { return this.number; } }\nowned Value make(int number) { var value = new Value(number); return move value; }\nint main() { var value = make(21); var old = move value; value = make(42); return value.read(); }\n',
	'owned-result-explicit-transfer': 'class Value { private int number; init(int number) { this.number = number; } int read() { return this.number; } }\nowned Value make(int number) { var value = new Value(number); return move value; }\nint consume(owned Value value) { return value.read(); }\nint main() { var value = make(42); return consume(move value); }\n',
}


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	p.add_argument('--case', choices=tuple(CASES), action='append')
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('owner_form_oracle_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('owner-form-oracles-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	commands = []
	def run(argv, name, allowed):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stderr.splitlines()[:3])
		return r
	rows = []
	for name, text in CASES.items():
		if a.case and name not in a.case:
			continue
		source = leaf/(name+'.astra')
		source.write_text(text)
		profiles = []
		for mode in ('O0', 'O2'):
			exe = build/(name+'-'+mode)
			compiled = run([C0, '-'+mode, source, ROOT/'lib/astra/base/errors.astra', '-o', exe], name+'-'+mode+'-build', (0, 1))
			if compiled.returncode != 0:
				profiles.append(dict(mode=mode, C0_source_rejected=True, diagnostic=compiled.stderr.decode(errors='replace')))
				continue
			fatal = name.endswith('-fatal')
			expected = (132, -4) if fatal else (42,)
			observed = run([exe], name+'-'+mode+'-execute', expected)
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-'+mode+'-memory', expected)
			if not fatal:
				assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
			assert observed.stdout == memory.stdout
			profiles.append(dict(mode=mode, C0_source_rejected=False, ELF_sha256=sha(exe), exit=observed.returncode, fatal=fatal, stdout=observed.stdout.decode(errors='replace'), returning_clean_memory=not fatal))
		rows.append(dict(name=name, source_sha256=sha(source), profiles=profiles))
		(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_C0_OWNER_FORM_ORACLES', programs=rows, C0_sha256=sha(C0), Astra_native_credit=0, limitation='Original C0 source-policy, evaluation-order and memory observations only. Rejected source remains rejected. Fatal memory receipts are retained and never described as returning clean memory.'), indent=2)+'\n')
		print(name, ['C0 rejected' if row['C0_source_rejected'] else row['exit'] for row in profiles], flush=True)


if __name__ == '__main__':
	main()
