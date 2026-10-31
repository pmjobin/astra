#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Cross-build previously qualified independent C matrices; never execute a VM.

The input is a Meson JSONL registry receipt from this checkout's authored M16
recipes. Source hashes and successful native assertions are required. Only
allowlisted compiler/build steps are replayed for the Windows target. This does
not qualify native Windows behavior: that requires separate guest receipts.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SKIP = {'schema', 'contracts', 'native-callables', 'callback-views'}


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler', type=Path, required=True)
	parser.add_argument('--native-registry', type=Path, required=True)
	parser.add_argument('--cc', type=Path, required=True)
	parser.add_argument('--cxx', type=Path, required=True)
	parser.add_argument('--sysroot', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--only', help='Comma-separated fixture stems; default all C Class channel matrices')
	args = parser.parse_args()
	compiler, output = args.compiler.resolve(), args.output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='windows-c-matrix-', dir=output))
	media = work/'media'; media.mkdir()
	receipt = dict(scope='declarations-v1 C Class Windows cross-build only; native Windows execution required',
		compiler_sha256=sha(compiler), recipe_sha256=sha(Path(__file__)),
		native_registry=dict(path=str(args.native_registry.resolve()), sha256=sha(args.native_registry)),
		checks=[], native_matrices={}, sources={}, products={}, execution_expectations={})
	def save():
		(work/'build.json').write_text(json.dumps(receipt, indent=2)+'\n')
	def run(command):
		assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during Windows matrix build'
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, cwd=work,
			timeout=120, env=dict(os.environ, CCACHE_DISABLE='1'))
		receipt['checks'].append(dict(command=list(map(str, command)), exit=p.returncode, stdout=p.stdout, stderr=p.stderr)); save()
		assert p.returncode == 0, receipt['checks'][-1]
		return p.stdout
	def source_identity(path):
		path = Path(path)
		if path.is_file() and path.suffix in {'.astra', '.c', '.h', '.cc', '.cpp'}:
			receipt['sources'][str(path)] = sha(path)
	tool_flags = ['--sysroot='+str(args.sysroot.resolve())]
	receipt['toolchain'] = run([args.cc, '--version'])
	objdump = run([args.cc, '-print-prog-name=objdump']).strip()
	selected = set(args.only.split(',')) if args.only else None
	for line in args.native_registry.read_text().splitlines():
		registration = json.loads(line)
		prefix = 'astra:declaration-interop-16-'
		if not registration['name'].startswith(prefix):
			continue
		stem = registration['name'].removeprefix(prefix)
		if stem in SKIP or selected is not None and stem not in selected:
			continue
		assert registration['result'] == 'OK' and not registration['is_fail']
		matrix_path = Path(json.loads(registration['stdout'])['receipt']).resolve()
		matrix = json.loads(matrix_path.read_text()); prior = matrix_path.parent
		assert matrix.get('status', '').endswith('PASS')
		assert all(check['exit'] == check.get('expected_exit',0) for check in matrix['checks'])
		for name, digest in matrix['sources'].items():
			path = ROOT/name; assert path.is_relative_to(ROOT) and sha(path) == digest, name
			source_identity(path)
		receipt['native_matrices'][stem] = dict(path=str(matrix_path), sha256=sha(matrix_path), compiler_sha256=matrix['compiler_sha256'])
		case = work/stem; case.mkdir()
		for path in prior.rglob('*'):
			if path.is_file() and path.suffix in {'.astra','.c','.h','.cc','.cpp'}:
				target = case/path.relative_to(prior); target.parent.mkdir(parents=True, exist_ok=True)
				shutil.copyfile(path,target); source_identity(path)
		def remap(value):
			return str(case)+value[len(str(prior)):] if value.startswith(str(prior)) else value
		binaries = {}
		for check in matrix['checks']:
			command = check['command']
			if check.get('expected_exit',0) != 0:
				continue
			if command[0] == str(compiler):
				if '-c' in command:
					mapped = [str(compiler),'--target=x86_64-w64-windows-gnu',*[remap(x) for x in command[1:]]]
					for item in command[1:]:source_identity(item)
					run(mapped)
				elif '--emit-class-header' in command or '--emit-class-source' in command:
					generated = run([str(compiler),'--target=x86_64-w64-windows-gnu',*[remap(x) for x in command[1:]]])
					assert generated == check['stdout'], 'target header/source changed; independently validate before replay'
				continue
			if command[0] in {'cc','c++','clang++'}:
				mapped = [str(args.cc if command[0]=='cc' else args.cxx),*tool_flags,*[remap(x) for x in command[1:]]]
				for item in command[1:]:source_identity(item)
				if '-o' in command and '-c' not in command:
					old_binary=command[command.index('-o')+1]
					binary=Path(remap(old_binary)+'.exe');mapped[mapped.index('-o')+1]=str(binary)
					mapped[1:1]=['-static','-Wl,--no-insert-timestamp']
					binaries[old_binary]=binary
				run(mapped);continue
			if command[0] in binaries:
				binary=binaries.pop(command[0]);name=stem+'-'+binary.relative_to(case).as_posix().replace('/','-')
				assert re.fullmatch(r'[A-Za-z0-9_.-]+',name) and len(name)<100
				assert 'PASS' in check['stdout'] and check['exit']==0
				imports=run([objdump,'-p',binary]);deps=[x.split(':',1)[1].strip().lower() for x in imports.splitlines() if 'DLL Name:' in x]
				assert deps and set(deps)<={'kernel32.dll','msvcrt.dll'},deps
				shutil.copyfile(binary,media/name);receipt['products'][name]=sha(media/name)
				receipt['execution_expectations'][name]=dict(pass_markers=[x for x in check['stdout'].splitlines() if x.startswith('PASS')], system_dlls=deps)
		assert not binaries, 'a foreign binary lacks an executed native oracle'
		save();print(stem, 'cross-build complete', flush=True)
	if selected is not None:assert set(receipt['native_matrices'])==selected
	assert receipt['products']
	receipt['status']='CROSS_BUILD_PASS; native Windows execution pending';save()
	print(json.dumps(dict(status=receipt['status'], products=len(receipt['products']), receipt=str(work/'build.json'))))


if __name__=='__main__':
	main()
