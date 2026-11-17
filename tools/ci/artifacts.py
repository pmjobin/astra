#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Export only explicitly identified build products and independent job digests."""
import argparse
import json
import os
from pathlib import Path
import shutil

from common import external, require, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--work', type=Path, required=True)
	p.add_argument('--kind', choices=('deb', 'rpm'), required=True)
	p.add_argument('--transfer', type=Path)
	a = p.parse_args()
	artifacts = list((a.work/'package').glob('*.'+a.kind))
	require(len(artifacts) == 1, 'one package required')
	package = artifacts[0]
	receipt = json.loads((a.work/'package-logs/result.json').read_text())
	require(sha(package) == receipt['artifact']['sha256'], 'package differs from build receipt')
	outputs = {'package_sha256':sha(package)}
	if a.transfer:
		destination = external(a.transfer)
		handoff = a.work/'handoff.json'
		data = json.loads(handoff.read_text())
		obj = a.work/'bootstrap/stage2/astrac-O2.o'
		require(sha(obj) == data['products']['O2']['object_sha256'], 'generation object mismatch')
		shutil.copyfile(obj, destination/'astrac-O2.o')
		shutil.copyfile(handoff, destination/'handoff.json')
		outputs['handoff_sha256'] = sha(handoff)
	write(a.work/'artifact-digests.json', outputs)
	if os.environ.get('GITHUB_OUTPUT'):
		with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
			for name, digest in outputs.items():
				stream.write(name+'='+digest+'\n')
	print(json.dumps(outputs))


if __name__ == '__main__':
	main()
