# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare GLib startup losses against the unmodified accepted DPTR-1 archive."""
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

out = Path(sys.argv[1]).resolve() / 'qualification-vecmem'
base = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else Path(tempfile.mkdtemp(prefix='astra-vecmem-baseline-77acb61-'))
archive = subprocess.run(['git', 'archive', BASELINE], cwd=ROOT, capture_output=True, check=True).stdout
with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
	if len(sys.argv) > 2:
		# A separately prepared strict baseline can be reused only after every
		# archived file has been verified against the accepted commit.
		for member in tar.getmembers():
			if member.isfile():
				assert (base / member.name).read_bytes() == tar.extractfile(member).read(), member.name
	else:
		tar.extractall(base, filter='data')
env = dict(os.environ, CCACHE_DIR='/tmp/astra-vecmem-ccache')
commands = [['meson', 'setup', *(['--reconfigure'] if len(sys.argv) > 2 else []), 'build', '-Dwerror=true'], ['meson', 'compile', '-C', 'build', '-j', '8', 'astra-semantic-tests', 'astra-core-tests', 'astra-cfg-tests']]
for n, command in enumerate(commands):
	with (out / f'baseline-build-{n}.log').open('w') as log:
		subprocess.run(command, cwd=base, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)


def records(path):
	text = re.sub(r'==\d+== ?', '', path.read_text())
	entries = re.findall(r'([\d,]+ bytes in \d+ blocks are definitely lost in loss record[^\n]*\n(?:[^\n]+\n)+)', text)
	return [re.sub(r'0x[0-9A-Fa-f]+', '<address>', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', entry)).strip() for entry in entries]


results = []
for suite in ['semantic', 'core', 'cfg']:
	command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file=' + str(out / f'baseline-{suite}.log'), str(base / f'build/tests/{suite}/astra-{suite}-tests'), '--tap']
	result = subprocess.run(command, cwd=base, env=env, capture_output=True, text=True)
	(out / f'baseline-{suite}.stdout').write_text(result.stdout)
	(out / f'baseline-{suite}.stderr').write_text(result.stderr)
	results.append({'name': suite, 'exit': result.returncode, 'command': command})
	before = records(out / f'baseline-{suite}.log')
	after = records(out / f'valgrind/{suite}.log')
	assert len(before) == 1 and before == after, (suite, before, after)
	assert '16,384 bytes' in before[0] and 'call_init' in before[0]
	for path in [out / f'baseline-{suite}.log', out / f'valgrind/{suite}.log']:
		text = path.read_text()
		assert 'indirectly lost: 0 bytes' in text and 'possibly lost: 0 bytes' in text
	print(suite, 'exact baseline allocation stack and lost bytes match', flush=True)
rows = json.loads((out / 'valgrind/results.json').read_text())
assert len(rows) == json.loads((out / 'valgrind/completion.json').read_text())['measured'], 'memory qualification must finish before baseline comparison'
for row in rows:
	if row['name'] in ['semantic', 'core', 'cfg']:
		assert row['errors'] == 1 and row['definite'] == 16384 and row['exit'] == 99
	else:
		assert (row['exit'] < 0 if row['name'].startswith('run-trap-') else row['exit'] == 0) and row['errors'] == 0 and row['definite'] == row['indirect'] == row['possible'] == 0, row
	if row['name'].startswith('run-trap-effects'):
		assert row['reachable'] == 4096 and '_IO_file_doallocate' in (out / ('valgrind/' + row['name'] + '.log')).read_text(), row
		assert (out / ('valgrind/' + row['name'] + '.stdout')).read_text() == 'A'
	elif row['name'].startswith('run-'):
		assert row['reachable'] == 0, row
result = {'current_processes': len(rows), 'baseline': BASELINE, 'baseline_source': str(base), 'baseline_syntax_repair': False, 'baseline_comparisons': results, 'no_new_astra_losses': True, 'baseline_glib_losses': ['semantic', 'core', 'cfg'], 'native_targets_zero_reachable': sum(row['name'].startswith('run-') and row['reachable'] == 0 for row in rows), 'trap_stdio_buffers': 1}
(out / 'memory-verification.json').write_text(json.dumps(result, indent='\t') + '\n')
print(json.dumps(result), flush=True)
