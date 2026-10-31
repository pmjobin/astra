# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently observable A49-A56 applications; qualify only implemented entries."""
from pathlib import Path
import hashlib
import json
import struct
import os
import re
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
APPS = ROOT/'examples/language-usability-7'


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='apps-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	rows = []
	libs = [ROOT/path for path in ['lib/astra/collections/bag.astra', 'lib/astra/hosted/text.astra',
		'lib/astra/base/errors.astra', 'lib/astra/hosted/files.astra', 'lib/astra/text/utf8-message.astra',
		'lib/astra/text/utf8-byte-builder.astra', 'lib/astra/text/scalar-format.astra',
		'lib/astra/hosted/text-ops.astra', 'lib/astra/text/float-format.astra']]
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler), checks=rows,
		products={}, application_ids=['A49', 'A50', 'A51', 'A52', 'A53', 'A54', 'A55', 'A56'], source_sha256={str(path.relative_to(ROOT)): sha(path)
		for path in [*libs, APPS/'counted-record-scanner.astra', APPS/'diagnostic-bag-report.astra', APPS/'scoped-config-renderer.astra', APPS/'nullable-boundary-processor.astra', APPS/'ordered-policy-engine.astra', APPS/'float-telemetry-report.astra', APPS/'source-inspector.astra', APPS/'diagnostic-transform-pipeline.astra', HERE/'apps-check.py', HERE/'app-locale-probe.c',
		ROOT/'lib/runtime/platform/args-posix.c', ROOT/'lib/runtime/platform/text-posix.c', ROOT/'lib/runtime/platform/files-posix.c', ROOT/'lib/runtime/platform/float-text-posix.c', ROOT/'lib/runtime/platform/float-text-posix.h', ROOT/'lib/runtime/platform/text-ops-posix.c']})
	def run(command, expected=0, stdout=b'', memory=False, environment=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=out, capture_output=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1', **(environment or {})))
		valid = p.returncode == expected and p.stdout == stdout
		if memory:
			valid &= all(part in p.stderr for part in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
			if '--track-fds=yes' in command: valid &= re.search(rb'FILE DESCRIPTORS: 3 open \(3 (?:std|inherited)\) at exit', p.stderr) is not None
		else:
			valid &= not p.stderr
		rows.append(dict(command=command, cwd=str(out), expected_exit=expected, actual_exit=p.returncode,
			environment=environment or {}, stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace'), passed=bool(valid)))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert valid, rows[-1]
		return p.stdout
	links = []
	for name in ['text', 'args', 'files', 'text-ops', 'float-text']:
		obj = out/(name+'.o')
		run(['cc', '-std=c11', '-fno-fast-math', '-ffp-contract=off', '-Wall', '-Wextra', '-Werror', '-c', ROOT/f'lib/astra/platform/{name}-posix.c', '-o', obj])
		links += ['--link-object', obj]
	locale_probe = out/'locale-probe.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'app-locale-probe.c', '-o', locale_probe])
	links += ['--link-object', locale_probe, '--link-library', 'm']
	config = out/'config.txt'; config.write_text('sample é', encoding='utf-8')
	empty = out/'empty.txt'; empty.write_bytes(b'')
	invalid = out/'invalid.txt'; invalid.write_bytes(b'\xff')
	records = out/'records.bin'; records.write_bytes(bytes([3,1,2,3,0,2,255,128,255,99]))
	truncated = out/'truncated.bin'; truncated.write_bytes(bytes([3,1]))
	created = b'created\n'*3
	retired = b'retired error: terminal\nretired warning: sample\nretired info: ready\n'
	header = b'diagnostic report\n'
	def verify_file(path, expected):
		actual = path.read_bytes() if path.exists() else None
		rows.append(dict(file=str(path), expected_hex=None if expected is None else expected.hex(), actual_hex=None if actual is None else actual.hex(), passed=actual == expected))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert actual == expected, rows[-1]
	def telemetry_expected(last):
		rows = ['f32\tf64\n']
		for value in ['-0', '1.401298464324817e-45', '3.4028234663852886e38', 'nan', 'inf', '-inf']:
			parsed = float(value); first = struct.unpack('<f', struct.pack('<f', parsed))[0]
			rows.append(format(first, '.9g')+'\t'+format(parsed, '.17g')+'\n')
		for value in ['4.9406564584124654e-324', '1.7976931348623157e308']:
			rows.append('-\t'+format(float(value), '.17g')+'\n')
		parsed = float(last); first = struct.unpack('<f', struct.pack('<f', parsed))[0]
		rows.append(format(first, '.9g')+'\t'+format(parsed, '.17g')+'\n')
		return ''.join(rows).encode()
	good_source = out/'good.astra'; good_source.write_text('int main() {\n\tstring label = "é";\n\treturn 0;\n}\n')
	bad_source = out/'hygiene.astra'; bad_source.write_bytes(b'  int x; \n\treturn "a\x00";\n')
	crlf_source = out/'crlf.astra'; crlf_source.write_bytes(b'int main() {\r\n\treturn 0;\r\n}\r\n')
	measurements = out/'measurements.txt'; measurements.write_bytes(b'10\n-1\nnan\ninf\n-0\n\n99.5\n100\n')
	bad_measurements = out/'bad-measurements.txt'; bad_measurements.write_bytes(b'12\nbad\n')
	pipeline_expected = b'measurements\n0\t10\n1\t-1\n2\tnan\n1\tinf\n0\t-0\n0\t99.5\n1\t100\naccepted 3\noutside 3\nunordered 1\n'
	pipeline_empty = b'measurements\naccepted 0\noutside 0\nunordered 0\n'
	formatted = {}
	for app, name in [('A49', 'counted-record-scanner'), ('A50', 'diagnostic-bag-report'), ('A51', 'nullable-boundary-processor'), ('A52', 'ordered-policy-engine'), ('A53', 'scoped-config-renderer'), ('A54', 'float-telemetry-report'), ('A55', 'source-inspector'), ('A56', 'diagnostic-transform-pipeline')]:
		source = APPS/(name+'.astra'); target = out/(app+'-formatted.astra')
		run([compiler, '--format', source, '-o', target])
		run([compiler, '--format', '--check', source])
		run([compiler, '--format', '--check', target])
		formatted[app] = target
	receipt['formatted_sources'] = {app: sha(path) for app, path in formatted.items()}
	for opt in ['-O0', '-O1', '-O2']:
		scanner = out/('A49'+opt)
		run([compiler, opt, APPS/'counted-record-scanner.astra', *libs, *links, '-o', scanner])
		receipt['products'][scanner.name] = sha(scanner)
		for path, status, trace in [(records, 0, b'records 2\nvalues 5\nsum 389\nbytes 9\nempty 1\n'),
			(empty, 0, b'records 0\nvalues 0\nsum 0\nbytes 0\nempty 0\n'),
			(truncated, 65, b'scan failed\n'), (out/'missing.bin', 65, b'scan failed\n')]:
			run([scanner, path], expected=status, stdout=trace)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
				'--errors-for-leak-kinds=all', '--track-fds=yes', '--error-exitcode=99', scanner, path], expected=status, stdout=trace, memory=True)
		exe = out/('A50'+opt)
		run([compiler, opt, APPS/'diagnostic-bag-report.astra', *libs, *links, '-o', exe])
		receipt['products'][exe.name] = sha(exe)
		for argument, trace in [('all', created+header+b'warning: sample\nerror: terminal\n'+retired),
			('first', created+header+b'warning: sample\n'+retired), ('empty', header)]:
			run([exe, argument], stdout=trace)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
				'--errors-for-leak-kinds=all', '--error-exitcode=99', exe, argument], stdout=trace, memory=True)
		run([exe, 'outside'], expected=-signal.SIGILL, stdout=created+header+b'warning: sample\nerror: terminal\n')
		boundary = out/('A51'+opt)
		run([compiler, opt, APPS/'nullable-boundary-processor.astra', *libs, *links, '-o', boundary])
		receipt['products'][boundary.name] = sha(boundary)
		boundary_trace = 'accepted sample é\naccepted sample é\nclosed boundary\nclosed sample é\n'.encode()
		for argument, status, trace in [('sample é', 0, boundary_trace), ('none', 0, b'skipped null\n'), ('fail', 65, b'boundary failed\n')]:
			run([boundary, argument], expected=status, stdout=trace)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', boundary, argument], expected=status, stdout=trace, memory=True)
		configured = out/('A53'+opt)
		run([compiler, opt, APPS/'scoped-config-renderer.astra', *libs, *links, '-o', configured])
		receipt['products'][configured.name] = sha(configured)
		prefix = 'loaded configuration\nname sample é\nport 9080\nnested nested\nouter sample é\nclosed nested\n'.encode()
		for mode, status, suffix in [('all', 0, 'rendered\nclosed sample é\n'),
			('early', 0, 'closed sample é\n'), ('fail', 65, 'closed sample é\nrender failed\n')]:
			trace = prefix+suffix.encode()
			run([configured, config, mode], expected=status, stdout=trace)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
				'--errors-for-leak-kinds=all', '--error-exitcode=99', configured, config, mode], expected=status, stdout=trace, memory=True)
		for path in [empty, invalid, out/'missing.txt']:
			run([configured, path, 'all'], expected=65, stdout=b'render failed\n')
		policy = out/('A52'+opt)
		run([compiler, opt, APPS/'ordered-policy-engine.astra', *libs, *links, '-o', policy]); receipt['products'][policy.name] = sha(policy)
		for value, mode, status, trace in [('10', 'normal', 0, b'policy allow\nlower 1\nmeasure 1\nupper 1\n'),
			('-1', 'normal', 0, b'policy deny\nlower 1\nmeasure 1\nupper 0\n'),
			('nan', 'normal', 0, b'policy deny\nlower 1\nmeasure 1\nupper 0\n'),
			('-inf', 'normal', 0, b'policy deny\nlower 1\nmeasure 1\nupper 0\n'),
			('inf', 'normal', 0, b'policy deny\nlower 1\nmeasure 1\nupper 1\n'),
			('10', 'fail', 65, b'policy failed\nlower 1\nmeasure 1\nupper 0\n'), ('bad', 'normal', 65, b'policy invalid\n')]:
			run([policy, value, mode], expected=status, stdout=trace)
			if mode == 'fail' or value == 'nan':
				run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', policy, value, mode], expected=status, stdout=trace, memory=True)
		telemetry = out/('A54'+opt)
		run([compiler, opt, APPS/'float-telemetry-report.astra', *libs, *links, '-o', telemetry]); receipt['products'][telemetry.name] = sha(telemetry)
		for locale in ['C', 'fr_CA.utf8']:
			path = out/('telemetry-'+locale+opt+'.txt')
			run([telemetry, path, '0.1'], stdout=b'telemetry written\n', environment={'ASTRA_TEST_NUMERIC_LOCALE': locale}); verify_file(path, telemetry_expected('0.1'))
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--track-fds=yes', '--error-exitcode=99', telemetry, path, '0.1'], stdout=b'telemetry written\n', memory=True, environment={'ASTRA_TEST_NUMERIC_LOCALE': locale}); verify_file(path, telemetry_expected('0.1'))
		for value in ['1,5', '1e400', '1e-999']:
			path = out/('bad-telemetry-'+value+opt+'.txt'); run([telemetry, path, value], expected=65, stdout=b'telemetry failed\n'); verify_file(path, None)
		run([telemetry, out/'absent'/'telemetry.txt', '0.1'], expected=65, stdout=b'telemetry failed\n')
		inspector = out/('A55'+opt)
		run([compiler, opt, APPS/'source-inspector.astra', *libs, *links, '-o', inspector]); receipt['products'][inspector.name] = sha(inspector)
		for paths, status, trace in [([good_source], 0, b'file 1\nlines 4\nfindings 0\n'),
			([bad_source], 1, b'file 1\nspace indentation at 1:1\ntrailing whitespace at 1:9\nNUL byte at 2:11\nlines 2\nfindings 3\n'),
			([empty, crlf_source], 0, b'file 1\nlines 0\nfindings 0\nfile 2\nlines 3\nfindings 0\n'),
			([invalid], 65, b'inspection failed\n'), ([out/'absent.astra'], 65, b'inspection failed\n')]:
			run([inspector, *paths], expected=status, stdout=trace)
			if paths == [bad_source] or status == 65:
				run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--track-fds=yes', '--error-exitcode=99', inspector, *paths], expected=status, stdout=trace, memory=True)
		pipeline = out/('A56'+opt)
		run([compiler, opt, APPS/'diagnostic-transform-pipeline.astra', *libs, *links, '-o', pipeline]); receipt['products'][pipeline.name] = sha(pipeline)
		for source, expected in [(measurements, pipeline_expected), (empty, pipeline_empty)]:
			path = out/('pipeline-'+source.name+opt+'.txt')
			run([pipeline, source, path], stdout=b'pipeline written\n'); verify_file(path, expected)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--track-fds=yes', '--error-exitcode=99', pipeline, source, path], stdout=b'pipeline written\n', memory=True); verify_file(path, expected)
		for source in [bad_measurements, invalid, out/'missing-measurements.txt']:
			path = out/('rejected-'+source.name+opt+'.txt')
			run([pipeline, source, path], expected=65, stdout=b'pipeline failed\n'); verify_file(path, None)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--track-fds=yes', '--error-exitcode=99', pipeline, source, path], expected=65, stdout=b'pipeline failed\n', memory=True); verify_file(path, None)
		run([pipeline, measurements, out/'absent'/'pipeline.txt'], expected=65, stdout=b'pipeline failed\n')
		for app, arguments, trace in [
			('A49', [records], b'records 2\nvalues 5\nsum 389\nbytes 9\nempty 1\n'),
			('A50', ['all'], created+header+b'warning: sample\nerror: terminal\n'+retired),
			('A51', ['sample é'], boundary_trace),
			('A52', ['10', 'normal'], b'policy allow\nlower 1\nmeasure 1\nupper 1\n'),
			('A54', [out/('formatted-telemetry'+opt+'.txt'), '0.1'], b'telemetry written\n'),
			('A55', [good_source], b'file 1\nlines 4\nfindings 0\n'),
			('A56', [measurements, out/('formatted-pipeline'+opt+'.txt')], b'pipeline written\n'),
			('A53', [config, 'all'], prefix+'rendered\nclosed sample é\n'.encode())]:
			peer = out/(app+'-formatted'+opt)
			run([compiler, opt, formatted[app], *libs, *links, '-o', peer])
			receipt['products'][peer.name] = sha(peer)
			run([peer, *arguments], stdout=trace)
			if app == 'A54': verify_file(arguments[0], telemetry_expected('0.1'))
			if app == 'A56': verify_file(arguments[1], pipeline_expected)
	print(f'{sum("command" in row for row in rows)} application commands; {sum("file" in row for row in rows)} file checks; {len(receipt["application_ids"])} application(s); receipts: {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
