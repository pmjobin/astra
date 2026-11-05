#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Expose the existing effect deferral without weakening its call contract."""
import argparse
import json
import os
import signal
import subprocess
import time
from state import RUNTIME, BUILD, C0, read, sha

CASES = {
	'throwing': '[ExceptionRoot]class Error { readonly string text; init(string message) { this.text=message; } virtual property string message { get { return this.text; } } }\nint candidate() throws Error { return 7; }\nint main() { return 0; }\n',
	'pure': 'int candidate() { return 7; }\nint main() { return candidate(); }\n',
}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version',default='v2'); a = p.parse_args(); assert a.version.replace('-','').isalnum()
	leaf = RUNTIME/('effect-boundary-'+a.version); leaf.mkdir(exist_ok=False); commands = []
	component = read(RUNTIME/'initial.json')['products']['O0']['path']
	for name,source in CASES.items():
		path = leaf/(name+'.astra'); path.write_text(source)
		for label,argv in [('parse',[C0,'--dump-syntax',path]),('C0',[C0,'--check',path]),('native',[component,'--classstorage-admit','O0',BUILD/'unused',path])]:
			start = time.monotonic()
			process = subprocess.Popen(['/usr/bin/time','-v','-o',str(leaf/(name+'-'+label+'.time')),*map(str,argv)],cwd=BUILD,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
			try: out,err = process.communicate(timeout=120)
			except subprocess.TimeoutExpired:
				os.killpg(process.pid,signal.SIGTERM); out,err = process.communicate(); raise
			(leaf/(name+'-'+label+'.stdout')).write_bytes(out); (leaf/(name+'-'+label+'.stderr')).write_bytes(err)
			commands.append(dict(name=name+'-'+label,argv=list(map(str,argv)),exit=process.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'-'+label+'.stdout')),stderr_sha256=sha(leaf/(name+'-'+label+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
			assert process.returncode == (3 if name == 'throwing' and label == 'native' else 0)
			if name == 'throwing' and label == 'native':
				start_byte = source.index('int candidate()'); end_byte = source.index('\nint main()')
				deferred = [line.split() for line in out.decode().splitlines() if line.startswith('DEFER UNSUPPORTED_EFFECT 6 ')]
				assert any(row[-2:] == [str(start_byte),str(end_byte)] for row in deferred)
			print(name,label,process.returncode,flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='EXISTING_EFFECT_BOUNDARY_CONFIRMED',component_sha256=sha(component),commands=commands,recipe_sha256=sha(__file__),limitation='The throwing source also has exception-root Class/member deferrals. The separate UNSUPPORTED_EFFECT refusal is bound to the candidate function span; its body is identical to the pure twin. This is a contract probe, not execution of the original caller functions.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
