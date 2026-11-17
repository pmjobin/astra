#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Record hosted job outcomes without promoting the unfinished Windows gate."""
import argparse
import json
import os
from pathlib import Path

from common import write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	needs = json.loads(os.environ['ASTRA_JOB_OUTCOMES'])
	write(a.output, dict(format='astra-ci-qualification/1', status='PARTIAL', source_commit=os.environ['GITHUB_SHA'], run_id=os.environ['GITHUB_RUN_ID'], run_url='https://github.com/'+os.environ['GITHUB_REPOSITORY']+'/actions/runs/'+os.environ['GITHUB_RUN_ID'], jobs={name:row['result'] for name, row in needs.items()}, blockers=['Native Windows seed/compiler/installer and native execution remain unavailable', 'Installed canonical milestone qualification is a separate owner workflow'], public_release=False))


if __name__ == '__main__':
	main()
