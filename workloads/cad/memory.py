#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unsuppressed normal CAD runs and independent numeric ownership observation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET


def run(build, inputs, observer, output):
	output.mkdir(parents=True, exist_ok=False)
	constant = inputs / 'constant-37-119-213-input.png'
	line = inputs / 'narrow-line-input.png'
	if not constant.is_file() or not line.is_file():
		raise RuntimeError('run the original Synthetic suite first; both pinned synthetic inputs are mandatory')
	cases = [(f'constant-{i}', [str(constant), str(output / f'constant-{i}.png'), '4', '3'], 0) for i in range(3)]
	cases += [('narrow-line', [str(line), str(output / 'narrow-line.png'), '8', '8', '--pixel-art'], 0), ('usage', [], 1), ('missing-input', [str(output / 'missing.png'), str(output / 'unused.png'), '1', '1'], 1), ('write-error', [str(constant), str(output / 'absent-parent/output.png'), '4', '3'], 1), ('ceiling', [str(line), str(output / 'ceiling.png'), '8', '8', '--pixel-art', '--max-iterations', '1'], 3)]
	env = dict(os.environ, LD_LIBRARY_PATH=str(build), CCACHE_DISABLE='1')
	rows = []
	for name, args, expected in cases:
		for category in ['normal-memory', 'ownership-observer']:
			label = name + '-' + category
			command = [str(build / 'astra-cad'), *args]
			selected_env = dict(env)
			if category == 'normal-memory':
				command = ['valgrind', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=97', '--xml=yes', '--xml-file=' + str(output / (label + '.xml')), *command]
			else:
				selected_env.update(LD_PRELOAD=str(observer), CAD_OBSERVER_OUTPUT=str(output / (label + '.json')))
			p = subprocess.run(command, cwd=output, env=selected_env, capture_output=True)
			(output / (label + '.stdout')).write_bytes(p.stdout)
			(output / (label + '.stderr')).write_bytes(p.stderr)
			row = {'name': name, 'category': category, 'argv': command, 'cwd': str(output), 'status': p.returncode, 'expected_status': expected}
			if category == 'normal-memory':
				xml = ET.parse(output / (label + '.xml'))
				row['errors'] = [node.findtext('kind') for node in xml.findall('error') if node.findtext('kind') != 'Leak_StillReachable']
				row['finished'] = xml.findall('status')[-1].findtext('state') == 'FINISHED'
				row['clean'] = not row['errors'] and row['finished']
			else:
				observation = json.loads((output / (label + '.json')).read_text())
				row['observation'] = observation
				row['clean'] = observation['observer_errors'] == observation['numeric_live_count'] == observation['numeric_live_bytes'] == 0 and observation['numeric_allocations'] == observation['numeric_releases'] and observation['argument_tables'] == observation['argument_table_releases']
				if observation['numeric_allocations'] and observation['argument_tables']:
					row['clean'] &= observation['last_numeric_release_sequence'] < observation['argument_release_sequence']
				row['same_visible_output'] = p.stdout == (output / (name + '-normal-memory.stdout')).read_bytes() and p.stderr == (output / (name + '-normal-memory.stderr')).read_bytes()
				row['clean'] &= row['same_visible_output']
			for path in [output / (name + '.png')]:
				if path.is_file():
					row['png_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
			rows.append(row)
			(output / 'results.json').write_text(json.dumps(rows, indent='\t') + '\n')
			if p.returncode != expected or not row['clean']:
				raise RuntimeError(f'{label}: {row}')
	for i in range(0, len(rows), 2):
		if 'png_sha256' in rows[i] and rows[i]['png_sha256'] != rows[i + 1]['png_sha256']:
			raise RuntimeError(f'observer changed output PNG: {rows[i]["name"]}')
	print(f'{len(cases)} clean normal runs; {len(cases)} matching independent ownership observations')
	return rows


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--build', type=Path, required=True)
	parser.add_argument('--synthetic-inputs', type=Path, required=True)
	parser.add_argument('--observer', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	args = parser.parse_args()
	run(args.build.resolve(), args.synthetic_inputs.resolve(), args.observer.resolve(), args.output.resolve())


if __name__ == '__main__':
	main()
