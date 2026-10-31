# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the reconciliation challenge with opaque or monolithic native code."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LIBRARIES = ['base/errors.astra', 'collections/bag.astra', 'text/utf8-message.astra',
	'text/utf8-byte-builder.astra', 'hosted/text-ops.astra', 'text/scalar-format.astra', 'hosted/text.astra']
INSTANCE = 'Inventory<Reconcile.StockKey,Reconcile.StockValue,Reconcile.InventoryContext<int>>'
EXPORTS = ['StockKey', 'StockValue', 'StockSnapshot', 'Change', 'Proposal', 'Receipt',
	'InventoryContext<int>', 'AuditContext<int>', INSTANCE, INSTANCE + '::project<Reconcile.StockSnapshot>',
	'StockList', 'Error', 'InputError', 'UnknownKey', 'StaleRevision', 'Overdraw', 'Overflow',
	'AuditFailure', 'InvalidReceipt', 'IntegerParseError', 'TextRangeError', 'TextCapacityError',
	'Utf8Message', 'Utf8ByteBuilder', 'InvalidUtf8', 'parse_int', 'append_text', 'append_int', 'require_text',
	'print', 'println_stderr', 'inspect', 'apply', 'reconciliation_observe']


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def renamed(text):
	replacements = dict([('Inventory', 'StockState'), ('identifier', 'identity_value'),
		('stock', 'stored_value'), ('context', 'owned_notes'), ('generation', 'current_revision')])
	# Preserve protocol strings and comments while changing identifier tokens.
	pattern = r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/|\b[A-Za-z_][A-Za-z_0-9]*\b'
	text = re.sub(pattern, lambda match: replacements.get(match.group(), match.group()), text, flags=re.S)
	fields = '\tprivate K identity_value;\n\tprivate V stored_value;\n\tprivate owned Context owned_notes;\n\tprivate int current_revision;'
	if fields in text:
		text = text.replace(fields, '\n'.join(reversed(fields.splitlines())))
	return text


def build(compiler, output, library_root, mode='native', levels=(0, 0), variant=False):
	compiler = compiler.resolve(strict=True)
	output = output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='reconcile-' + mode + '-', dir=output))
	libraries = [library_root.resolve(strict=True) / name for name in LIBRARIES]
	adapters = [library_root / ('platform/' + name + '.c') for name in ['args-posix', 'text-posix', 'text-ops-posix']]
	adapters.append(HERE / 'observer.c')
	sources = [HERE / 'inventory.astra', HERE / 'cli.astra', *libraries, *adapters, Path(__file__)]
	receipt = dict(format='astra-m15-reconciliation-build/1', compiler_sha256=sha(compiler),
		mode=mode, levels=list(levels), variant=variant, sources={str(p): sha(p) for p in sources},
		checks=[], products={}, producer_sources_hidden=False)

	def save():
		(out / 'build.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	def run(argv):
		argv = list(map(str, argv))
		started = time.perf_counter()
		result = subprocess.run(argv, cwd=out, capture_output=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == 0 and not result.stdout and not result.stderr
		receipt['checks'].append(dict(argv=argv, passed=passed, exit=result.returncode,
			elapsed_seconds=time.perf_counter() - started,
			stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace')))
		save()
		assert passed, receipt['checks'][-1]

	provider = out / 'inventory.astra'
	client = out / 'cli.astra'
	text = (HERE / 'inventory.astra').read_text() + '\n' + '\n'.join(p.read_text() for p in libraries)
	provider.write_text(renamed(text) if variant else text)
	text = (HERE / 'cli.astra').read_text()
	client.write_text(renamed(text) if variant else text)
	objects = []
	for source in adapters:
		obj = out / (source.stem + '.o')
		run(['cc', '-std=c11', '-g', '-O2', '-Wall', '-Wextra', '-Werror', '-c', source, '-o', obj])
		objects.append(obj)
	if mode == 'native':
		selectors = [renamed(name) if variant else name for name in EXPORTS]
		run([compiler, '-g', '-O' + str(levels[0]), '-c', '--module', 'Reconcile',
			*[arg for name in selectors for arg in ['--native-export', 'Reconcile.' + name]],
			'--emit-interface', out / 'inventory.asti', provider, '-o', out / 'inventory.o'])
		provider.unlink()
		receipt['producer_sources_hidden'] = True
		run([compiler, '-g', '-O' + str(levels[1]), '--import-module', out / 'inventory.asti', client,
			*[arg for obj in objects for arg in ['--link-object', obj]], '-o', out / 'reconcile'])
		receipt['products'][str(out / 'inventory.asti')] = sha(out / 'inventory.asti')
		receipt['products'][str(out / 'inventory.o')] = sha(out / 'inventory.o')
	else:
		run([compiler, '-g', '-O' + str(levels[1]), '--entry-object', provider, client, '-o', out / 'reconcile.o'])
		run(['cc', '-no-pie', out / 'reconcile.o', *objects, '-o', out / 'reconcile'])
		receipt['products'][str(out / 'reconcile.o')] = sha(out / 'reconcile.o')
	for obj in [*objects, out / 'reconcile']:
		receipt['products'][str(obj)] = sha(obj)
	assert sha(compiler) == receipt['compiler_sha256']
	assert all(sha(Path(path)) == digest for path, digest in receipt['sources'].items())
	receipt['built'] = True
	save()
	return out / 'build.json'


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	parser.add_argument('--library-root', type=Path, default=ROOT / 'lib/astra')
	parser.add_argument('--mode', choices=['native', 'mono'], default='native')
	parser.add_argument('--levels', type=int, choices=[0, 1, 2], nargs=2, default=[0, 0])
	parser.add_argument('--variant', action='store_true')
	args = parser.parse_args()
	print(build(args.compiler, args.output, args.library_root, args.mode, args.levels, args.variant))
