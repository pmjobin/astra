#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind current diagnostic qualification without advancing unavailable release gates."""
import argparse
import datetime
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tools/ci'))
from common import external, identify, require, sha, write

spec = importlib.util.spec_from_file_location('installer_stream_audit', ROOT/'tests/install/audit.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
BASE = '4c96dd81e571742fa74739c561e72e793f3f5852'
TREE = '2441302d08ed3f507c34c031a4ac0f4842de541e'


def load(path):
	return json.loads(Path(path).read_text())


def git(*args):
	return subprocess.check_output(['git', '-C', ROOT, *args], text=True).strip()


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--campaign', type=Path, required=True)
	p.add_argument('--format', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	campaign = a.campaign
	entry = load(campaign/'intake.json')
	require(entry['HEAD'] == BASE and entry['tree'] == TREE and git('rev-parse', BASE+'^{tree}') == TREE, 'intake base changed')
	require(not git('status', '--porcelain', '--untracked-files=no'), 'commit task-owned inputs before final audit')
	require(git('ls-files', '--others', '--exclude-standard') == 'tests/selfhost-compiler-complete/run.py', 'untracked inventory changed')
	require(sha(ROOT/'tests/selfhost-compiler-complete/run.py') == entry['peer']['sha256'], 'peer work changed')
	require(subprocess.run(['git', '-C', ROOT, 'merge-base', '--is-ancestor', BASE, 'HEAD']).returncode == 0, 'history no longer descends from intake')
	require(not git('diff', BASE, 'HEAD', '--', 'compiler', 'lib'), 'compiler/runtime changed without a new product qualification')
	for path, digest in entry['installed'].items():
		require(sha(path) == digest, 'installed pm-next changed')
	for path, digest in entry['protected'].items():
		require(sha(ROOT/path) == digest, 'protected input changed: '+path)
	base_scope = json.loads(subprocess.check_output(['git', '-C', ROOT, 'show', BASE+':format/scope.json']))
	scope = load(ROOT/'format/scope.json')
	require(all(scope[name] == row for name, row in base_scope.items()), 'existing format classification changed')
	preserved = audit.preservation(WORK/'runtime/selfhost27b-intake/pre-edit-preservation.json')
	require(sha(entry['C8']['path']) == entry['C8']['sha256'], 'predecessor postpublication receipt changed')
	publication = load(entry['C8']['path'])
	require(publication['status'] == 'ACTUAL_INSTALLED_PUBLISHER_AND_INDEPENDENT_REOPEN_VERIFIED' and sha(publication['report']['path']) == publication['report']['sha256'], 'predecessor canonical identity no longer matches')
	manifest = load(ROOT/'tests/books/examples.json')
	case_ids = {row['id'] for row in manifest['cases']}
	require(len(case_ids) == 63, 'Book case inventory changed')
	for directory, recipe in [('books', 'tests/books/run.py'), ('limits', 'tests/books/limits.py'), ('native', 'tests/api-docs/qualify.py')]:
		require(sha(campaign/directory/'executed-recipe.py.txt') == sha(ROOT/recipe), 'qualification recipe changed after execution')
	for row in manifest['files']:
		require((ROOT/row['path']).read_bytes() == subprocess.check_output(['git', '-C', ROOT, 'show', BASE+':'+row['path']]), 'Book fixture changed')
	book = load(campaign/'books/result.json')
	require(book['status'] == 'BOOK_CURRENT_NATIVE_O0_O2_STRICT_MEMORY_PASS' and book['full_manifest'] and len(book['profiles']) == 252, 'full Book matrix absent')
	require({row['id'] for row in book['cases']} == case_ids and all(row['passed'] for row in book['profiles']), 'Book profile failure')
	expected_profiles = {case+'-'+host+'-'+target for case in case_ids for host in ('O0', 'O2') for target in ('O0', 'O2')}
	require({row['label'] for row in book['profiles']} == expected_profiles, 'Book profile matrix drift')
	for path, digest in {**book['inputs'], **book['emit_products']}.items():
		require(sha(path) == digest, 'Book input/product changed')
	limits = load(campaign/'limits/result.json')
	require(limits['status'] == 'CURRENT_GENERIC_LAZY_CAPTURE_COMPREHENSION_AND_PARSER_BOUNDARIES_PASS' and not limits['failures'], 'boundary suite failed')
	require(sha(campaign/'limits/cases.json') == limits['cases_sha256'] and sha(campaign/'limits/commands.json') == limits['commands_sha256'], 'boundary receipts changed')
	for path, digest in {**limits['inputs'], **limits['emit_products']}.items():
		require(sha(path) == digest, 'boundary input/product changed')
	native = load(campaign/'native/result.json')
	require(native['status'] == 'CURRENT_CONSOLIDATED_NATIVE_ABI_OWNER_PHYSICAL_PASS' and native['profiles'] == ['O0', 'O2'] and len(native['suites']) == 23, 'native/ABI/source-owner suites incomplete')
	for row in native['suites']:
		require(row['result']['status'] == 'EXPECTED_OUTCOME' and sha(campaign/'native'/row['label']/'result.json') == row['receipt_sha256'], 'native suite receipt changed')
		accepted = {'SELECTED_EXPRESSIVE_NATIVE_AND_MEMORY_PASS', 'SELECTED_CURRENT_COMPILER_NATIVE_GATES_PASS', 'SELECTED_INTRINSIC_ABI_NATIVE_GATES_PASS', 'EXISTING_C_TO_ASTRA_STRING_DESCRIPTOR_CLIENT_PASS', 'SELECTED_INDEPENDENT_PHYSICAL_MUTATIONS_PASS', 'FOCUSED_EXPRESSIVE_SEMANTIC_COMPONENT_PASS'}
		require(load(campaign/'native'/row['label']/'result.json')['status'] in accepted, 'native suite lacks its acceptance result')
	for product in native['products'].values():
		for image in (product, product['native'], product['doc']):
			require(sha(image['path']) == image['sha256'], 'qualified compiler image changed')
	physical = sum(load(path)['mutations'] for path in (campaign/'native').glob('*physical-*/result.json') if not path.parent.name.endswith('-controller'))
	require(physical == 46, 'physical mutation count changed')
	commands, memory, costs = audit.streams([campaign/'books', campaign/'limits', campaign/'native'])
	require(memory and all(row['passed'] for row in memory), 'diagnostic-candidate strict memory failed')
	toolchain = load(campaign/'candidate-toolchain.json')
	for path, digest in toolchain['tools'].items():
		require(sha(path) == digest, 'candidate tool changed')
	require(book['inputs'][str(campaign/'candidate-toolchain.json')] == sha(campaign/'candidate-toolchain.json'), 'Book candidate routing receipt changed')
	oracle = load(campaign/'oracle-final/result.json')
	require(oracle['status'] == 'ORIGINAL_FAILURE_REPRODUCED_REBUILT_ORACLE_STRICT_CLEAN' and all(oracle['optimized_IR_equal'].values()), 'final oracle comparison failed')
	for variant in ('original', 'candidate'):
		require(sha(oracle[variant]['path']) == oracle[variant]['sha256'], 'oracle library changed')
	for distro in ('ubuntu', 'fedora'):
		result = load(campaign/(distro+'-diagnostic-final/result.json'))
		require(result['status'] == 'HISTORICAL_INSTALLED_PAYLOAD_WITH_ISOLATED_LLVM_REBUILD_FOCUSED_PASS', 'focused installed comparison failed')
		require(result['package']['sha256'] in ('8c260da73471814caf780a604d74b3af454a4526dcb0dbe3dc635fcc1bff5386', '2207c00cba71651ef9e1cedbcc45c3a9f919dffcddc48de909b4a894ea6d5869'), 'historical package identity changed')
	negative = load(campaign/'original-book-values/result.json')
	require(negative['status'] == 'BOOK_CURRENT_NATIVE_O0_O2_STRICT_MEMORY_FAILURE' and len(negative['profiles']) == 4 and sum(not row['passed'] for row in negative['profiles']) == 2, 'Book keep-going no longer rejects original memory failure')
	negative_limits = load(campaign/'original-boundaries/result.json')
	require(negative_limits['status'] == 'BOUNDARY_FAILURE' and len(negative_limits['failures']) == 8, 'boundary keep-going no longer rejects original memory failures')
	formatted = load(a.format)
	require(formatted['changed'] == 0 and all(sha(ROOT/row['path']) == row['before_sha256'] == row['after_sha256'] for row in formatted['rows']), 'format receipt stale')
	require(all(sha(ROOT/path) == digest for path, digest in formatted['configs'].items()), 'formatter configuration changed')
	security = load(campaign/'security-final/result.json')
	require(security['status'] == 'BOOTSTRAP_REFUSALS_PASS' and len(security['checks']) == 17 and all(row['refused'] for row in security['checks']), 'trust controls incomplete')
	preflight = load(campaign/'hosted-preflight-final.json')
	require(preflight['status'] == 'BLOCKED' and preflight['hosted_execution'] is False and load(ROOT/'tools/ci/seed-linux.json')['url'] is None, 'hosted disposition changed')
	readiness = load(campaign/'qualification-input-controls.json')
	require(readiness['status'] == 'QUALIFICATION_READINESS_CONTROLS_PASS' and not readiness['authenticated_local_inputs'] and len(readiness['missing_cold_runner']) == len(readiness['modified_cold_runner']) == 2, 'qualification input refusal incomplete')
	workflow = load(campaign/'workflow-validation.json')
	require(workflow['status'] == 'LOCAL_ACTIONLINT_PASS_NOT_HOSTED' and workflow['tool']['sha256'] == 'c872d6db8c6bf83a8eaa704fc93999f027d55dffbc63b8a6abdccb47df5f4cd4' and sha(workflow['tool']['path']) == workflow['tool']['sha256'], 'workflow validator identity changed')
	require(all(sha(ROOT/path) == digest for path, digest in workflow['sources'].items()), 'workflow lint receipt stale')
	prior = load(WORK/'runtime/release28c1/audit-final/QUALIFICATION.json')
	packages = prior['packages']
	for row in packages.values():
		require(sha(row['artifact']['path']) == row['artifact']['sha256'], 'historical installer changed')
		row['qualification_scope'] = 'HISTORICAL_28C1_NOT_A_NEW_FINAL_DERIVATIVE_PACKAGE'
	output = external(a.output)
	write(output/'STREAMS.json', dict(commands=commands, memory=memory, costs=costs, scope='Current broad Linux replay with the isolated Clang object rebuild. Original-library failures and other diagnostic derivatives are separate observations.'))
	result = dict(format='astra-installer-completion-qualification/1', status='PARTIAL', audited_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), final_commit=git('rev-parse', 'HEAD'), final_tree=git('rev-parse', 'HEAD^{tree}'), base_commit=BASE, base_tree=TREE, gates={'R0':'PASS_AUTHENTICATED_CORRECTED_INTAKE_AND_GENUINE_C8', 'R1':'PARTIAL_OBJECT_ISOLATED_DIAGNOSTIC_REBUILD_CLEAN_ORIGINAL_NOT_PASS_CAUSE_UNRESOLVED', 'R2':'PARTIAL_HISTORICAL_INSTALLERS_PRESERVED_NO_NEW_FINAL_PACKAGES', 'R3':'BLOCKED_NO_AUTHORIZED_NATIVE_WINDOWS_HOST_OR_PORT_EXE', 'R4':'BLOCKED_OWNER_AUTHORIZATION_AND_IMMUTABLE_SEED_DISTRIBUTION', 'R5':'PARTIAL_FULL_LINUX_DIAGNOSTIC_REPLAY_PASS_FINAL_BASELINE_UNQUALIFIED', 'R6':'PARTIAL_HISTORICAL_LINUX_GUIDE_WINDOWS_OPEN', 'R7':'PARTIAL_ORIGINAL_TRUST_PRESERVED_DIAGNOSTIC_DEPENDENCY_NOT_APPROVED', 'R8':'PREPUBLICATION_PENDING_INSTALLED_PUBLISHER_AND_REOPEN'}, book_cases=63, book_profiles=252, native_suites=23, physical_mutations=physical, boundary_cases=len(load(campaign/'limits/cases.json')), strict_memory_streams=len(memory), failed_candidate_memory_streams=[], stream_audit=identify(output/'STREAMS.json'), broad_candidate_toolchain=identify(campaign/'candidate-toolchain.json'), focused_oracle=identify(campaign/'oracle-final/result.json'), packages=packages, preservation=preserved, formatter=identify(a.format), historical_dispositions=prior['limitations'], limitations=['Original LLVM library remains NOT_PASS; exact upstream producer cause is unresolved', 'Broad current replay selects an unapproved diagnostic object rebuild; no source patch or baseline substitution', 'Historical packages only; no fresh final installer or new lifecycle qualification', 'No native Windows port, compiler, selfhosting, EXE or Windows lifecycle', 'No authorized GitHub push or seed distribution and no hosted run', 'No code signing, public release, secret mutation or VM startup'])
	write(output/'QUALIFICATION.json', result)
	print(json.dumps(dict(status='PARTIAL', book_profiles=252, native_suites=23, physical_mutations=physical, strict_memory_streams=len(memory))))


if __name__ == '__main__':
	main()
