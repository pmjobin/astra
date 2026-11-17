#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Owner-only candidate gate. Never creates a release, tag, deployment or key."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

from common import external, require, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--candidate', required=True)
	p.add_argument('--run-id', required=True)
	p.add_argument('--qualification', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	require(re.fullmatch('[0-9a-f]{40}', a.candidate) and re.fullmatch('[0-9]+', a.run_id), 'exact candidate SHA and numeric run ID required')
	repo = os.environ['GITHUB_REPOSITORY']
	require(repo == 'pmjobin/astra' and os.environ['GITHUB_REF'] == 'refs/heads/main' and os.environ['GITHUB_ACTOR'] == os.environ['GITHUB_REPOSITORY_OWNER'], 'owner/default-branch preparation required')
	run = json.loads(subprocess.check_output(['gh', 'api', 'repos/'+repo+'/actions/runs/'+a.run_id]))
	require(run['head_sha'] == a.candidate and run['status'] == 'completed' and run['conclusion'] == 'success', 'candidate has no successful completed qualification run')
	require(run['event'] in ('schedule', 'workflow_dispatch') and run['path'] == '.github/workflows/nightly.yml' and run['head_repository']['full_name'] == repo, 'untrusted qualification origin')
	qualification = json.loads(a.qualification.read_text())
	require(qualification['status'] == 'PASS' and qualification['source_commit'] == a.candidate and str(qualification['run_id']) == a.run_id, 'qualification is partial, stale or belongs to another candidate')
	require(set(qualification['gates']) == {'C'+str(n) for n in range(9)} and all(v == 'PASS' for v in qualification['gates'].values()), 'required acceptance gates remain open')
	require(qualification['native_windows_install_receipt'] and qualification['clean_deb_receipt'] and qualification['clean_rpm_receipt'], 'native installer receipts required')
	out = external(a.output)
	write(out/'candidate.json', dict(format='astra-release-preparation/1', status='PREPARED_FOR_OWNER_REVIEW_NOT_PUBLICATION', source_commit=a.candidate, qualification_sha256=sha(a.qualification), qualifying_run=run['html_url'], public_release=False))


if __name__ == '__main__':
	main()
