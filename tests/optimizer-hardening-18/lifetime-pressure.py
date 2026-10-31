#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Valid graph width/depth probes under explicit per-process resource limits."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import resource
import subprocess
import tempfile
import time


def main():
	parser=argparse.ArgumentParser(description=__doc__)
	parser.add_argument('probe',type=Path)
	parser.add_argument('runtime',type=Path)
	args=parser.parse_args()
	probe=args.probe.resolve(strict=True)
	runtime=args.runtime.resolve()
	assert not runtime.is_relative_to(Path(__file__).resolve().parents[2])
	runtime.mkdir(parents=True,exist_ok=True)
	work=Path(tempfile.mkdtemp(prefix='pressure-',dir=runtime))
	result={'probe_sha256':hashlib.sha256(probe.read_bytes()).hexdigest(),
		'limits':{'address_space_bytes':512*1024**2,'cpu_seconds':20,'wall_seconds':25},
		'cpu_count':os.cpu_count(),'load_at_start':os.getloadavg(),'checks':[]}
	def limits():
		resource.setrlimit(resource.RLIMIT_AS,(512*1024**2,512*1024**2))
		resource.setrlimit(resource.RLIMIT_CPU,(20,20))
		resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	for mode,count in [('wide',4096),('wide',16384),('wide',65536),('deep',256),('deep',8192),('deep',32767)]:
		command=[str(probe),mode,str(count)]
		timing=work/f'{mode}-{count}.time'
		start=time.monotonic()
		p=subprocess.run(['/usr/bin/time','-v','-o',str(timing),*command],capture_output=True,text=True,timeout=25,preexec_fn=limits)
		row={'command':command,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'seconds':time.monotonic()-start,'resources':timing.read_text()}
		result['checks'].append(row)
		(work/'checks.json').write_text(json.dumps(result,indent=2)+'\n')
		assert p.returncode==0 and not p.stderr,row
	print(work/'checks.json')


if __name__=='__main__': main()
