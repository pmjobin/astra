"""Full unsuppressed Valgrind audit of one current O2 product for each app."""
from pathlib import Path
import json
import sys
import evidence as support


def main(compiler,output,components):
	e=support.Evidence(compiler,output,'memory-audit');components=Path(components).resolve()
	e.inputs(Path(__file__))
	selected=[(f'a{app}',f'a{app}/a{app}-O2') for app in range(85,92)]
	selected += [('policies','policies/policies-O2'),('a93','a93/local-O2-on'),('a94','a94/readonly-O2-on'),('a95','a95/a95-O2-on'),('a96','a96/O0/stream')]
	for recipe,relative in selected:
		receipt=components/recipe/(recipe+'.json');data=json.loads(receipt.read_text())
		assert data['status']=='PASS' and data['compiler']['sha256']==e.data['compiler']['sha256'], recipe
		exe=components/relative
		assert any(row['path']==str(exe) and row['sha256']==support.parent.identity(exe)['sha256'] for row in data['files']),relative
		result=e.run(['valgrind','--default-suppressions=no','--error-exitcode=91','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all','-s',exe],timeout=300)
		assert 'ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)' in result.stderr
		assert 'in use at exit: 0 bytes in 0 blocks' in result.stderr
		e.inputs(receipt,exe)
	e.data['scope']='Twelve current public O2 products; A96 producer O0/consumer O2. Default suppressions explicitly disabled; no reachable heap at exit and zero suppressed/error contexts required.'
	e.complete()


if __name__=='__main__':main(*sys.argv[1:])
