#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Versioned ALLOC-FAIL-1 public-CLI boundary; never qualifies full CAD route I."""
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
PIN = 'f415381f92daecfa683838206dffa5ea78d78477'
EXPECTED = b'astra-cad: failure 3 (value 37748736)\n'


def limited():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	resource.setrlimit(resource.RLIMIT_AS, (64 * 1024 * 1024, 64 * 1024 * 1024))


def qualify(compiler, provider, output, cad_repository=None, original_program=None, original_input=None):
	output.mkdir(parents=True, exist_ok=False)
	(output / 'tmp').mkdir()
	env = dict(os.environ, CCACHE_DISABLE='1', TMPDIR=str(output / 'tmp'), PYTHONDONTWRITEBYTECODE='1')
	rows = []
	def run(argv, label, status=0, stderr=b'', limit=False, extra_env=None):
		p = subprocess.run(list(map(str, argv)), cwd=HERE / 'probes', env=env | (extra_env or {}), capture_output=True, preexec_fn=limited if limit else None)
		(output / (label + '.stdout')).write_bytes(p.stdout)
		(output / (label + '.stderr')).write_bytes(p.stderr)
		rows.append(dict(label=label, argv=list(map(str, argv)), status=p.returncode, stdout_hex=p.stdout.hex(), stderr_hex=p.stderr.hex(), address_space_limit=64 * 1024 * 1024 if limit else None))
		(output / 'commands.json').write_text(json.dumps(rows, indent='\t') + '\n')
		assert p.returncode == status and p.stderr == stderr, (label, p.returncode, p.stderr)
		return p
	protocol = (HERE / 'probes/allocation-failure-protocol.c').read_text()
	provenance = {'pinned_application': PIN, 'original_comparison': 'NOT_RUN'}
	if cad_repository is not None:
		adapter = subprocess.check_output(['git', '-C', str(cad_repository), 'show', PIN + ':native/adapter.c']).decode()
		declaration = subprocess.check_output(['git', '-C', str(cad_repository), 'show', PIN + ':src/numeric.astra']).decode()
		algorithm = subprocess.check_output(['git', '-C', str(cad_repository), 'show', PIN + ':src/algorithm.astra']).decode()
		body = adapter[adapter.index('void cad_fail('):adapter.index('\n}', adapter.index('void cad_fail(')) + 2]
		assert body in protocol
		assert 'extern(C) void cad_fail(int code, f64 value);' in declaration
		kernel = next(line for line in algorithm.splitlines() if line.startswith('struct Kernel '))
		assert kernel in (HERE / 'probes/allocation-failure-kernel.astra').read_text()
		provenance['exact_pinned_body_sha256'] = hashlib.sha256(body.encode()).hexdigest()
	if original_program is not None:
		assert original_input is not None and cad_repository is not None
		p = run([original_program, original_input, output / 'original-output.png', '2048', '2048'], 'original-application-error', 2, EXPECTED, True, {'LD_LIBRARY_PATH': str(original_program.parent)})
		assert not p.stdout
		provenance['original_comparison'] = 'EXACT_STATUS_STDOUT_STDERR'
	for cc in ['gcc', 'clang']:
		object_path = output / (cc + '-protocol.o')
		run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', 'allocation-failure-protocol.c', '-o', object_path], cc + '-provider')
		for shape in ['kernel', 'scalar']:
			name = shape + '-' + cc
			binary = output / name
			source = 'allocation-failure-' + shape + '.astra'
			run([compiler, source, '--link-object', provider, '--link-object', object_path, '-o', binary], name + '-compile')
			for stage in ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
				run([compiler, '--dump-' + stage, source], name + '-' + stage)
			for mode in ['', 'generic']:
				p = run([binary, *([mode] if mode else [])], name + '-' + (mode or 'concrete'), 2, EXPECTED, True)
				assert not p.stdout
			if shape == 'kernel':
				for mode, status, error in [('small', 0, b''), ('bounds', -signal.SIGILL, b''), ('negative', -signal.SIGILL, b''), ('distinct', 2, b'astra-cad: failure 17 (value 37748727)\n')]:
					p = run([binary, mode], name + '-' + mode, status, error, True)
					assert not p.stdout
	result = dict(version='ASTRA-ALLOC-FAIL-1', protocol='PASS', full_boundary='requires the compiler, ownership, model, installation and regression matrices', APP_CAD_FULL_I='NOT_RUN/INCOMPLETE', inherited_APP_CAD_1='BLOCKED_COMPILER', compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), provider_sha256=hashlib.sha256(provider.read_bytes()).hexdigest(), logical_kernel_count=4194304, historical_f64_slots=37748736, payload_bytes=301989888, expected_stderr_hex=EXPECTED.hex(), provenance=provenance, commands=len(rows))
	(output / 'result.json').write_text(json.dumps(result, indent='\t') + '\n')
	return result


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler', type=Path, required=True)
	parser.add_argument('--args-provider', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--cad-repository', type=Path)
	parser.add_argument('--original-program', type=Path)
	parser.add_argument('--original-input', type=Path)
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	args = parser.parse_args(); args.output = fresh_output(args.output)
	print(json.dumps(qualify(args.compiler.resolve(), args.args_provider.resolve(), args.output.resolve(), args.cad_repository, args.original_program, args.original_input), indent='\t'))


if __name__ == '__main__':
	main()
