# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Dependency, source identity, source-data size and old-API boundaries."""
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
from qualify import HERE, LIB, STAGES, MODES, COMMANDS, cc, machine, process, report, run, sha, write_json


def sources(build, out):
	out.mkdir(); (out / 'left').mkdir(); (out / 'right').mkdir()
	(out / 'left/same.astra').write_text('void left(){\nassert_that(false);\n}')
	(out / 'right/same.astra').write_text('void right(){\n\nassert_that(false);\n}')
	(out / 'main.astra').write_text('int main(string[] args){if(args[1]=="left"){left();}else{right();}return 0;}')
	args = [build / 'astrac', 'main.astra', './left//same.astra', 'right/same.astra', LIB / 'base/diagnostics.astra', '--link-object', build / 'lib/astra/args-posix.o', '--link-object', build / 'lib/astra/diagnostics-hosted.o', '-o', out / 'consumer']
	run(args, cwd=out); rows = []
	for name, line in [('left', 2), ('right', 3)]:
		p = process([out / 'consumer', name]); expected = report((name + '/same.astra').encode(), line, b'false')
		assert p.returncode < 0 and p.stderr == expected and not p.stdout
		(out / (name + '.stderr')).write_bytes(p.stderr); rows.append(dict(source=name, line=line, sha256=sha(p.stderr)))
		# The same definition specializes once despite distinct files and expressions.
	(out / 'generic.astra').write_text('T id<T>(T x,[CallerFilePath] string file,[CallerLineNumber] int line,[CallerArgumentExpression("x")] string expression){return x;}')
	(out / 'left/same.astra').write_text('int left(){return id(1);}')
	(out / 'right/same.astra').write_text('int right(){\nreturn id<int>(2);}')
	data = run([build / 'astrac', '--dump-instances', 'generic.astra', 'left/same.astra', 'right/same.astra'], cwd=out)
	assert data.count(b'(generic-instance #') == 1 and b'(type-arguments int) (requests 2)' in data
	(out / 'dedup.instances').write_bytes(data)
	return rows


def components(build, out):
	out.mkdir(); rows = []
	cases = [
		('old', 'int main(){return 0;}', [], []),
		('unrelated-name', 'int assert_that(int value){return value;} int main(){return assert_that(0);}', [], []),
		('native-helper', 'int check_value(int value,[CallerFilePath] string file,[CallerLineNumber] int line,[CallerArgumentExpression("value")] string expression){if(file.byte_length>0 && line>0 && expression=="0"){return value;}return 1;} int main(){return check_value(0);}', [], []),
		('old-assert', 'int main(){assert(true);return 0;}', [LIB / 'base/contracts.astra'], ['failure-trap.o']),
		('diagnostic-trap-success', 'int main(){assert_that(true);return 0;}', [LIB / 'base/diagnostics.astra'], ['diagnostics-trap.o']),
		('diagnostic-trap-failure', 'int main(){assert_that(false);return 0;}', [LIB / 'base/diagnostics.astra'], ['diagnostics-trap.o']),
		('diagnostic-hosted', 'int main(){assert_that(true);return 0;}', [LIB / 'base/diagnostics.astra'], ['diagnostics-hosted.o']),
	]
	for name, source, library, providers in cases:
		path = out / (name + '.astra'); path.write_text(source)
		ir_file = out / (name + '.entry.ll'); run([build / 'tests/diag/astra-diag-llvm', '--emit', ir_file, path.name, *library], cwd=out)
		ir = ir_file.read_bytes()
		if name in ['old', 'unrelated-name', 'old-assert']:
			assert b'astra_diag_' not in ir and b'@astra.text.' not in ir
		if name == 'native-helper':
			assert b'astra_diag_' not in ir and b'astra_base_' not in ir
		for mode in MODES:
			stem = out / (name + '-' + mode); obj = machine(ir, stem, mode)
			exe = out / (name + '-' + mode + '.exe')
			if name != 'diagnostic-hosted':
				run(['/usr/bin/gcc', '-nostdlib', '-no-pie', HERE / 'fixtures/start.S', obj, *[build / 'lib/astra' / p for p in providers], '-o', exe])
				assert not run(['nm', '-u', exe]); dynamic = run(['readelf', '-d', exe]); assert b'NEEDED' not in dynamic
			else:
				run(['/usr/bin/gcc', obj, *[build / 'lib/astra' / p for p in providers], '-o', exe])
			p = process([exe]); assert (p.returncode < 0 if name == 'diagnostic-trap-failure' else p.returncode == 0) and not p.stdout and not p.stderr
			rows.append(dict(name=name, mode=mode, status=p.returncode, object_sha256=sha(obj.read_bytes()), size=run(['size', '-A', obj]).decode(), undefined=run(['nm', '-u', exe]).decode(), executable=str(exe)))
			# Pooling is by full payload, including count and bytes after NUL.
	pool = out / 'pool.astra'; pool.write_text('extern(C) void scalar(int n); void take(string x,[CallerArgumentExpression("x")] string e){scalar(x.byte_length+e.byte_length);} int main(){take("a\\0b");take("a\\0b");take("a\\0c");return 0;}')
	ir = run([build / 'astrac', '--dump-llvm', pool.name], cwd=out); (out / 'pool.llvm').write_bytes(ir)
	constants = re.findall(rb'^@[^\n]+ = private (?:unnamed_addr )?constant [^\n]+', ir, re.M)
	assert len(constants) == 4, constants
	write_json(out / 'results.json', rows)
	return rows


def qualify(build, out):
	build = build.resolve(); out = out.resolve(); out.mkdir(parents=True, exist_ok=False)
	try:
		write_json(out / 'results.json', dict(sources=sources(build, out / 'sources'), components=components(build, out / 'components')))
	finally:
		write_json(out / 'commands.json', COMMANDS)
	print('DIAG-1 source labels, specialization, pooling and component boundaries PASS')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]), Path(sys.argv[2]))
