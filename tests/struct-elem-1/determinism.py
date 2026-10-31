# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare independently built, fully executed campaigns without text rewriting."""
from pathlib import Path
import hashlib
import json
import sys

STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']


def qualify(candidate, independent, out):
	out.mkdir(parents=True, exist_ok=False); compared = []
	def exact(relative):
		left = (candidate/relative).read_bytes(); right = (independent/relative).read_bytes()
		assert left == right, relative
		compared.append(dict(path=str(relative), bytes=len(left), sha256=hashlib.sha256(left).hexdigest()))
	root = Path('tests/struct-elem-1')
	first = json.loads((candidate/root/'execution/results.json').read_text()); second = json.loads((independent/root/'execution/results.json').read_text())
	assert first == second
	for case in first['stages']:
		name, stage = case.split(':'); exact(root/'execution'/(name+'.'+stage))
	for stem in first['machines']:
		for suffix in ['-input.ll', '.ll', '.o']:
			exact(root/'execution'/(stem+suffix))
	for name in ['borrowed', 'call-entry']:
		for mode in ['O0', 'O2', 'preserved']:
			for suffix in ['-input.ll', '.ll', '.o', '']:
				exact(root/'machine'/(name+'-'+mode+suffix))
	for mode in ['O0', 'O2', 'fma', 'preserved']:
		for suffix in ['-input.ll', '.ll', '.o']:
			exact(root/'client/machine'/(mode+suffix))
	for location in ['original', 'relocated/qualification']:
		for stage in STAGES:
			exact(root/'client'/location/('canonical.'+stage))
		for i in range(24):
			for suffix in ['.stdout', '.stderr']:
				exact(root/'client'/location/(f'consumer-{i}'+suffix))
			exact(root/'client'/location/'client'/('consumer-'+str(i)))
		exact(root/'client'/location/'method-failure.stderr')
	for name in ['args-posix.o', 'text-posix.o', 'diagnostics-hosted.o', 'diagnostics-trap.o', 'failure-trap.o', 'failure-hosted.o']:
		exact(Path('lib/astra')/name)
	exact(Path('const-1/oracle/oracle.json'))
	utf8 = []
	for build in [candidate, independent]:
		utf8.append(json.loads((build/'args-1/qualification/qualification.json').read_text())['utf8'])
	assert utf8[0] == utf8[1]
	suites = [[json.loads(line) for line in (build/'meson-logs/testlog.json').read_text().splitlines()] for build in [candidate, independent]]
	assert sorted((row['name'], row['result']) for row in suites[0]) == sorted((row['name'], row['result']) for row in suites[1])
	assert all(row['result'] == 'OK' for suite in suites for row in suite)
	(out/'results.json').write_text(json.dumps(dict(exact_artifacts=compared, utf8=utf8[0], passing_tests=[len(suite) for suite in suites], runtime_runs=len(first['runs']), compiler_sha256=[hashlib.sha256((build/'astrac').read_bytes()).hexdigest() for build in [candidate, independent]], normalization='none; actual canonical payloads and ELF object/executable bytes'), indent='\t')+'\n')
	print(f'{len(compared)} exact independent artifacts, {len(first["runs"])} identical execution records; both complete suites pass')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve())
