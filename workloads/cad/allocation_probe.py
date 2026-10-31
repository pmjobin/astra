#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce CAD's required native-allocation failure boundary, without images."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def limited():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	resource.setrlimit(resource.RLIMIT_AS, (64 * 1024 * 1024, 64 * 1024 * 1024))


def probe(compiler, provider, output):
	output.mkdir(parents=True, exist_ok=False)
	(output / 'tmp').mkdir()
	env = dict(os.environ, CCACHE_DISABLE='1', TMPDIR=str(output / 'tmp'), PYTHONDONTWRITEBYTECODE='1')
	commands = []
	rows = []
	for name in ['owned-kernel-allocation', 'owned-kernel-bounds', 'owned-scalar-allocation']:
		source = HERE / 'probes' / (name + '.astra')
		links = [] if name == 'owned-scalar-allocation' else ['--link-object', str(provider)]
		command = [str(compiler), str(source), *links, '-o', str(output / name)]
		p = subprocess.run(command, capture_output=True, env=env)
		commands.append({'argv': command, 'status': p.returncode})
		(output / (name + '.compile.stdout')).write_bytes(p.stdout)
		(output / (name + '.compile.stderr')).write_bytes(p.stderr)
		(output / 'commands.json').write_text(json.dumps(commands, indent='\t') + '\n')
		if p.returncode:
			raise RuntimeError(f'probe compile failed; inspect {output / (name + ".compile.stderr")}')
		command = [str(compiler), '--dump-llvm', str(source)]
		p = subprocess.run(command, capture_output=True, env=env)
		commands.append({'argv': command, 'status': p.returncode})
		(output / (name + '.ll')).write_bytes(p.stdout)
		(output / (name + '.llvm.stderr')).write_bytes(p.stderr)
		if p.returncode:
			raise RuntimeError(f'probe LLVM dump failed: {name}')
	for name, arguments in [('small', ['owned-kernel-allocation', 'small']), ('allocation-failure', ['owned-kernel-allocation']), ('bounds-control', ['owned-kernel-bounds']), ('scalar-allocation', ['owned-scalar-allocation'])]:
		command = [str(output / arguments[0]), *arguments[1:]]
		p = subprocess.run(command, capture_output=True, env=env, preexec_fn=limited)
		commands.append({'argv': command, 'status': p.returncode, 'address_space_limit': 64 * 1024 * 1024})
		(output / (name + '.stdout')).write_bytes(p.stdout)
		(output / (name + '.stderr')).write_bytes(p.stderr)
		rows.append({'name': name, 'status': p.returncode, 'signal': signal.Signals(-p.returncode).name if p.returncode < 0 else None, 'stdout': p.stdout.decode(errors='backslashreplace'), 'stderr': p.stderr.decode(errors='backslashreplace'), 'category': 'normal-probe' if name == 'small' else 'fatal-nonunwinding'})
	confirmed = rows[0]['status'] == 0 and all(row['status'] == -signal.SIGILL for row in rows[1:]) and all(not row['stdout'] and not row['stderr'] for row in rows)
	record = {'status': 'BLOCKED_COMPILER' if confirmed else 'UNRESOLVED_PROBE', 'scope': 'Required allocation boundary only; not a full idiomatic CAD application.', 'kind': 'Missing supported native allocation failure interface; not an inferred compiler miscompile.', 'legacy_obligation': {'source': 'f415381:tests/test_cad.py:345', 'exit_status': 2, 'stderr_contains': 'failure 3'}, 'native_allocation_bytes': 2048 * 2048 * 72, 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'provider_sha256': hashlib.sha256(provider.read_bytes()).hexdigest(), 'rows': rows}
	(output / 'commands.json').write_text(json.dumps(commands, indent='\t') + '\n')
	(output / 'result.json').write_text(json.dumps(record, indent='\t') + '\n')
	return record


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler', type=Path, required=True)
	parser.add_argument('--args-provider', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	args = parser.parse_args()
	record = probe(args.compiler.resolve(), args.args_provider.resolve(), args.output.resolve())
	print(json.dumps(record, indent='\t'))
	return 3 if record['status'] == 'BLOCKED_COMPILER' else 1


if __name__ == '__main__':
	sys.exit(main())
