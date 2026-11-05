#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe allocation identities and scope/field retirement for the real method."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import xml.etree.ElementTree as ET
from state import ROOT, RUNTIME, BUILD, C0, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--qualification',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); a = p.parse_args()
	leaf = RUNTIME/('lifetime-v1-'+a.mode); build = BUILD/leaf.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	commands = []; rows = []; env = dict(os.environ,CCACHE_DISABLE='1'); env.pop('VALGRIND_OPTS',None); env.pop('LD_PRELOAD',None)
	def run(argv,name,expected=0):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=build,capture_output=True,env=env,timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); assert r.returncode == expected,(name,r.stderr.decode()); return r
	observer = build/'observer.o'; source = ROOT/'tests/selfhost-ownexchange/observer.c'
	run(['gcc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',source,'-o',observer],'observer')
	expected = {
		'original-add-signature': 'A 1 40\nA 2 320\nA 3 320\nA 4 640\nF 2 320\nA 5 1280\nF 4 640\nA 6 2560\nF 5 1280\nF 3 320\nF 6 2560\nF 1 40\n',
		'nested-field-local': 'A 1 32\nA 2 72\nA 3 168\nA 4 264\nF 2 72\nF 3 168\nF 4 264\nF 1 32\n',
	}
	for row in read(a.qualification/'results.json'):
		if row['name'] not in expected: continue
		assert row['baseline_complete']; name = row['name']; code = 53 if name == 'original-add-signature' else 42
		c0 = build/(name+'-C0.o'); run([C0,'-'+a.mode,'--entry-object',*[s['path'] for s in row['sources']],'-o',c0],name+'-C0-object')
		for role,obj in [('native',Path(row['products']['object']['path'])),('C0',c0)]:
			elf = build/(name+'-'+role); run(['gcc',obj,observer,'-Wl,--wrap=calloc','-Wl,--wrap=free','-o',elf],name+'-'+role+'-link')
			r = run([elf],name+'-'+role+'-execute',code); assert r.stdout == b'' and r.stderr.decode() == expected[name]
			xml = leaf/(name+'-'+role+'.xml'); r = run(['valgrind','--command-line-only=yes','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all','--xml=yes','--xml-file='+str(xml),elf],name+'-'+role+'-memory',code)
			assert r.stderr.decode() == expected[name] and ET.parse(xml).getroot().find('error') is None
			rows.append(dict(name=name,role=role,source_identity=row['sources'],object_sha256=sha(obj),ELF_sha256=sha(elf),expected_and_observed_trace=expected[name],memory_errors=0,xml_sha256=sha(xml)))
		print(a.mode,name,'exact allocation identity and cleanup order',flush=True)
	assert len(rows) == 4
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,observations=rows,commands=commands,observer_sha256=sha(source),recipe_sha256=sha(__file__),limitation='Observer wraps allocation/free only; it implements no Astra operation. Normal returns only. Fatal traps do not imply unwinding.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
