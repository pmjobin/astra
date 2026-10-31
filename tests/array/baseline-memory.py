# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare known GLib startup loss stacks against the exact accepted archive."""
from pathlib import Path
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile

sys.dont_write_bytecode = True
from qualify import BASELINE, ROOT

out = Path(sys.argv[1]).resolve()/'qualification-array'
base = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else Path(tempfile.mkdtemp(prefix='astra-array-baseline-e996d382-'))
archive = subprocess.run(['git', 'archive', BASELINE], cwd=ROOT, capture_output=True, check=True).stdout
with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
	if len(sys.argv) > 2:
		for member in tar.getmembers():
			if member.isfile():
				assert (base/member.name).read_bytes() == tar.extractfile(member).read(), member.name
	else:
		tar.extractall(base, filter='data')
env = dict(os.environ, CCACHE_DIR='/tmp/astra-array-ccache')
commands = [['meson', 'setup', *(['--reconfigure'] if (base/'build/build.ninja').exists() else []), 'build', '-Dwerror=true'], ['meson', 'compile', '-C', 'build', '-j', '8', 'astra-semantic-tests', 'astra-core-tests', 'astra-cfg-tests']]
for i, command in enumerate(commands):
	with (out/f'baseline-build-{i}.log').open('w') as log:
		subprocess.run(command, cwd=base, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)


def records(path):
	text = re.sub(r'==\d+== ?', '', path.read_text())
	entries = re.findall(r'([\d,]+ bytes in \d+ blocks are definitely lost in loss record[^\n]*\n(?:[^\n]+\n)+)', text)
	return [re.sub(r'0x[0-9A-Fa-f]+', '<address>', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', entry)).strip() for entry in entries]


rows = []
for suite in ['semantic', 'core', 'cfg']:
	log = out/f'baseline-{suite}.log'
	command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(log), str(base/f'build/tests/{suite}/astra-{suite}-tests'), '--tap']
	r = subprocess.run(command, cwd=base, env=env, capture_output=True, text=True)
	(out/f'baseline-{suite}.stdout').write_text(r.stdout)
	(out/f'baseline-{suite}.stderr').write_text(r.stderr)
	before = records(log)
	after = records(out/f'valgrind/{suite}.log')
	assert r.returncode == 99 and len(before) == 1 and before == after, (suite, r, before, after)
	assert '16,384 bytes' in before[0] and 'call_init' in before[0]
	rows.append(dict(suite=suite, definite=16384, exact_startup_stack_match=True))
	print(suite, 'exact accepted-baseline GLib allocation stack and bytes match', flush=True)
(out/'baseline-memory-results.json').write_text(json.dumps(dict(baseline=BASELINE, suites=rows), indent='\t')+'\n')
