# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Instrument actual emitted Astra application bodies with AddressSanitizer.

This monolithic memory check supplements opaque native-unit qualification. Its
LLVM startup wrapper follows the existing six-step GNU x64 argv protocol; it
contains no application algorithm. Runtime/OS adapter objects are uninstrumented.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def module(name, path):
	spec = importlib.util.spec_from_file_location(name, path)
	loaded = importlib.util.module_from_spec(spec)
	sys.modules[name] = loaded
	spec.loader.exec_module(loaded)
	return loaded


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('build_output', type=Path)
	parser.add_argument('runtime_output', type=Path)
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	output = args.runtime_output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='application-asan-', dir=output))
	receipt = dict(format='astra-m15-emitted-application-asan/1', compiler_sha256=sha(compiler),
		recipe_sha256=sha(Path(__file__)), builds=[], checks=[], products={},
		scope='AddressSanitizer on monolithic emitted Astra bodies and the explicit LLVM startup wrapper; existing runtime/OS adapter objects are uninstrumented. No opaque-unit or UBSan credit from this recipe.')

	def save():
		(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	def run(argv, cwd=out, expected=b'', code=0, dump=False):
		argv = list(map(str, argv))
		result = subprocess.run(argv, cwd=cwd, capture_output=True, timeout=180,
			env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1', CCACHE_DISABLE='1',
			ASAN_OPTIONS='detect_leaks=1:halt_on_error=1', UBSAN_OPTIONS='halt_on_error=1'))
		passed = result.returncode == code and not result.stderr and (dump or result.stdout == expected)
		receipt['checks'].append(dict(argv=argv, cwd=str(cwd), exit=result.returncode, expected_exit=code,
			passed=passed, stdout_sha256=hashlib.sha256(result.stdout).hexdigest(), stderr=result.stderr.decode(errors='replace')))
		save()
		assert passed, receipt['checks'][-1]
		return result.stdout

	target = dict(line.split('=', 1) for line in run([compiler, '--target-info'], dump=True).decode().splitlines() if '=' in line)
	receipt['target'] = target
	index = module('asan_index_build', ROOT / 'tests/file-indexer-15/build.py')
	challenge = module('asan_reconcile_build', ROOT / 'tests/reconciliation-15/build.py')
	corpus = module('asan_index_corpus', ROOT / 'tests/file-indexer-15/corpus.py')
	index_oracle = module('asan_index_oracle', ROOT / 'tests/file-indexer-15/oracle.py')
	challenge_oracle = module('oracle', ROOT / 'tests/reconciliation-15/oracle.py')
	challenge_inputs = module('asan_reconcile_inputs', ROOT / 'tests/reconciliation-15/inputs.py')
	manifest = corpus.generate(out / 'corpus', corpus.DEFAULT_SEED)
	for name, builder in [('indexer', index), ('reconcile', challenge)]:
		built = builder.build(compiler, args.build_output, ROOT / 'lib/astra', mode='mono',
			**({'levels': [1, 1, 1], 'async_profile': 'virtual'} if name == 'indexer' else {'levels': [1, 1]}))
		data = json.loads(built.read_text())
		receipt['builds'].append(dict(path=str(built), sha256=sha(built)))
		# The portable builder records the exact source list in its actual
		# monolithic compiler command. No producer source is reconstructed here.
		compile_step = next(c for c in data['checks'] if '--entry-object' in c['argv'])
		sources = [Path(arg) for arg in compile_step['argv'] if arg.endswith('.astra')]
		folder = out / name
		folder.mkdir()
		ssa = run([compiler, '--dump-ssa', *sources], dump=True).decode()
		entry = int(re.search(r'\(function #(\d+) "main" -> int', ssa)[1])
		text = run([compiler, '--dump-llvm', *sources], dump=True).decode()
		if not re.search(r'^target datalayout', text, re.M):
			text = 'target datalayout = \"' + target['data-layout'] + '\"\ntarget triple = \"' + target['target'] + '\"\n' + text
		assert re.search(r'define (?:internal )?fastcc i32 @astra\.fn\.' + str(entry) + r'\(ptr [^,]+, i32 ', text), 'startup requires exact existing text-slice ABI'
		assert 'astra_host_args_prepare_v0' not in text and 'astra_host_args_dispose_v0' not in text
		text = re.sub(r'^(define .*?)\s*\{\s*$', r'\1 sanitize_address {', text, flags=re.M)
		text += '''
declare i32 @astra_host_args_prepare_v0(i32, ptr, ptr)
declare void @astra_host_args_dispose_v0(ptr)
define i32 @main(i32 %argc, ptr %argv) sanitize_address {
entry:
  %slot = alloca ptr
  store ptr null, ptr %slot
  %status = call i32 @astra_host_args_prepare_v0(i32 %argc, ptr %argv, ptr %slot)
  %valid = icmp eq i32 %status, 0
  br i1 %valid, label %ready, label %failure
failure:
  ret i32 %status
ready:
  %items = load ptr, ptr %slot
  %result = call fastcc i32 @astra.fn.ENTRY(ptr %items, i32 %argc)
  call void @astra_host_args_dispose_v0(ptr %items)
  ret i32 %result
}
'''.replace('ENTRY', str(entry))
		raw, checked, obj, binary = [folder / part for part in ['source.ll', 'asan.ll', 'asan.o', name]]
		raw.write_text(text)
		run(['opt', '-passes=default<O1>,asan', '-S', raw, '-o', checked])
		assert '__asan_report_' in checked.read_text()
		run(['llc', '-O1', '-filetype=obj', '-relocation-model=pic', checked, '-o', obj])
		objects = [Path(p) for p in data['products'] if Path(p).suffix == '.o' and Path(p).name != name + '.o']
		run(['clang', '-fsanitize=address', '-fno-omit-frame-pointer', '-no-pie', obj, *objects, '-o', binary])
		if name == 'indexer':
			paths = ['input-02.astra', 'embedded-nul.astra', 'missing-input.astra', 'input-02.astra', 'input-63.astra']
			previous = Path.cwd()
			try:
				os.chdir(manifest.parent)
				expected = index_oracle.render(paths)
				partial = b''.join(index_oracle.render(paths[:1]).splitlines(keepends=True)[:-1])
			finally:
				os.chdir(previous)
			run([binary, '--policy=alternate', '--retry-sink', '--refresh', '--evict-last', *paths], cwd=manifest.parent, expected=expected)
			for flag, expected in [('cold', b''), ('suspended', b'astra-index\t1\n'), ('after-first', partial)]:
				run([binary, '--cancel-' + flag, *paths], cwd=manifest.parent, expected=expected)
		else:
			for scenario, arguments in challenge_inputs.scenarios():
				run([binary, *arguments], expected=challenge_oracle.render(arguments))
			run([binary, '2', '1', '2', '3', '4', '5', '6', '-1', '6'], code=2)
		for product in [raw, checked, obj, binary]:
			receipt['products'][str(product)] = sha(product)
	assert sha(compiler) == receipt['compiler_sha256']
	receipt['all_passed'] = True
	save()
	print(out / 'checks.json')


if __name__ == '__main__':
	main()
