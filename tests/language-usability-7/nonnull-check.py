# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public nonnull admission, retained nullable controls and reference liveness."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PRELUDE = 'class C {int value;init(){this.value=7;}} int use(nonnull C p){return p.value;} '


def main(compiler_path, emitter_path, output_path):
	compiler, emitter, output = [Path(p).resolve() for p in [compiler_path, emitter_path, output_path]]
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='nonnull-', dir=output))
	sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
	rows = []
	receipt = dict(compiler_sha256=sha(compiler), emitter_sha256=sha(emitter), checks=rows, products={}, sources={})
	def run(command, code=0, needle=None, memory=False, stdout=b''):
		command = list(map(str, command))
		p = subprocess.run(command, capture_output=True, cwd=out, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		ok = p.returncode == code and (stdout is None or p.stdout == stdout)
		if needle is not None: ok &= needle.encode() in p.stderr
		elif memory: ok &= all(x in p.stderr for x in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else: ok &= not p.stderr
		rows.append(dict(command=command, exit=p.returncode, stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace'), passed=bool(ok)))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert ok, rows[-1]
		return p.stdout
	positive = {
		'suspension-owner': PRELUDE+'async void work() throws AsyncError {owned nonnull C p=new C();await delay_ticks(1);use(p);}',
		'interface-contract': 'interface I {int invoke(int p);} int f(borrowed nonnull I p){return p(7);}',
		'nullable-default': 'class C {int value;} int f(C p){C q=null;return p.value;} ',
		'guard': PRELUDE+'int f(C p){if(p==null){return 0;}nonnull C q=p;return use(q);}',
		'short-and': PRELUDE+'int f(C p){if(p!=null && use(p)==7){return use(p);}return 0;}',
		'short-or': PRELUDE+'int f(C p){if(p==null || false){return 0;}return use(p);}',
		'loop': PRELUDE+'int f(C p){while(p!=null){return use(p);}return 0;}',
		'branch-join': PRELUDE+'int f(C p,bool b){C q=null;if(b){q=p;}else{q=p;}if(q==null){return 0;}return use(q);}',
	}
	negative = {
		'null-argument': (PRELUDE+'int f(){return use(null);}', 'current non-null proof'),
		'unknown-argument': (PRELUDE+'int f(C p){return use(p);}', 'current non-null proof'),
		'null-local': (PRELUDE+'int f(){nonnull C p=null;return 0;}', 'current non-null proof'),
		'null-assignment': (PRELUDE+'int f(nonnull C p){nonnull C q=p;q=null;return 0;}', 'current non-null proof'),
		'branch-join': (PRELUDE+'int f(C p){if(p!=null){use(p);}return use(p);}', 'current non-null proof'),
		'stale-boolean': (PRELUDE+'int f(C p){C q=p;bool prior=q!=null;q=null;if(prior){return use(q);}return 0;}', 'current non-null proof'),
		'backedge': (PRELUDE+'int f(C p){if(p==null){return 0;}C q=p;while(true){use(q);q=null;}return 0;}', 'current non-null proof'),
		'nullable-result': (PRELUDE+'owned nonnull C f(){return null;}', 'current non-null proof'),
		'scalar': ('int f(nonnull int p){return p;}', 'exact concrete Class or Resource'),
		'raw-pointer': ('int f(nonnull void* p){return 0;}', 'exact concrete Class or Resource'),
		'weak': (PRELUDE+'int f(owned nonnull Weak<C> p){return 0;}', 'exact concrete Class or Resource'),
		'shared': (PRELUDE+'int f(owned nonnull Shared<C> p){return 0;}', 'exact concrete Class or Resource'),
		'interface-null': ('interface I {int invoke(int p);} int use(borrowed nonnull I p){return p(7);} int f(borrowed I p){return use(p);}', 'current non-null proof'),
		'expired-upgrade': (PRELUDE+'int f(){var unique=new C();var shared=shared_acquire(move unique);var observer=shared_downgrade(shared);release shared;owned nonnull Shared<C> expired=weak_upgrade(observer);return 0;}', 'exact concrete Class or Resource'),
		'exception-path': (PRELUDE+'int f(C p){try{if(p==null){throw new Error("missing input");}}catch(Error failure){return use(p);}return 0;}', 'current non-null proof'),
		'override': (PRELUDE+'class B {virtual int f(C p){return p.value;}}class D:B {override int f(nonnull C p){return p.value;}}', 'direct native'),
		'mutated-field': (PRELUDE+'class Box {owned C child;init(owned C p){this.child=move p;}property borrowed C item {get{return this.child;}}void replace(owned C p){this.child=move p;}}int f(Box box,owned C p){if(box.item!=null){box.replace(move p);return use(box.item);}return 0;}', 'current non-null proof'),
		'virtual': (PRELUDE+'class B {virtual int f(nonnull C p){return p.value;}}', 'direct native'),
		'moved': (PRELUDE+'int f(){var p=new C();owned nonnull C q=move p;return use(p);}', 'moved'),
		'field-definite': (PRELUDE+'class Box {owned nonnull C child;init(){}}', 'not definitely initialized'),
		'field-null': (PRELUDE+'class Box {owned nonnull C child;init(){this.child=null;}}', 'owned child field transfer requires'),
		'field-unproven': (PRELUDE+'class Box {owned nonnull C child;init(owned C p){this.child=move p;}}', 'current non-null proof'),
		'borrow-result': (PRELUDE+'class Box {owned C child;init(owned C p){this.child=move p;}property borrowed nonnull C item {get{return this.child;}}}', 'current non-null proof'),
		'escape-borrow': (PRELUDE+'class Box {owned nonnull C child;init(owned nonnull C p){this.child=move p;}property borrowed nonnull C item {get{return this.child;}}} owned C f(Box p){return p.item;}', 'cannot transfer ownership'),
		'foreign-unknown': ('owned nonnull R f(){owned R value=acquire(7);return move value;}', 'current non-null proof'),
	}
	for name, source in positive.items():
		path = out/(name+'-positive.astra'); path.write_text(source+'\n')
		extra = [ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/async/virtual.astra'] if name == 'suspension-owner' else []
		run([compiler, '--check', path, *extra])
		run([compiler, '--dump-ssa', path, *extra], stdout=None)
	for name, (source, needle) in negative.items():
		path = out/(name+'-negative.astra'); path.write_text(source+'\n')
		extra = ['--vapi', HERE/'nonnull-resource.vapi'] if name == 'foreign-unknown' else [ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/async/virtual.astra'] if name == 'suspension' else [ROOT/'lib/astra/base/errors.astra'] if name == 'exception-path' else []
		run([compiler, '--check', path, *extra], code=1, needle=needle)
	qualified = HERE/'nonnull-control.astra'; plain = out/'nullable-peer.astra'; plain.write_text(qualified.read_text().replace('nonnull ', ''))
	for mode in ['--dump-nabi', '--dump-cabi', '--dump-llvm']:
		first = run([compiler, mode, qualified], stdout=None)
		second = run([compiler, mode, plain], stdout=None)
		assert first == second, mode+' changed the existing ABI or emitted runtime code'
	provider = out/'nonnull-resource.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'nonnull-resource.c', '-o', provider])
	for name in ['nonnull-control', 'nonnull-resource']:
		source = HERE/(name+'.astra'); receipt['sources'][name] = sha(source)
		extra = ['--vapi', HERE/'nonnull-resource.vapi', ROOT/'lib/astra/base/errors.astra', '--link-object', provider] if name == 'nonnull-resource' else []
		for opt in ['-O0', '-O1', '-O2']:
			exe = out/(name+opt)
			run([compiler, opt, source, *extra, '-o', exe]); receipt['products'][exe.name] = sha(exe)
			run([exe])
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', exe], memory=True)
	asan_provider = out/'nonnull-resource-provider-asan.o'
	run(['clang', '-std=c11', '-g', '-O1', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-c', HERE/'nonnull-resource.c', '-o', asan_provider])
	for name in ['nonnull-control', 'nonnull-resource']:
		raw, marked, instrumented, obj, exe = [out/(name+suffix) for suffix in ['-raw.ll', '-marked.ll', '-asan.ll', '-asan.o', '-asan']]
		inputs = [HERE/(name+'.astra')]
		if name == 'nonnull-resource': inputs += ['--vapi', HERE/'nonnull-resource.vapi', ROOT/'lib/astra/base/errors.astra']
		run([emitter, '--emit', raw, *inputs])
		text, count = re.subn(r'^(define [^\n]+)\{$', r'\1sanitize_address {', raw.read_text(), flags=re.M)
		assert count > 0; marked.write_text(text)
		run(['opt', '-passes=verify', '-disable-output', marked])
		run(['opt', '-passes=default<O2>,asan', '-S', marked, '-o', instrumented])
		assert '__asan_report_' in instrumented.read_text()
		run(['opt', '-passes=verify', '-disable-output', instrumented])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', instrumented, '-o', obj])
		run(['clang', '-fsanitize=address,undefined', obj, *([asan_provider] if name == 'nonnull-resource' else []), '-o', exe])
		run([exe]); receipt['products'][exe.name] = sha(exe)
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'{len(rows)} public nonnull checks; native ASan and provider ASan/UBSan; receipts: {out}')


if __name__ == '__main__': main(*sys.argv[1:])
