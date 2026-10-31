#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reject false registry closure and compare independent SDK/docs archive bytes."""
from pathlib import Path
import copy
import hashlib
import json
import runpy
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main(build, runtime):
	build, runtime = Path(build).resolve(), Path(runtime).resolve()
	for path in [build, runtime]:
		assert not path.is_relative_to(ROOT); path.mkdir(parents=True, exist_ok=True)
	products = Path(tempfile.mkdtemp(prefix='release-policy-', dir=build))
	receipts = Path(tempfile.mkdtemp(prefix='release-policy-', dir=runtime))
	policy = runpy.run_path(str(ROOT / 'tools/release/integrity.py'))
	check = policy['check_current_registry']
	base = dict(source_freeze=dict(commit='qualified'), full_registry_pass=True, selected_pass=True,
		exit=0, stage='REGISTRY_PASS', source_unchanged=True, compiler_unchanged=True, registry_unchanged=True,
		held=[], missing_selected=[], unexpected=[], duplicates=[], nonpassing=[], tap_skips=[],
		registry=[dict(name='positive'), dict(name='refusal')], selected_registrations=['positive', 'refusal'],
		results=[dict(name='astra:positive', result='OK'), dict(name='astra:refusal', result='OK')])
	check(base, 'qualified')
	mutations = {
		'wrong-source': lambda d: d['source_freeze'].update(commit='different'),
		'held-guest': lambda d: d['held'].append(dict(name='guest')),
		'skipped-assertion': lambda d: d['tap_skips'].append(dict(registration='positive', line='ok 1 # SKIP')),
		'missing-result': lambda d: d['results'].pop(),
		'duplicate-result': lambda d: d['results'].__setitem__(1, d['results'][0]),
		'duplicate-registration': lambda d: d['registry'].__setitem__(1, d['registry'][0]),
		'unexpected-result': lambda d: d['results'][1].update(name='astra:unregistered'),
		'nonpassing-result': lambda d: d['results'][1].update(result='TIMEOUT'),
		'false-source-conservation': lambda d: d.update(source_unchanged=False),
		'false-compiler-conservation': lambda d: d.update(compiler_unchanged=False),
		'false-registry-conservation': lambda d: d.update(registry_unchanged=False),
	}
	refused = []
	for name, mutate in mutations.items():
		data = copy.deepcopy(base); mutate(data)
		try: check(data, 'qualified')
		except AssertionError: refused.append(name)
		else: raise AssertionError(name)
	archives = []
	for label in ['a', 'b']:
		prefix = products / label
		for name, content, mode in [('share/astra/library.astra', b'int f(){return 42;}\n', 0o644),
			('share/astra/docs/guide.md', b'Guide\n', 0o644), ('share/licenses/astra/LICENSE.txt', b'License fixture\n', 0o644),
			('bin/astrac', b'not a compiler\n', 0o755)]:
			path = prefix / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(content); path.chmod(mode)
		archive = products / (label + '.tar.gz')
		review = products / (label + '-review.md'); review.write_text('Review fixture\n'); review.chmod(0o644)
		extra_name = 'astra-dev/share/astra/docs/review.md'
		policy['split_archive'](prefix, archive, 1234567890, lambda p: p.startswith('share/'), [(extra_name, review)])
		members = policy['archive_members'](archive)
		assert {m['path'] for m in members} == {extra_name, *['astra-dev/' + p for p in ['share/astra/library.astra', 'share/astra/docs/guide.md', 'share/licenses/astra/LICENSE.txt']]}
		assert [m['path'] for m in members] == sorted(m['path'] for m in members)
		assert all(m['mtime'] == 1234567890 and m['mode'] == 0o644 for m in members)
		assert all(m['sha256'] == hashlib.sha256((review if m['path'] == extra_name else prefix / m['path'].removeprefix('astra-dev/')).read_bytes()).hexdigest() for m in members)
		archives.append(archive)
	assert archives[0].read_bytes() == archives[1].read_bytes()
	data = dict(status='PASS', scope='Release guard mutations and deterministic split-archive fixtures; no candidate qualification or promotion',
		refused=refused, independent_archive_sha256=hashlib.sha256(archives[0].read_bytes()).hexdigest(),
		inputs={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__).resolve(), ROOT / 'tools/release/integrity.py']})
	(receipts / 'checks.json').write_text(json.dumps(data, indent=2) + '\n'); print(receipts / 'checks.json')


if __name__ == '__main__': main(*sys.argv[1:])
