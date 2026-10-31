# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Current-language witnesses, explicit rejection probes, native/O2 and memory."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PROBES = {
	'generic-class': (0, None),
	'owned-generic-field': (1, 'owned struct fields are unsupported'),
	'class-elements': (0, 'BUFFER-1 element requires concrete fixed storage, defined zero, trivial destruction and copyable element semantics'),
	'owner-view': (0, 'owned buffer cannot be copied or stored as an escaping slice'),
	'view-and-move': (0, "cannot borrow moved owned value 'owner'"),
	'snapshot-loan': (0, 'cannot invalidate a receiver while a stored text loan remains in its lexical extent'),
	'bytes-as-text': (0, "expected initializer of type 'string', found 'u8[]'"),
}


def main(compiler, emitter, output):
	compiler, emitter, output = [Path(p).resolve() for p in [compiler, emitter, output]]
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='run-', dir=output))
	rows = []

	def run(command, expected=0, stdout=None, diagnostic=None, memory=False):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=60, env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == expected and (stdout is None or p.stdout == stdout.encode())
		if memory:
			valid &= all(token in p.stderr for token in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		elif diagnostic:
			valid &= diagnostic.encode() in p.stderr and b'internal error' not in p.stderr.lower()
		else:
			valid &= not p.stderr
		rows.append(dict(command=command, expected=expected, observed=p.returncode, stdout=p.stdout.decode('utf-8'), stderr=p.stderr.decode('utf-8'), memory=memory, passed=bool(valid)))
		(out / 'checks.json').write_text(json.dumps(rows, indent=2, ensure_ascii=False) + '\n')
		assert valid, rows[-1]
		return p.stdout

	providers = []
	for name in ['args', 'text']:
		obj = out / (name + '.o')
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT / f'lib/astra/platform/{name}-posix.c', '-o', obj])
		providers.append(obj)
	vg = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all']
	drops = 'drop bag\ndrop W200\ndrop E100\n'
	cases = [([], 'empty\ndrop bag\n'), (['café', 'early'], drops)]
	for text in ['café', 'cafe\u0301', '🖤', '']:
		cases.append(([text], f'error: {text}\nwarning: {text}\nfull: capacity 2\n' + drops))
	binaries = {}
	for name in ['current', 'storage']:
		inputs = [HERE / (name + '.astra')]
		if name == 'current':
			inputs.append(ROOT / 'lib/astra/hosted/text.astra')
		binary = out / name
		run([compiler, *inputs, *[arg for obj in providers for arg in ['--link-object', obj]], '-o', binary])
		for stage in ['semantics', 'ssa', 'nabi']:
			(out / f'{name}.{stage}').write_bytes(run([compiler, '--dump-' + stage, *inputs]))
			# Existing test emitter lowers the authentic hosted entry, including argv
			# prepare/dispose. No handwritten replacement ABI or app implementation.
		ir, optimized, obj, o2 = [out / (name + suffix) for suffix in ['.ll', '-O2.ll', '-O2.o', '-O2']]
		run([emitter, '--emit', ir, *inputs])
		if name == 'current':
			assert 'define i32 @main(i32' in ir.read_text() and '@astra_host_args_dispose_v0' in ir.read_text()
		run(['opt', '-passes=verify', '-disable-output', ir])
		run(['opt', '-passes=default<O2>', '-S', ir, '-o', optimized])
		run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj])
		run(['cc', obj, *providers, '-o', o2])
		for program in [binary, o2]:
			for arguments, expected in cases if name == 'current' else [([], '')]:
				run([program, *arguments], stdout=expected)
				run([*vg, program, *arguments], stdout=expected, memory=True)
		binaries[name] = dict(native_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(), optimized_sha256=hashlib.sha256(o2.read_bytes()).hexdigest(), ir_sha256=hashlib.sha256(ir.read_bytes()).hexdigest())
		# Unchanged positive control: independent snapshot survives its source owner.
	snapshot = out / 'existing-snapshot'
	run([compiler, ROOT / 'tests/error-1/fixtures/snapshot.astra', '--link-object', providers[0], '-o', snapshot])
	run([snapshot], expected=42, stdout='')
	run([*vg, snapshot], expected=42, stdout='', memory=True)
	for name, (parse_exit, diagnostic) in PROBES.items():
		source, binary = HERE / 'probes' / (name + '.astra'), out / (name + '-invalid')
		run([compiler, '--parse', source], expected=parse_exit, stdout='', diagnostic=diagnostic if parse_exit else None)
		if diagnostic is None:
			run([compiler, '--check', source], stdout='')
			continue
		first = None
		for mode in ['--check', 'native']:
			assert not binary.exists()
			command = [compiler, *([] if mode == 'native' else [mode]), source, *(['-o', binary] if mode == 'native' else [])]
			run(command, expected=1, stdout='', diagnostic=diagnostic)
			assert first is None or first == rows[-1]['stderr']
			first = rows[-1]['stderr']
			assert not binary.exists()
	sources = [p for p in HERE.rglob('*') if p.is_file()] + [ROOT / 'lib/astra/hosted/text.astra', ROOT / 'lib/runtime/platform/args-posix.c', ROOT / 'lib/runtime/platform/text-posix.c']
	identity = dict(compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), emitter_sha256=hashlib.sha256(emitter.read_bytes()).hexdigest(), commands=len(rows), positive_memory_runs=sum(r['memory'] for r in rows), source_probes=len(PROBES), output=str(out), binaries=binaries, source_sha256={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})
	(out / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
	(output / 'current.json').write_text(json.dumps(identity, indent=2) + '\n')
	print(f'{len(cases)} application scenarios native/O2; storage and unchanged snapshot control; {identity["positive_memory_runs"]} unsuppressed memory runs; {len(PROBES)} explicit source probes; {len(rows)} commands')
	print(f'Evidence: {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
