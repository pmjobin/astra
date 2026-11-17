#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify the uploaded/downloaded smoke evidence without executing artifact code."""
import argparse
import json
import os
from pathlib import Path
import subprocess

from common import ROOT, identify, require, sha, write


def load(path):
	return json.loads(path.read_text())


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--input', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	root = a.input.resolve()
	require(not a.input.is_symlink() and not a.output.resolve().is_relative_to(ROOT) and not a.output.resolve().is_relative_to(root), 'unsafe artifact input/output routing')
	require(not any(path.is_symlink() for path in a.input.rglob('*')), 'artifact symlink refused')
	probe = root/'astra-pr/seed-smoke'
	result = load(probe/'result.json')
	pipeline = load(root/'astra-pr/result.json')
	runner = load(root/'astra-smoke-final.json')
	commit = subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD'], text=True).strip()
	tree = subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD^{tree}'], text=True).strip()
	require(runner['source_commit'] == commit and runner['source_tree'] == tree, 'artifact source identity differs from checkout')
	if os.environ.get('GITHUB_SHA'):
		require(commit == os.environ['GITHUB_SHA'], 'workflow source identity differs from checkout')
	lock = load(ROOT/'tools/ci/seed-linux.json')
	require(result['status'] == 'AUTHENTICATED_SEED_NATIVE_SMOKE_PASS' and pipeline['status'] == 'PR_SEED_NATIVE_SMOKE_PASS', 'smoke did not pass')
	require(result['seed']['sha256'] == lock['sha256'] and result['seed']['bytes'] == lock['bytes'], 'seed identity changed')
	require(result['llvm_c_api_version'] == [23, 1, 4] and result['current_compiler_generations_built'] == 0, 'smoke toolchain/scope changed')
	require(pipeline['release_qualified'] is False and pipeline['original_llvm_strict_memory'] == 'NOT_PASS', 'release qualification was incorrectly advanced')
	require({(row['case'], row['profile']) for row in result['products']} == {(case, mode) for case in ('main', 'owners') for mode in ('O0', 'O2')}, 'incomplete native smoke matrix')
	for row in result['products']:
		for kind in ('object', 'executable'):
			pin = row[kind]
			path = probe/Path(pin['path']).name
			require(path.stat().st_size == pin['bytes'] and sha(path) == pin['sha256'], 'downloaded native product changed')
	expected = {'tests/install/'+name for name in ('main.astra', 'owners.astra', 'abi.c', 'negative-type.astra', 'negative-owner.astra')}
	require(set(result['fixture_inputs']) == expected, 'unexpected fixture source set')
	for path, pin in result['fixture_inputs'].items():
		require(sha(ROOT/path) == pin['sha256'], 'fixture differs from current source')
	commands = []
	for path in sorted(root.rglob('command.json')):
		row = load(path)
		require(row['status'] == 'EXPECTED_OUTCOME' and row['exit'] == row['expected_exit'], 'failed or incomplete command in passing smoke artifact')
		for name, pin in row['streams'].items():
			require(name in ('stdout', 'stderr', 'time.txt'), 'unexpected artifact stream path')
			stream = path.parent/name
			require(stream.stat().st_size == pin['bytes'] and sha(stream) == pin['sha256'], 'artifact command stream changed')
		commands.append(str(path.relative_to(root)))
	require(bool(commands), 'no native command evidence')
	write(a.output, dict(status='SMOKE_ARTIFACT_ROUNDTRIP_VERIFIED', source_commit=commit, source_tree=tree, seed_sha256=lock['sha256'], products=4, command_records=len(commands), files={str(path.relative_to(root)):identify(path) for path in root.rglob('*') if path.is_file()}, scope='Actual artifact transfer and hash verification only. No downloaded code executed; strict qualification, Windows and release status remain separate.'))
	print('SMOKE_ARTIFACT_ROUNDTRIP_VERIFIED', len(commands), 'command records')


if __name__ == '__main__':
	main()
