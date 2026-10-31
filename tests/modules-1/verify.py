# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""MODULE-1A independent scopes, ownership, diagnostic order and C-link witness."""
import itertools
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent

def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	records = []
	def run(args, expected=0, message=None):
		command = [str(compiler), *map(str, args)]
		p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60)
		records.append(dict(command=command, status=p.returncode, stdout=p.stdout, stderr=p.stderr))
		(output/'checks.json').write_text(json.dumps(records, indent=2)+'\n')
		assert p.returncode == expected, records[-1]
		if message: assert message in p.stderr, records[-1]
		return p
		# Qualified-name lookahead must retain tokens even when the source is a
		# legacy this.field assignment rather than a qualified local declaration.
	probe=output/'legacy-field-probe.astra'
	probe.write_text('class ByteBox{private owned u8[] bytes;init(){this.bytes=new u8[2];this.bytes[1]=42;}int read(){return this.bytes[1] as int;}}int main(){var box=new ByteBox();return box.read()-42;}'+'\n')
	assert '(private-field "bytes"' in run(['--dump-syntax', probe]).stdout
	for opt in ['-O0', '-O2']:
		binary=output/('field-probe'+opt);run([opt, probe, '-o', binary]);assert subprocess.run([binary]).returncode == 0
	header=output/'namespace-header.astra';header.write_text('namespace Empty;using Left;'+'\n')
	parsed=run(['--dump-syntax', header]).stdout
	assert '(namespace Empty)' in parsed and '(using Left)' in parsed
	files = [HERE/'left.astra', HERE/'right.astra', HERE/'main.astra']
	reference = None
	for order in itertools.permutations(files):
		p = run(['--dump-semantics', *order])
		if reference is None: reference = p.stdout
		assert p.stdout == reference
		for opt in ['-O0', '-O2']:
			binary = output/('positive'+opt)
			run([opt, *order, '-o', binary])
			assert subprocess.run([binary]).returncode == 0
	cases = {
		'ambiguous': ('using Left; using Right; int main(){var value=new Record(1);return 0;}', 'ambiguous imported name'),
		'missing': ('using Missing; int main(){return 0;}', 'unknown imported namespace'),
		'internal-qualified': ('int main(){var value=new Left.Payload(1);return Left.inspect(value);}', 'internal declaration'),
		'internal-imported': ('using Left; int main(){var value=new Payload(1);return inspect(value);}', 'unknown function'),
		'private-field': ('int main(){var value=new Left.Record(1);return value.child;}', 'private'),
		'moved': ('int main(){var value=new Left.Record(1);Left.consume(move value);return Left.measure(value);}', 'moved'),
		'duplicate': ('namespace Left; class Record{}', 'duplicate class type'),
		'unknown-qualified': ('int main(){var value=new Absent.Record(1);return 0;}', 'unknown type'),
		'same-namespace-private': ('namespace Left;class Outsider{init(){}int read(Record value){return value.child;}}', 'private field'),
	}
	for label, (source, diagnostic) in cases.items():
		path = output/(label+'.astra'); path.write_text(source+'\n')
		for stage in ['--check', '--dump-llvm']:
			first = None
			for order in [(files[0], files[1], path), (path, files[1], files[0])]:
				p = run([stage, *order], expected=1, message=diagnostic)
				assert not p.stdout
				if first is None: first = p.stderr
				assert p.stderr == first
	shadow=output/'shadow-receiver.astra'
	shadow.write_text('using Left;using Right;int main(){var Record=new Left.Record(42);return Record.read()-42;}'+'\n')
	for opt in ['-O0', '-O2']:
		binary=output/('shadow'+opt);run([opt, files[0], files[1], shadow, '-o', binary]);assert subprocess.run([binary]).returncode == 0
	hidden=output/'hidden.astra';hidden_user=output/'hidden-user.astra'
	hidden.write_text('namespace HiddenSpace;internal class Hidden{init(){}}'+'\n')
	hidden_user.write_text('int main(){var value=new HiddenSpace.Hidden();return 0;}'+'\n')
	run(['--check', hidden, hidden_user], expected=1, message='internal declaration')
	physical_a=output/'physical-a.astra';physical_b=output/'physical-b.astra'
	physical_a.write_text('namespace ForeignA;[CCode(cname="same_physical_symbol")]extern(C) int alias_a();'+'\n')
	physical_b.write_text('namespace ForeignB;[CCode(cname="same_physical_symbol")]extern(C) int alias_b();'+'\n')
	run(['--dump-llvm', physical_a, physical_b], expected=1, message='declared more than once')
	# Same-named generic definitions keep separate canonical definition identities.
	generic_files=[HERE/'generic-left.astra', HERE/'generic-right.astra', HERE/'generic-main.astra']
	assert run(['--dump-core', *generic_files]).stdout == run(['--dump-core', *reversed(generic_files)]).stdout
	for opt in ['-O0', '-O2']:
		binary=output/('generic'+opt);run([opt, *reversed(generic_files), '-o', binary]);assert subprocess.run([binary]).returncode == 0
	wrong=output/'wrong-generic.astra'
	wrong.write_text('int main(){GenericLeft.Box<int> value={value=1};return GenericRight.read(value);}'+'\n')
	run(['--check', generic_files[0], generic_files[1], wrong], expected=1, message='exact')
	bag_files=[HERE/'generic-bag.astra', HERE/'generic-bag-main.astra']
	for opt in ['-O0', '-O2']:
		binary=output/('generic-bag'+opt);run([opt, *reversed(bag_files), '-o', binary]);assert subprocess.run([binary]).returncode == 0
	qualified_files=[HERE/'qualified-type-parameter.astra', HERE/'qualified-generic.astra', HERE/'qualified-generic-main.astra']
	for opt in ['-O0', '-O2']:
		binary=output/('qualified-generic'+opt);run([opt, *reversed(qualified_files), '-o', binary]);assert subprocess.run([binary]).returncode == 0
		# Imports are lexical and may cycle; all source dependencies are explicit.
	cycle_a=output/'cycle-a.astra'; cycle_b=output/'cycle-b.astra'; cycle_main=output/'cycle-main.astra'
	cycle_a.write_text('namespace A; using B; int first(){return second();}\n')
	cycle_b.write_text('namespace B; using A; int second(){return 42;}\n')
	cycle_main.write_text('int main(){return A.first()-42;}\n')
	binary=output/'cycle'; run(['-O2', cycle_b, cycle_main, cycle_a, '-o', binary])
	assert subprocess.run([binary]).returncode == 0
	constants_a=output/'constants-a.astra';constants_b=output/'constants-b.astra'
	constants_a.write_text('namespace ConstA;using ConstB;const int one=two;'+'\n')
	constants_b.write_text('namespace ConstB;using ConstA;const int two=one;'+'\n')
	run(['--check', constants_b, constants_a], expected=1, message='constant dependency cycle')
	sibling=output/'same-namespace-sibling.astra';sibling_main=output/'same-namespace-main.astra'
	sibling.write_text('namespace Left;int cross_file(Payload value){return inspect(value);}'+'\n')
	sibling_main.write_text('int main(){var value=new Left.Payload(42);return Left.cross_file(value)-42;}'+'\n')
	for opt in ['-O0', '-O2']:
		binary=output/('sibling'+opt);run([opt, sibling, files[0], sibling_main, '-o', binary]);assert subprocess.run([binary]).returncode == 0
		# Legacy global source still has exactly the previous whole-program scope.
	legacy_a=output/'legacy-a.astra'; legacy_b=output/'legacy-b.astra'
	legacy_a.write_text('int helper(){return 42;}\n'); legacy_b.write_text('int main(){return helper()-42;}\n')
	binary=output/'legacy';run(['-O2', legacy_b, legacy_a, '-o', binary]);assert subprocess.run([binary]).returncode == 0
	obj=output/'modules.o'; run(['-O2', '-c', files[1], files[0], '-o', obj])
	binary=output/'client'; subprocess.run(['cc', str(HERE/'client.c'), str(obj), '-o', str(binary)], check=True)
	p=subprocess.run([binary], capture_output=True, text=True);assert p.returncode == 0 and p.stdout == 'namespace C exports: 42 42\n'
	(output/'result.json').write_text(json.dumps(dict(compiler_commands=len(records), passed=True), indent=2)+'\n')
	print(f'{len(records)} MODULE-1A compiler checks; O0/O2 permutations and independent C client passed')

if __name__ == '__main__': main(*sys.argv[1:])
