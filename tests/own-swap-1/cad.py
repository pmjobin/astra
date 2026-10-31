# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual accepted Context, exact I0/I1 rotation and independent record snapshots."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'workloads/cad'))
from qualify_owner_exchange import OLD, NEW, I0_SHA256


def qualify(compiler, out):
	out.mkdir(parents=True, exist_ok=False)
	source = ROOT / 'workloads/cad/idiomatic'; algorithm = (source / 'src/algorithm.astra').read_text()
	assert hashlib.sha256(algorithm.encode()).hexdigest() == I0_SHA256 and algorithm.count(OLD) == 1
	context = algorithm[algorithm.index('struct Kernel {'):algorithm.index('Kernel load_kernel(')]
	context += '\nvoid rotation0(Context c){int k=0;\n' + OLD + '\n}\nvoid rotation1(Context c){\n' + NEW + '\n}\n'
	(out / 'context.astra').write_text(context)
	check = '''extern(C) int cad_same_bits(f64 a,f64 b);
extern(C) f64 cad_nextafter(f64 a,f64 b);
int main(){var a=Context.init(3,1,3,1);var b=Context.init(3,1,3,1);var i=0;
	while(i<3){a.state[i].mx=-0.0;a.state[i].sigma=cad_nextafter(1.0,2.0);a.next[i].my=cad_number(i);a.next[i].sigma=7.0;b.state[i]=a.state[i];b.next[i]=a.next[i];i=i+1;}
	var saved=a.state[0];var iteration=0;while(iteration<5){rotation1(a);rotation0(b);i=0;
		while(i<3){require(cad_same_bits(a.state[i].mx,b.state[i].mx)!=0&&cad_same_bits(a.next[i].mx,b.next[i].mx)!=0&&cad_same_bits(a.state[i].sigma,b.state[i].sigma)!=0&&cad_same_bits(a.next[i].sigma,b.next[i].sigma)!=0,401,cad_number(i));i=i+1;}
		iteration=iteration+1;
	}require(cad_same_bits(saved.mx,-0.0)!=0&&cad_same_bits(saved.sigma,cad_nextafter(1.0,2.0))!=0,402,saved.sigma);return 0;}
'''
	(out / 'rotation.astra').write_text(check)
	commands = [['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT / 'workloads/cad/reference/math.c', '-o', out / 'math.o'], [compiler, source / 'src/numeric.astra', out / 'context.astra', out / 'rotation.astra', '--link-object', out / 'math.o', '--link-library', 'm', '-o', out / 'rotation'], [out / 'rotation']]
	rows = []
	for command in commands:
		p = subprocess.run(list(map(str, command)), capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1', TMPDIR=str(out)))
		rows.append(dict(argv=list(map(str, command)), status=p.returncode, stdout=p.stdout.decode(), stderr=p.stderr.decode()))
		(out / 'commands.json').write_text(json.dumps(rows, indent='\t') + '\n'); assert p.returncode == 0 and not p.stdout and not p.stderr, rows[-1]
	print('Actual Context: five I1/I0 rotations, signed-zero and sigma bits, saved record and normal cleanup')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
