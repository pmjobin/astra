#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Same-key reuse and genuine 257th-distinct request under unchanged ceilings."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args()
	leaf = RUNTIME/('resources-'+a.version+'-'+a.mode); directory = BUILD/leaf.name; leaf.mkdir(exist_ok=False); directory.mkdir(exist_ok=False); commands = []; results = {}
	declarations = 'T retain<T>(T input) { T local = input; return local; }\n'
	for label, distinct in [('reuse', False), ('distinct-257', True)]:
		count = 257 if distinct else 512
		prefix = declarations+''.join('struct Tag'+str(n)+' { int value; }\n' for n in range(count if distinct else 1))
		# Keep each function below the unchanged Flow slot/event ceilings. The
		# number of independent generic requests and exact keys is unchanged.
		body = ''; batches = (count+63)//64
		for batch in range(batches):
			body += 'int batch'+str(batch)+'() {\n'
			for n in range(batch*64, min(count, (batch+1)*64)):
				tag = 'Tag'+str(n if distinct else 0); body += f'\t{tag} input{n} = {{value = {n}}}; var result{n} = retain<{tag}>(input{n}); if (result{n}.value != {n}) return 99;\n'
			body += '\treturn 0;\n}\n'
		body += 'int main() {\n'+''.join('\tif (batch'+str(n)+'() != 0) return 99;\n' for n in range(batches))+'\treturn 0;\n}\n'
		path = leaf/(label+'.astra'); path.write_text(prefix+body)
		for stage, argv in [('C0', [C0, '--check', path]), ('admit', [a.component, '--classstorage-admit', a.mode, directory/'unused', path]), ('data', [a.component, '--classstorage-genref-data', a.mode, directory/'unused', path])]:
			name = label+'-'+stage; start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *map(str, argv)], cwd=directory, capture_output=True, timeout=240)
			(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
			assert r.returncode == (1 if distinct and stage == 'admit' else 0), (name, r.returncode, r.stderr.decode()[-1000:])
			if distinct and stage == 'admit': assert b'67656e6572696320696e7374616e6365207265736f75726365206c696d6974' in r.stdout
			if stage == 'data':
				universe = next(line.split()[1:] for line in r.stdout.decode().splitlines() if line.startswith('UNIVERSE ')); assert int(universe[4]) == (256 if distinct else 1)
				results[label] = dict(source_sha256=sha(path), requests=count, distinct=distinct, retained_instances=int(universe[4]), universe=universe)
		if distinct:
			dest = directory/'preserved.o'; dest.write_bytes(b'preserved resource refusal destination\n'); before = sha(dest); argv = [a.component, '--classstorage-emit-obj', a.mode, dest, path]
			start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/'writer.time', *map(str, argv)], cwd=directory, capture_output=True, timeout=240)
			(leaf/'writer.stdout').write_bytes(r.stdout); (leaf/'writer.stderr').write_bytes(r.stderr); assert r.returncode == 2 and sha(dest) == before
			commands.append(dict(name='writer', argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); results[label]['preserved_destination_sha256'] = before
		print(a.mode, label, results[label]['retained_instances'], flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), results=results, commands=commands, unchanged_limits=dict(instances=256, SSA_steps=8000000), limitation='Source-stage reuse/resource witnesses. The intentionally refused 257-request program is not counted as an executed native application.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
