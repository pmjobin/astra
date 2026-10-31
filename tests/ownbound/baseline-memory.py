# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the accepted baseline and compare every reported memory loss exactly."""
from pathlib import Path
import io
import json
import os
import subprocess
import tarfile
import tempfile
import sys
import re
root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve() / 'qualification'
base = Path(tempfile.mkdtemp(prefix='astra-ownbound-baseline-fd181d8-'))
archive = subprocess.run(['git', 'archive', 'fd181d8835a88476e622b2605f474cf5b7602d6a'], cwd=root, capture_output=True, check=True).stdout
with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
	tar.extractall(base, filter='data')
env = dict(os.environ, CC='/usr/bin/cc', CCACHE_DISABLE='1')
commands = [['meson', 'setup', 'build', '-Dwerror=true'], ['meson', 'compile', '-C', 'build', '-j', '8', 'astra-semantic-tests', 'astra-core-tests', 'astra-cfg-tests']]
for n, command in enumerate(commands):
	with (out / f'baseline-build-{n}.log').open('w') as log:
		subprocess.run(command, cwd=base, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
results = []
for suite in ['semantic', 'core', 'cfg']:
	command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file=' + str(out / f'baseline-{suite}.log'), str(base / f'build/tests/{suite}/astra-{suite}-tests'), '--tap']
	result = subprocess.run(command, cwd=base, env=env, capture_output=True, text=True)
	(out / f'baseline-{suite}.stdout').write_text(result.stdout)
	(out / f'baseline-{suite}.stderr').write_text(result.stderr)
	results.append({'name': suite, 'exit': result.returncode, 'command': command})
(out / 'baseline-results.json').write_text(json.dumps({'source': str(base), 'baseline': 'fd181d8835a88476e622b2605f474cf5b7602d6a', 'results': results}, indent='\t') + '\n')
print(base)
print(json.dumps(results))

def records(path):
	text = re.sub(r'==\d+== ?', '', path.read_text())
	entries = re.findall(r'([\d,]+ bytes in \d+ blocks are definitely lost in loss record[^\n]*\n(?:[^\n]+\n)+)', text)
	return [re.sub(r'0x[0-9A-Fa-f]+', '<address>', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', entry)).strip() for entry in entries]

for name in ['semantic', 'core', 'cfg']:
	before = records(out / f'baseline-{name}.log')
	after = records(out / f'valgrind/{name}.log')
	assert len(before) == 1 and before == after, name
	assert '16,384 bytes' in before[0] and 'call_init' in before[0]
	for path in [out / f'baseline-{name}.log', out / f'valgrind/{name}.log']:
		text = path.read_text()
		assert 'indirectly lost: 0 bytes' in text and 'possibly lost: 0 bytes' in text
	print(name, 'exact baseline allocation stack and lost bytes match')
rows = json.loads((out / 'valgrind/results.json').read_text())
assert len(rows) == 82
for row in rows:
	if row['name'] in ['semantic', 'core', 'cfg']:
		assert row['errors'] == 1 and row['definite'] == 16384 and row['exit'] == 99
	else:
		assert row['exit'] == row['expected'] and row['errors'] == 0 and row['definite'] == row['indirect'] == row['possible'] == 0, row
	if row['name'].startswith('run-'):
		assert row['reachable'] == 0, row
(out / 'memory-verification.json').write_text(json.dumps({'current_processes': len(rows), 'baseline_comparisons': 3, 'no_new_astra_losses': True, 'baseline_glib_losses': ['semantic', 'core', 'cfg'], 'native_targets_zero_reachable': 19}, indent='\t') + '\n')
