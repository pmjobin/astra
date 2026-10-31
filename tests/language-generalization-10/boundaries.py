# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Selected ASan/UBSan C boundaries; generated Astra LLVM is not instrumented."""
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests/systems-dsp-9'))
from support import Evidence


def main(compiler,output):
	output=Path(output).resolve();output.mkdir(parents=True,exist_ok=True)
	e=Evidence(compiler,tempfile.mkdtemp(prefix='boundaries-',dir=output),'boundaries')
	apps=ROOT/'examples/language-generalization-10'
	libraries=[ROOT/'lib/astra'/name for name in ['base/errors.astra','collections/bag.astra','collections/vector.astra',
		'text/utf8-message.astra','text/utf8-byte-builder.astra','hosted/text.astra','hosted/text-ops.astra','text/unicode-scalars.astra']]
	providers=[apps/'resources.c',*[ROOT/'lib/runtime/platform'/name for name in ['args-posix.c','text-posix.c','text-ops-posix.c','files-posix.c']]]
	flags=['-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer']
	objects=[]
	for source in providers:
		obj=e.output/(source.stem+'.o');objects.append(obj)
		result=e.run(['clang-22',*flags,'-c',source,'-o',obj],stdout='')
		assert not result.stderr
	environment=dict(ASAN_OPTIONS='detect_leaks=1:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
	for app in ['a73-document.astra','a74-router.astra','a83-diagnostics.astra']:
		selected=libraries+([ROOT/'lib/astra/hosted/files.astra',ROOT/'lib/astra/text/scalar-format.astra'] if app.startswith('a83') else [])
		obj,exe=e.output/(app+'.o'),e.output/app.removesuffix('.astra')
		result=e.run([e.compiler,'-O2','--entry-object','--vapi',apps/'resources.vapi',*selected,apps/app,'-o',obj],stdout='')
		assert not result.stderr
		result=e.run(['clang-22',*flags,'-no-pie',obj,*objects,'-o',exe],stdout='')
		assert not result.stderr
		if app.startswith('a73'):
			cases=[(['3/λ/41/right','-1'],'+3\n+103\n+41\n+141\nN214\n-141\nE1041\n-41\n-103\nN72\nE1003\n-3\nN0\n',0),
				(['3/λ/41/right','0'],'document stage\nN0\n',2),
				(['3/λ/41/right','5'],'+3\n+103\n-103\nE1003\n-3\ndocument stage\nN0\n',2),
				(['3/λ/41/right','13'],'+3\n+103\n+41\n+141\n-141\nE1041\n-41\n-103\nE1003\n-3\ndocument stage\nN0\n',2)]
		elif app.startswith('a74'):
			cases=[(['L:3|L:3|emit|P:4|P:4|emit|L:5|P:5|emit'],
				'+3\n+3\n-3\n-3\nN9\n+4\n+4\n-4\n-4\nN26\n+5\n+5\n-5\n-5\nN31\nN0\nN66\nN0\n',0)]
		else:
			valid,invalid=e.output/'diagnostics.txt',e.output/'invalid.txt'
			valid.write_bytes('E:λ\nW:abc\n'.encode());invalid.write_bytes(b'I:\xf0\x9f')
			cases=[([valid],'+83\ndiagnostics=2 score=11\n1:3 bytes=2 scalars=1 λ\n2:2 bytes=3 scalars=3 abc\nbytes=5 scalars=4\n-83\nN0\n',0),
				([invalid],'+83\n-83\ninvalid UTF-8\nN0\n',2),([e.output/'missing.txt'],'+83\n-83\nfile I/O\nN0\n',2)]
			e.files(valid,invalid)
		for arguments,expected,status in cases:
			result=e.run([exe,*arguments],expected=status,stdout=expected,env=environment)
			assert not result.stderr,result.stderr
		e.files(obj,exe,apps/app,*selected)
	e.files(*providers,*[p.with_suffix('.h') for p in providers if p.with_suffix('.h').is_file()],apps/'resources.vapi',Path(__file__),ROOT/'tests/systems-dsp-9/support.py')
	e.data['instrumentation']='Clang ASan/UBSan on the actual C Resource/POSIX adapters; Astra LLVM and foreign/system libraries are not sanitizer-instrumented.'
	e.complete()


if __name__=='__main__':
	main(*sys.argv[1:])
