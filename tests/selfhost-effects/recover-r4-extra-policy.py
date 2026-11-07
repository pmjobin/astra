#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""C0 authority for Class-field producers, independent of native admission."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_extra_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-extra-policy-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	prefix = 'class Item { init() {} } owned Item make() { var value = new Item(); return move value; }\n'
	programs = {
		'Class-field-call-result': prefix+'class Box { private owned Item item; init(owned Item item) { this.item = move item; } void replace() { this.item = make(); } } int main() { var item = new Item(); var value = new Box(move item); value.replace(); return 42; }\n',
		'Class-field-direct-new': prefix+'class Box { private owned Item item; init(owned Item item) { this.item = move item; } void replace() { this.item = new Item(); } } int main() { var item = new Item(); var value = new Box(move item); value.replace(); return 42; }\n',
		'Class-constructor-direct-new': prefix+'class Box { private owned Item item; init() { this.item = new Item(); } } int main() { var value = new Box(); return 42; }\n',
		'buffer-field-call-result': 'owned int[] make() { var value = new int[42]; return move value; } class Box { private owned int[] data; init() { this.data = new int[1]; } void replace() { this.data = make(); } int count() { return len(this.data); } } int main() { var value = new Box(); value.replace(); return value.count(); }\n',
		'Class-field-null-replacement': prefix+'class Box { private owned Item item; init(owned Item item) { this.item = move item; } void replace() { this.item = null; } } int main() { var item = new Item(); var value = new Box(move item); value.replace(); return 42; }\n',
		'private-field-access': 'class Box { private int value; init() { this.value = 42; } } int main() { var value = new Box(); return value.value; }\n',
		'private-snapshot-public-property': 'class Label { private readonly string snapshot; init(string input) { this.snapshot = input; } property string text { get { return this.snapshot; } } } int main() { var value = new Label("kept"); if (value.text == "kept") return 42; return 3; }\n',
		'discard-string': 'string ignored() { return "kept"; } int main() { ignored(); return 42; }\n',
	}
	for name, text in programs.items():
		source = leaf/(name+'.astra'); source.write_text(text); exe = build/name
		def run(argv, label):
			argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'-'+label+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=120); (leaf/(name+'-'+label+'.stdout')).write_bytes(r.stdout); (leaf/(name+'-'+label+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name+'-'+label, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'-'+label+'.stdout')), stderr_sha256=sha(leaf/(name+'-'+label+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
		r = run([C0, '-'+a.mode, source, '-o', exe], 'build'); assert r.returncode in (0, 1); row = dict(name=name, source_sha256=sha(source), C0_legal=r.returncode == 0)
		if r.returncode == 0:
			assert run([exe], 'execute').returncode == 42; memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], 'memory'); assert memory.returncode == 42 and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr; row['C0_ELF_sha256'] = sha(exe)
		rows.append(row); (leaf/'result.json').write_text(json.dumps(dict(status='C0_FIELD_PRODUCER_POLICY', profile=a.mode, programs=rows, Astra_native_credit=0), indent=2)+'\n'); print(name, row['C0_legal'], flush=True)


if __name__ == '__main__':
	main()
