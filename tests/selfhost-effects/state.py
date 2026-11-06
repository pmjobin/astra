#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact EFFECTS-25 intake and immutable predecessor/protection receipts."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT.parent/'codex/work/astra/runtime/effects25'
BUILD = ROOT.parent/'codex/work/astra/build/effects25'
PRIOR = RUNTIME.parent/'genref24'
INPUT = RUNTIME.parent/'native-current/input'
BASE = 'a19425f2cd0932fb0c93629abcd1ed63b98aa5bf'
TREE = '9ef8178508f411c474c247a8bb0718075f5d6f08'
REPORT = '45575de25c8f62ad8d9c30480be353eedde28bca75c96713fa8c777166e51a37'


def load_module(name, path):
	spec = importlib.util.spec_from_file_location(name, path)
	module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
	return module


prior = load_module('effects_prior_state', ROOT/'tests/selfhost-genref/state.py')
sha, read, git, archive, digest, population = prior.sha, prior.read, prior.git, prior.archive, prior.digest, prior.population
C0, COHORTS = prior.C0, prior.COHORTS


def bounded_run(argv, *, timeout=None, capture_output=False, **kwargs):
	# Killing only /usr/bin/time leaves its compiler child running. Own one
	# process group so the unchanged deadline applies to the complete command.
	if capture_output:
		assert 'stdout' not in kwargs and 'stderr' not in kwargs
		kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
	process = subprocess.Popen(argv, start_new_session=True, **kwargs)
	try:
		out, err = process.communicate(timeout=timeout)
	except subprocess.TimeoutExpired:
		os.killpg(process.pid, signal.SIGKILL)
		out, err = process.communicate()
		raise subprocess.TimeoutExpired(argv, timeout, output=out, stderr=err)
	return subprocess.CompletedProcess(argv, process.returncode, out, err)


def preservation():
	module = load_module('effects_protection', ROOT/'tests/selfhost-genresource/state.py')
	result = module.preservation()
	old = read(PRIOR/'initial.json')
	for path, expected in old['workflow'].items(): assert sha(path) == expected
	for path, row in old['hooks'].items(): assert sha(path) == row['sha256'] and oct(Path(path).stat().st_mode & 0o777) == row['mode']
	proofs = read(RUNTIME.parent/'indexpath18/historical-proof-outputs.json')
	assert len(proofs['outputs']) == proofs['count'] == 1044
	assert all(sha(path) == row['sha256'] for path, row in proofs['outputs'].items())
	scope = read(ROOT/'format/scope.json')
	for path, row in scope.items():
		if 'exclude' in row: assert sha(ROOT/path) == row['sha256'], path
	assert sha(C0) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	return dict(protected=result['protected'], donor=result['donor'], donor_head=result['donor_head'], donor_status=result['donor_status'], workflow=old['workflow'], hooks=old['hooks'], historical_proofs=1044, exclusions=sum('exclude' in row for row in scope.values()))


def main():
	assert git('rev-parse', 'HEAD').strip() == BASE and git('rev-parse', 'HEAD^{tree}').strip() == TREE
	assert not git('diff', '--name-only') and not git('diff', '--cached', '--name-only')
	RUNTIME.mkdir(exist_ok=True); BUILD.mkdir(exist_ok=True)
	assert not (RUNTIME/'initial.json').exists()
	result = preservation()
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert report.stat().st_size == 13447308 and sha(report) == REPORT
	if (RUNTIME/'predecessor-report.zip').exists(): assert sha(RUNTIME/'predecessor-report.zip') == REPORT
	else: shutil.copy2(report, RUNTIME/'predecessor-report.zip')
	archives = [archive(report), archive(PRIOR/'predecessor-report.zip'), archive(RUNTIME.parent/'callplace23/predecessor-report.zip')]
	for path, status in [(report, 'PASS'), (PRIOR/'predecessor-report.zip', 'PASS'), (RUNTIME.parent/'callplace23/predecessor-report.zip', 'PARTIAL')]:
		with zipfile.ZipFile(path) as z: assert read_result(z)['status'] == status
	with zipfile.ZipFile(report) as z:
		previous = read_result(z); assert (previous['final_commit'], previous['final_tree']) == (BASE, TREE)
		for row in read(INPUT/'REFERENCE-INDEX.json')['files']:
			if row['kind'] == 'byte-exact report ZIP member': assert (INPUT/row['path']).read_bytes() == z.read(row['origin'])
	for name in ('check', 'build', 'model'):
		assert sha(ROOT/f'compiler/semantic/flow-{name}.astra') == sha(INPUT/f'reference/original/repository-flow-{name}.astra')
	result.update(base=BASE, tree=TREE, archives=archives, config=git('config', '--show-origin', '--list'), refs=git('show-ref'), worktrees=git('worktree', 'list', '--porcelain'), stash=git('stash', 'list'), status=git('status', '--porcelain=v2', '--untracked-files=all'), ignored=git('ls-files', '--others', '--ignored', '--exclude-standard'), routing=dict(PM_NEXT_EXCHANGE_ROOT=os.environ.get('PM_NEXT_EXCHANGE_ROOT'), project=read(ROOT/'codex-project.json')))
	(RUNTIME/'initial.json').write_text(json.dumps(result, indent=2)+'\n')
	print('Pinned predecessor, workflow, 451 protected paths, 6622 donor files, 1044 historical proofs and format exclusions verified', flush=True)
	replay()


def read_result(z):
	return json.loads(z.read('RESULT.json'))


def replay():
	results = {}
	for mode in ('O0', 'O2'):
		cohorts = read(PRIOR/('cohorts-v3-'+mode+'.json'))
		for name in COHORTS:
			old = cohorts[name]; argv = old['independent_consumer']['argv'][2:]
			identity = read(Path(argv[0]).with_suffix('.identity.json'))
			assert sha(argv[0]) == identity['sha256']
			assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
			ledger = read(PRIOR/('ledger-v3-'+mode+'-'+name)/'ledger.json')
			logical, nodes = population(ledger)
			assert digest(logical) == old['population_sha256'] and digest(nodes) == old['node_identity_sha256']
			for row in ledger['files']:
				data = bytes.fromhex(row['synthetic_source_hex']) if 'synthetic_source_hex' in row else Path(row['path']).read_bytes()
				assert len(data) == row['bytes'] and prior.hashlib.sha256(data).hexdigest() == row['sha256']
			leaf = RUNTIME/('baseline-'+mode+'-'+name); leaf.mkdir(exist_ok=False)
			start = time.monotonic()
			with (leaf/'stdout').open('xb') as out, (leaf/'stderr').open('xb') as err:
				r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/'time', *argv], cwd=ROOT, stdout=out, stderr=err, timeout=240)
			codes = [line for line in (leaf/'stderr').read_text().splitlines() if line.startswith('CHECKED_CONSUMER')]
			assert r.returncode == 2 and codes == ['CHECKED_CONSUMER 1 25']
			results[mode+'/'+name] = dict(argv=argv, exit=r.returncode, codes=codes, seconds=time.monotonic()-start, files=len(ledger['files']), nodes=len(nodes), population_sha256=digest(logical), node_identity_sha256=digest(nodes), component_sha256=sha(argv[0]), stdout_sha256=sha(leaf/'stdout'), stderr_sha256=sha(leaf/'stderr'))
			(RUNTIME/'baseline.json').write_text(json.dumps(results, indent=2)+'\n')
			print(mode, name, len(nodes), codes, flush=True)


if __name__ == '__main__':
	main()
