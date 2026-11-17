#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently inspect current receipts; keep unavailable platform gates open."""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tools/ci'))
from common import external, identify, require, sha, write
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from audit import preservation

BASE = '1c66336d5e6ff6b0a137e83102630be0557066e6'
TREE = 'e2d992d8e7f807284b0de3484057dad3696a6fc2'
PREDECESSOR = 'ef53ff2537c894677deb46fa14c2e7face881fb315b083921d1a5b2a55eadb7e'


def load(path):
	return json.loads(Path(path).read_text())


def git(*args):
	return subprocess.check_output(['git', '-C', ROOT, *args], text=True).strip()


def memory_stream(path):
	data = path.read_bytes()
	pids = set(re.findall(rb'^==([0-9]+)== Memcheck,', data, re.M))
	require(bool(pids), 'no actual Memcheck process: '+str(path))
	passed = True
	for pid in pids:
		lines = b'\n'.join(line for line in data.splitlines() if line.startswith(b'=='+pid+b'=='))
		errors = re.findall(rb'ERROR SUMMARY: ([0-9,]+) errors', lines)
		live = re.findall(rb'in use at exit: ([0-9,]+) bytes in ([0-9,]+) blocks', lines)
		passed = passed and bool(errors) and bool(live) and all(value == b'0' for value in errors) and all(a == b == b'0' for a, b in live) and b'(suppressed: 0 from 0)' in lines
	return dict(path=str(path), sha256=sha(path), processes=len(pids), passed=passed)


def streams(bases):
	"""Authenticate failed and passing observations without turning failures into PASS."""
	commands, memory, costs = [], {}, {}
	def inspect(path):
		data = path.read_bytes()
		if re.search(rb'^==[0-9]+== Memcheck,', data, re.M):
			memory[str(path)] = memory_stream(path)
		if path.name == 'time.txt' or path.suffix == '.time':
			fields = {}
			for line in data.decode().splitlines():
				if ': ' in line:
					key, value = line.strip().split(': ', 1)
					fields[key] = value
			costs[str(path)] = dict(path=str(path), sha256=sha(path), user_seconds=fields.get('User time (seconds)'), system_seconds=fields.get('System time (seconds)'), maximum_RSS_KiB=fields.get('Maximum resident set size (kbytes)'))
	for base in bases:
		for index in sorted(base.rglob('commands.json')):
			for row in load(index):
				label = row.get('label', row.get('name'))
				result = row.get('result', row)
				if 'stdout_sha256' not in result:
					continue
				for kind in ('stdout', 'stderr', 'time'):
					if kind+'_sha256' not in result:
						continue
					candidates = [index.parent/label/('time.txt' if kind == 'time' else kind), index.parent/(label+('.time' if kind == 'time' else '.'+kind)), index.parent/(label+'-controller')/('time.txt' if kind == 'time' else kind)]
					leaf = next((path for path in candidates if path.is_file()), None)
					require(leaf is not None and sha(leaf) == result[kind+'_sha256'], 'recorded stream changed: '+str(index)+' '+label)
					inspect(leaf)
				commands.append(dict(index=str(index), label=label, exit=result['exit'], expected=result.get('expected_exit', result.get('expected')), timed_out=result.get('timed_out', False)))
		for index in sorted(base.rglob('command.json')):
			row = load(index)
			require(row['status'] != 'RUNNING', 'unfinished command: '+str(index))
			for name, item in row.get('streams', {}).items():
				leaf = index.parent/name
				require(sha(leaf) == item['sha256'], 'controller stream changed')
				inspect(leaf)
			commands.append(dict(index=str(index), exit=row.get('exit'), expected=row.get('expected_exit'), status=row['status']))
	return commands, list(memory.values()), list(costs.values())


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('campaign', 'bootstrap', 'regression', 'seed', 'format', 'output'):
		p.add_argument('--'+name, type=Path, required=True)
	for kind in ('deb', 'rpm'):
		for field in ('package', 'build-receipt', 'install'):
			p.add_argument('--'+kind+'-'+field, type=Path, required=True)
	a = p.parse_args()
	entry = load(a.campaign/'intake.json')
	require(entry['HEAD'] == BASE and entry['tree'] == TREE and entry['offline']['status'] == 'OFFLINE_PASS', 'intake mismatch')
	require(sha(a.campaign/'predecessor-publication.json') == entry['predecessor_publication_sha256'], 'prior publisher receipt changed')
	require(sha(WORK.parent.parent/'reports/astra-report-current.zip') == PREDECESSOR, 'canonical predecessor changed before publication')
	preserved = preservation(WORK/'runtime/selfhost27b-intake/pre-edit-preservation.json')
	require(preserved == entry['preservation'], 'protected or peer inputs changed')
	require(sha(ROOT/'tests/selfhost-compiler-complete/run.py') == entry['peer_sha256'], 'peer file changed')
	require(git('rev-parse', BASE+'^{tree}') == TREE, 'base tree changed')
	require(not git('status', '--porcelain', '--untracked-files=no'), 'commit task changes before final audit')
	require(git('ls-files', '--others', '--exclude-standard') == 'tests/selfhost-compiler-complete/run.py', 'untracked inventory drift')
	require(subprocess.run(['git', '-C', ROOT, 'merge-base', '--is-ancestor', BASE, 'HEAD']).returncode == 0, 'history is not descended from intake')
	# The only compiler edit is the additive user-facing version banner.
	before = subprocess.check_output(['git', '-C', ROOT, 'show', BASE+':compiler/driver/main.astra'])
	after = (ROOT/'compiler/driver/main.astra').read_bytes()
	require(before.replace(b'astrac 27-C expressive development (GNU/Linux x86-64, E25-A-v1, LLVM 23)', b'astrac 0.0.3-dev28c1 (GNU/Linux x86-64, E25-A-v1, LLVM 23.1.4)') == after, 'unexpected compiler semantics change')
	require(git('diff', '--name-only', BASE, '--', 'compiler', 'lib') == 'compiler/driver/main.astra', 'unexpected compiler or library scope')
	old_fixtures = json.loads(subprocess.check_output(['git', '-C', ROOT, 'show', BASE+':tests/books/examples.json']))
	require(load(ROOT/'tests/books/examples.json') == old_fixtures and len(old_fixtures['cases']) == 63, 'Book fixture inventory changed')
	for row in old_fixtures['files']:
		require((ROOT/row['path']).read_bytes() == subprocess.check_output(['git', '-C', ROOT, 'show', BASE+':'+row['path']]), 'Book fixture changed: '+row['path'])
	seed = load(a.seed)
	require(seed['status'] == 'LOCAL_AUTHENTICATED_NOT_PUBLISHED' and seed['artifact']['sha256'] == sha(seed['artifact']['path']) == seed['repeated_sha256'], 'seed capsule authentication/reproduction absent')
	bootstrap = load(a.bootstrap/'result.json')
	require(bootstrap['reproducible'] and len(bootstrap['stages']) >= 2 and len(bootstrap['comparisons']) >= 8 and all(row['equal'] for row in bootstrap['comparisons']), 'bootstrap convergence absent')
	for stage in bootstrap['stages']:
		for product in stage['products'].values():
			for image in (product, product['native'], product['doc']):
				require(sha(image['path']) == image['sha256'], 'generated image changed')
			require(sha(product['object']) == product['object_sha256'], 'generated object changed')
	reg = load(a.regression/'result.json')
	require(reg['status'] in ('CURRENT_LOCAL_CONSOLIDATED_REGRESSION_PASS', 'CURRENT_LOCAL_CONSOLIDATED_REGRESSION_FAILED') and len(reg['suites']) == 9, 'consolidated current suite incomplete')
	for mode, product in reg['products'].items():
		final = bootstrap['products'][mode]
		for key in ('sha256', 'object_sha256'):
			require(product[key] == final[key], 'qualified compiler differs from converged generation')
		for key in ('native', 'doc'):
			require(product[key]['sha256'] == final[key]['sha256'], 'qualified image differs from converged generation')
	for row in reg['suites']:
		receipt = a.regression/row['label']/'result.json'
		if row['completed']:
			require(sha(receipt) == row['receipt_sha256'] and load(receipt)['status'] == row['status'], 'suite receipt changed')
		else:
			require(load(a.regression/(row['label']+'-controller')/'command.json')['status'] == 'FAILED', 'failed suite lacks actual failed controller')
	remaining = load(a.campaign/'books-remaining/result.json')
	require(remaining['status'] == 'DIAGNOSTIC_CASE_COVERAGE_NOT_FULL_QUALIFICATION', 'remaining Book observations absent')
	all_ids = {row['id'] for row in old_fixtures['cases']}
	require(set(remaining['previously_started']) | {row['case'] for row in remaining['cases']} == all_ids, 'Book case coverage absent')
	book_passed = set(re.findall(r'^([a-z0-9-]+) EXPECTED_OUTCOMES_PASS$', (a.regression/'books-controller/stdout').read_text(), re.M))
	for row in remaining['cases']:
		if row['passed']:
			receipt = a.campaign/'books-remaining'/row['case']/'result.json'
			require(sha(receipt) == row['receipt_sha256'] and load(receipt)['status'] == 'BOOK_CURRENT_NATIVE_O0_O2_STRICT_MEMORY_PASS', 'Book case receipt changed')
			book_passed.add(row['case'])
	api_repairs = {}
	for mode in ('O0', 'O2'):
		receipt = a.campaign/('api-repair-'+mode)/'result.json'
		require(load(receipt)['status'] == 'CURRENT_COMPILER_REAL_API_PREVIEWS_PASS', 'API preview repair remains unqualified')
		api_repairs[mode] = identify(receipt)
	physical = 0
	for path in (a.regression/'native').glob('*physical-*/result.json'):
		row = load(path)
		require(row['status'] == 'SELECTED_INDEPENDENT_PHYSICAL_MUTATIONS_PASS', 'independent physical suite failed')
		physical += row['mutations']
	require(physical == 46, 'independent physical mutation coverage differs')
	commands, memory, costs = streams([a.regression, a.campaign/'books-remaining', *[a.campaign/('api-repair-'+mode) for mode in ('O0', 'O2')]])
	require(bool(memory), 'no strict-memory evidence')
	failed_memory = [row for row in memory if not row['passed']]
	failed_suites = [row['label'] for row in reg['suites'] if not row['completed'] and row['label'] not in ('O0-api', 'O2-api')]
	c7 = not failed_memory and not failed_suites and book_passed == all_ids
	packages = {}
	for kind in ('deb', 'rpm'):
		package = getattr(a, kind+'_package')
		build = load(getattr(a, kind+'_build_receipt'))
		identity_path = getattr(a, kind+'_build_receipt').parent/'docs-build-identity.json'
		require(sha(identity_path) == build['build_identity_sha256'], 'package build identity changed')
		material = load(identity_path)['material']
		require(material['compiler_mode'] == 'O2' and material['compiler_object_sha256'] == bootstrap['products']['O2']['object_sha256'] and material['LLVM'] == '23.1.4', 'package object is not the converged O2 source product')
		for name, item in build['payload'].items():
			path = package.parent/'payload'/name
			require(sha(path) == item['sha256'] and path.stat().st_size == item['bytes'], 'package payload changed')
		installed = getattr(a, kind+'_install')
		result = load(installed/'result.json')
		require(sha(package) == build['artifact']['sha256'] == result['package_sha256'], 'package transport mismatch')
		require(result['status'] == 'CLEAN_INSTALL_SMOKE_REINSTALL_UNINSTALL_PASS', 'clean install/lifecycle not accepted')
		lifecycle = load(installed/'lifecycle/result.json')
		require(lifecycle['package_sha256'] == sha(package) and sha(installed/'lifecycle/result.json') == result['lifecycle_sha256'], 'lifecycle binding mismatch')
		names = {row['name'] for row in load(installed/'lifecycle/commands.json')}
		require({'ordinary-user-native', 'pre-reinstall-corruption', 'reinstall', 'after-reinstall', 'uninstall'} <= names, 'ordinary-user or repair/removal controls missing')
		smoke = load(installed/'lifecycle/smoke/result.json')
		require(smoke['status'] == 'INSTALLED_NATIVE_SMOKE_PASS' and smoke['clean_host'] and smoke['strict_memory'], 'installed native/memory scope incomplete')
		require(smoke['llvm_c_api_version'] == [23, 1, 4], 'installed LLVM runtime identity absent')
		guide = load(installed/'lifecycle/guide/result.json')
		require(guide['status'] == 'INSTALLED_GUIDE_VERBATIM_COMMANDS_PASS' and len(guide['blocks']) == 43, 'installed Guide replay incomplete')
		for name, digest in guide['sources'].items():
			require(sha(ROOT/name) == digest, 'Guide changed after installed qualification')
		for directory in (installed/'lifecycle', installed/'lifecycle/smoke'):
			for row in load(directory/'commands.json'):
				for stream in ('stdout', 'stderr'):
					path = directory/(row['name']+'.'+stream)
					require(sha(path) == row[stream+'_sha256'], 'installed command stream changed')
				if row.get('strict_memory'):
					require(memory_stream(directory/(row['name']+'.stderr'))['passed'], 'installed smoke memory failed')
		packages[kind] = dict(artifact=identify(package), build_receipt=identify(getattr(a, kind+'_build_receipt')), installation=identify(installed/'result.json'), smoke=identify(installed/'lifecycle/smoke/result.json'), guide=identify(installed/'lifecycle/guide/result.json'))
	formatted = load(a.format)
	require(formatted['changed'] == 0 and all(row['before_sha256'] == row['after_sha256'] == sha(ROOT/row['path']) for row in formatted['rows']), 'format receipt stale')
	refusals = load(a.campaign/'refusal-final/result.json')
	require(refusals['status'] == 'BOOTSTRAP_REFUSALS_PASS' and len(refusals['checks']) == 17 and all(row['refused'] for row in refusals['checks']), 'trust refusal controls incomplete')
	require(refusals['recipe_sha256'] == sha(ROOT/'tests/install/security.py'), 'refusal recipe changed')
	workflow = load(a.campaign/'workflow-validation.json')
	require(workflow['status'] == 'LOCAL_ACTIONLINT_PASS_NOT_HOSTED' and all(sha(ROOT/name) == digest for name, digest in workflow['sources'].items()), 'workflow lint evidence stale')
	windows = load(a.campaign/'windows-feasibility/result.json')
	require(not windows['native_compiler'] and not windows['installer_exe'] and not windows['hosted_run'], 'Windows disposition mismatch')
	require(load(a.campaign/'github-workflows-readonly/stdout')['total_count'] == 0, 'read-only GitHub observation differs')
	output = external(a.output)
	write(output/'execution-costs.json', dict(commands=costs, scope='Actual individual GNU time observations; overlapping controllers and children are not summed.'))
	write(output/'STREAMS.json', dict(commands=commands, memory=memory, failed_commands=[row for row in commands if row.get('exit') != row.get('expected') or row.get('timed_out')], scope='Raw stream integrity is independent of observed success; failures remain failures.'))
	result = dict(format='astra-installer-qualification/1', status='PARTIAL', audited_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), final_commit=git('rev-parse', 'HEAD'), final_tree=git('rev-parse', 'HEAD^{tree}'), base_commit=BASE, base_tree=TREE, gates={'C0':'PASS_EXACT_INTAKE_AND_ACTUAL_PREDECESSOR_PUBLICATION', 'C1':'PARTIAL_LINUX_CONVERGED_SEED_DISTRIBUTION_AND_WINDOWS_OPEN', 'C2':'PASS_NATIVE_LINUX_DEB_AND_RPM', 'C3':'BLOCKED_NATIVE_WINDOWS_COMPILER_AND_EXE_UNIMPLEMENTED', 'C4':'PARTIAL_LINUX_CLEAN_INSTALL_NATIVE_PASS_WINDOWS_OPEN', 'C5':'BLOCKED_NO_HOSTED_WORKFLOW_EXECUTION_OR_DISTRIBUTED_SEED', 'C6':'PASS_INSTALLED_LINUX_GUIDE_AND_EXPLICIT_WINDOWS_UNAVAILABILITY', 'C7':'PASS_SCOPED_CURRENT_LINUX_REGRESSION_AND_PRESERVATION' if c7 else 'PARTIAL_CURRENT_STRICT_MEMORY_FAILURES_REMAIN', 'C8':'PREPUBLICATION_COMPLETE_PENDING_INSTALLED_CANONICAL_PUBLISHER'}, seed_capsule=identify(a.seed), bootstrap=identify(a.bootstrap/'result.json'), regression=identify(a.regression/'result.json'), packages=packages, physical_mutations=physical, book_cases_attempted=len(all_ids), book_cases_strict_pass=sorted(book_passed), book_cases_unqualified=sorted(all_ids-book_passed), installed_guide_blocks_per_platform=43, regression_commands=len(commands), strict_memory_streams=len(memory), failed_memory_streams=failed_memory, failed_suites=failed_suites, repaired_api_previews=api_repairs, stream_audit=identify(output/'STREAMS.json'), formatter=identify(a.format), preservation=preserved, limitations=['Current broader compiler strict memory is NOT_PASS; unsuppressed optimizer diagnostics are retained, with no suppression or dependency substitution', 'No native Windows compiler chain or setup EXE; no native Windows execution', 'Read-only GitHub access worked but no workflows were remotely installed or run; no push authorized', 'Seed capsule is local; committed URL remains null and hosted acquisition refuses', 'Unsigned development packages; no signatures, public release, tag or deployment', 'Clean containers share the host kernel; cross-version upgrade remains unqualified', 'Current grammar dump preflight is not a fresh typed-source grammar regeneration', 'Rebuilt C0 ACCEPTED_WITH_DISCLOSURE; strict all-kinds C0 memory NOT_PASS; original C0 and 1044 proofs lost', 'Formal 28-A2-R1 PARTIAL and 222 semantic witnesses remain open'])
	write(output/'QUALIFICATION.json', result)
	print(json.dumps(dict(status=result['status'], physical_mutations=physical, book_cases_strict_pass=len(book_passed), failed_memory_streams=len(failed_memory), command_records=len(commands), strict_memory_streams=len(memory))))


if __name__ == '__main__':
	main()
