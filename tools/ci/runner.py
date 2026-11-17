#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Record actual runner/source identity without conferring release qualification."""
import argparse
import json
import os
from pathlib import Path
import platform
import subprocess

from common import ROOT, identify, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--output', type=Path, required=True)
	p.add_argument('--work', type=Path)
	a = p.parse_args()
	keys = ('GITHUB_REPOSITORY', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_SHA', 'GITHUB_REF', 'GITHUB_EVENT_NAME', 'GITHUB_WORKFLOW_REF', 'GITHUB_WORKFLOW_SHA', 'RUNNER_OS', 'RUNNER_ARCH', 'ImageOS', 'ImageVersion')
	hosted = os.environ.get('GITHUB_ACTIONS') == 'true'
	repo, run_id = os.environ.get('GITHUB_REPOSITORY'), os.environ.get('GITHUB_RUN_ID')
	result = None
	if a.work and (a.work/'result.json').is_file():
		result = json.loads((a.work/'result.json').read_text())
	row = dict(format='astra-hosted-smoke-observation/1', hosted_execution=hosted, run_url='https://github.com/'+repo+'/actions/runs/'+run_id if hosted and repo and run_id else None, source_commit=subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD'], text=True).strip(), source_tree=subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD^{tree}'], text=True).strip(), runner={key:os.environ.get(key) for key in keys}, host=platform.platform(), python=platform.python_version(), workflow_sources={str(path.relative_to(ROOT)):sha(path) for path in sorted((ROOT/'.github/workflows').glob('*.yml'))}, seed_manifest=identify(ROOT/'tools/ci/seed-linux.json'), llvm_manifest=identify(ROOT/'tools/ci/llvm-linux.json'), smoke_result=result, job_status_at_observation=os.environ.get('ASTRA_JOB_STATUS'), scope='Actual hosted identity only when GITHUB_ACTIONS=true. Seed smoke is independent of strict nightly qualification. Original LLVM and rebuilt-C0 strict-memory NOT_PASS, missing original C0/1044 proofs, incomplete Reference and unqualified Windows remain unchanged.')
	write(a.output, row)
	print(json.dumps(row, indent=2))


if __name__ == '__main__':
	main()
