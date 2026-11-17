#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Hosted Linux orchestration; missing distribution is an error, never a skip."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

from common import ROOT, clean_environment, external, identify, require, run, sha, verify, write
from preflight import qualification_inputs
from trust import fetch, seed_manifest


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--lane', choices=('pr', 'nightly'), required=True)
	p.add_argument('--work', type=Path, required=True)
	p.add_argument('--seed', type=Path, help='Explicit local input, still checked against the committed seed pin')
	a = p.parse_args()
	work = external(a.work)
	logs = work/'logs'
	logs.mkdir()
	env = clean_environment()
	seed_lock = seed_manifest(ROOT/'tools/ci/seed-linux.json')
	# Refuse before large downloads when the approved seed is unavailable.
	seed = verify(a.seed, seed_lock) if a.seed else fetch(seed_lock, work/'seed')
	if not a.seed:
		seed.chmod(0o755)
	if a.lane == 'nightly':
		require(not (missing := qualification_inputs(ROOT.parent/'codex/work/astra')), '; '.join(missing))
	require(shutil.disk_usage(work).free >= 4*1024**3, 'less than 4 GiB available for selected LLVM inputs and native build')
	def script(name, args, timeout=7200):
		run([sys.executable, '-B', ROOT/'tools/ci'/name, *args], logs/name.removesuffix('.py'), env, timeout=timeout)
	script('trust.py', ['--manifest', ROOT/'tools/ci/llvm-linux.json', '--output', work/'llvm'])
	llvm = work/'llvm/unpacked'
	script('llvm_dylib.py', ['--llvm', llvm, '--manifest', ROOT/'tools/ci/llvm-linux.json', '--build', work/'llvm-library', '--runtime', work/'llvm-library-logs'])
	library, receipt = work/'llvm-library/libLLVM.so.23.1', work/'llvm-library-logs/result.json'
	script('seed_probe.py', ['--seed', seed, '--library', library, '--library-receipt', receipt, '--output', work/'seed-smoke'])
	if a.lane == 'pr':
		write(work/'result.json', dict(status='PR_SMOKE_ONLY', seed=identify(seed), source_commit=subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD'], text=True).strip()))
		return
	head = subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD'], text=True).strip()
	script('bootstrap.py', ['--seed', seed, '--llvm', llvm, '--library', library, '--library-receipt', receipt, '--commit', head, '--build', work/'bootstrap', '--runtime', work/'bootstrap-logs', '--stages', '2', '--jobs', '2'], timeout=18000)
	products = work/'bootstrap-logs/result.json'
	# These independent suites retain source-owner, ABI, physical mutation,
	# all Book cases and boundary checks. A failure blocks packaging and keeps
	# every suite's evidence available to the workflow artifact step.
	legacy = ROOT.parent/'codex/work/astra'
	run_name = 'ci-'+str(os.environ.get('GITHUB_RUN_ID', os.getpid()))+'-'+str(os.environ.get('GITHUB_RUN_ATTEMPT', '1'))
	qualification = legacy/'runtime'/(run_name+'-qualification')
	try:
		run([sys.executable, '-B', ROOT/'tests/install/regression.py', '--products', products, '--identity', work/'bootstrap-logs/docs-build-identity.json', '--link', work/'bootstrap-logs/link.json', '--toolchain', work/'bootstrap-logs/toolchain.json', '--build', legacy/'build'/(run_name+'-qualification'), '--runtime', qualification], logs/'qualification', env, timeout=14400)
	except (ValueError, OSError, subprocess.TimeoutExpired):
		write(work/'result.json', dict(status='CURRENT_LOCAL_CONSOLIDATED_REGRESSION_FAILED', source_commit=head, hosted_run_id=os.environ.get('GITHUB_RUN_ID'), release_authorized=False))
		raise
	finally:
		if qualification.is_dir():
			shutil.copytree(qualification, logs/'qualification-evidence')
	script('handoff.py', ['--products', products, '--identity', work/'bootstrap-logs/identity.json', '--output', work/'handoff.json'])
	script('package.py', ['--object', work/'bootstrap/stage2/astrac-O2.o', '--handoff', work/'handoff.json', '--llvm', llvm, '--library', library, '--library-receipt', receipt, '--kind', 'deb', '--build', work/'package', '--runtime', work/'package-logs'])
	write(work/'result.json', dict(status='PARTIAL_REQUIRES_SEPARATE_INSTALL_AND_WINDOWS', source_commit=head, bootstrap_receipt=identify(products), package_receipt=identify(work/'package-logs/result.json'), hosted_run_id=os.environ.get('GITHUB_RUN_ID'), gates=dict(native_linux='BUILT_AND_REGRESSION_TESTED', clean_install='PENDING_SEPARATE_JOB', native_windows='BLOCKED_PORT_AND_SEED'), release_authorized=False))


if __name__ == '__main__':
	main()
