# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lazy effects, fatal ownership edges and emitted machine controls."""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
PRELUDE = '''extern(C) int af_case();
extern(C) void af_fail();
extern(C) int af_count(int n);
extern(C) int af_arg(int index,int n);
extern(C) void af_action(int code,int n);
extern(C) void af_return();
extern(C) void af_next();
extern(C) void af_assert(int actual,int expected);
extern(C) void af_c_report(int code,int n);
extern(C) void af_exit(int code,int n);
void report(int code,int n){af_action(code,n);af_return();}
void inspect(int[] old,int n){af_assert(old[0],7);report(10,len(old));}
void consume(owned int[] old){report(11,len(old));}
void generic_report<T>(T value,int n){report(12,n);}
owned T[] make<T>(int n,int code){return new T[af_count(n)] else report(af_arg(1,code),af_arg(2,n));}
owned T[] forward<T>(int n,int code){return make<T>(n,code);}
void parameter(owned int[] old,int n){old=new int[af_count(n)] else inspect(old,n);af_next();}
struct Reporter{int code;void report(int n){report(this.code,n);}}
class Holder{owned int[] a;init(int n){this.a=new int[af_count(n)] else report(13,n);}void replace(int n){this.a=new int[af_count(n)] else inspect(this.a,n);}}
string label(int n){if(n>0){return "written";}return "other";}
void report_bool(bool good,int n){if(good){report(14,n);}else{report(999,n);}}
void metadata(int n,[CallerFilePath] string file,[CallerLineNumber] int line,[CallerArgumentExpression("n")] string expression){if(file!="effects.astra"||line!=META_LINE||expression!="af_arg(1, 2)"){report(999,n);}report(15,n);}
bool condition(){var a=new int[af_count(2)] else report(999,2);return true;}
void consume_any<T>(owned T[] a){report(21,len(a));}
owned T[] move_failure<T>(owned T[] incoming,int n){owned T[] a=new T[n] else consume_any(move incoming);af_assert(len(incoming),1);return move a;}
class Token{init(){af_action(70,0);}deinit(){af_action(71,0);}}
void consume_resources<U,V>(owned U resource,owned V token) where U : Ownable where V : Ownable {report(22,0);}
'''
# Exact expected traces distinguish expression evaluation, allocation attempt,
# action entry/normal return and the forbidden next statement. Fatal tests do
# not pass through the observer's normal-cleanup destructor.
CASES = [
	('success', 'var a=new int[af_count(2)] else report(af_arg(1,8),af_arg(2,2));af_next();', 0, 'C2 Q2:4 A1 NEXT F1'),
	('zero', 'var a=new int[af_count(0)] else report(af_arg(1,8),af_arg(2,0));af_assert(len(a),0);af_next();', 0, 'C0 NEXT'),
	('negative', 'var a=new int[af_count(-1)] else report(af_arg(1,8),af_arg(2,-1));af_next();', -signal.SIGILL, 'C-1'),
	('count-trap', 'var a=new int[1/af_count(0)] else report(af_arg(1,8),2);af_next();', -signal.SIGILL, 'C0'),
	('returning-native', 'af_fail();var a=new int[af_count(2)] else report(af_arg(1,8),af_arg(2,2));af_next();', -signal.SIGILL, 'C2 Q2:4 NULL G1:8 G2:2 H8:2:L0 RET'),
	('returning-c', 'af_fail();var a=new int[af_count(2)] else af_c_report(af_arg(1,8),af_arg(2,2));af_next();', -signal.SIGILL, 'C2 Q2:4 NULL G1:8 G2:2 H8:2:L0 RET'),
	('fatal-c', 'var old=new int[1];af_fail();var a=new int[af_count(2)] else af_exit(af_arg(1,9),af_arg(2,2));af_next();', 23, 'Q1:4 A1 C2 Q2:4 NULL G1:9 G2:2 H9:2:L1'),
	('argument-trap', 'af_fail();var a=new int[af_count(2)] else report(af_arg(1,8),7/af_arg(2,0));af_next();', -signal.SIGILL, 'C2 Q2:4 NULL G1:8 G2:0'),
	('explicit-repeated-count', 'af_fail();var a=new int[af_count(2)] else report(8,af_count(2));af_next();', -signal.SIGILL, 'C2 Q2:4 NULL C2 H8:2:L0 RET'),
	('saved-count', 'int n=af_count(2);af_fail();var a=new int[n] else report(8,n);af_next();', -signal.SIGILL, 'C2 Q2:4 NULL H8:2:L0 RET'),
	('receiver', 'Reporter[1] r={{code=9}};af_fail();var a=new int[af_count(2)] else r[af_arg(0,0)].report(af_arg(1,2));af_next();', -signal.SIGILL, 'C2 Q2:4 NULL G0:0 G1:2 H9:2:L0 RET'),
	('receiver-success', 'Reporter[1] r={{code=9}};var a=new int[af_count(2)] else r[af_arg(0,0)].report(af_arg(1,2));af_next();', 0, 'C2 Q2:4 A1 NEXT F1'),
	('receiver-zero', 'Reporter[1] r={{code=9}};var a=new int[af_count(0)] else r[af_arg(0,0)].report(af_arg(1,2));af_next();', 0, 'C0 NEXT'),
	('replacement-success', 'var old=new int[2];old[0]=7;old=new int[af_count(3)] else inspect(old,af_arg(1,3));af_next();', 0, 'Q2:4 A1 C3 Q3:4 A2 F1 NEXT F2'),
	('replacement-failure', 'var old=new int[2];old[0]=7;af_fail();old=new int[af_count(3)] else inspect(old,af_arg(1,3));af_next();', -signal.SIGILL, 'Q2:4 A1 C3 Q3:4 NULL G1:3 H10:2:L1 RET'),
	('independent-move-success', 'var old=new int[1];var a=new int[2] else consume(move old);af_assert(len(old),1);af_next();', 0, 'Q1:4 A1 Q2:4 A2 NEXT F2 F1'),
	('independent-move-failure', 'var old=new int[1];var independent=new int[2];af_fail();old=new int[3] else consume(move independent);af_next();', -signal.SIGILL, 'Q1:4 A1 Q2:4 A2 Q3:4 NULL H11:2:L2 RET F2'),
	('parameter-success', 'var old=new int[2];old[0]=7;parameter(move old,3);', 0, 'Q2:4 A1 C3 Q3:4 A2 F1 NEXT F2'),
	('parameter-failure', 'var old=new int[2];old[0]=7;af_fail();parameter(move old,3);', -signal.SIGILL, 'Q2:4 A1 C3 Q3:4 NULL H10:2:L1 RET'),
	('field-success', 'var h=Holder.init(2);h.a[0]=7;h.replace(3);af_next();', 0, 'C2 Q2:4 A1 C3 Q3:4 A2 F1 NEXT F2'),
	('field-failure', 'var h=Holder.init(2);h.a[0]=7;af_fail();h.replace(3);af_next();', -signal.SIGILL, 'C2 Q2:4 A1 C3 Q3:4 NULL H10:2:L1 RET'),
	('field-initialize-failure', 'af_fail();var h=Holder.init(2);af_next();', -signal.SIGILL, 'C2 Q2:4 NULL H13:2:L0 RET'),
	('released-rearm', 'var old=new int[1];release old;old=new int[2] else report(999,2);af_next();', 0, 'Q1:4 A1 F1 Q2:4 A2 NEXT F2'),
	('moved-rearm', 'var old=new int[1];var moved=move old;old=new int[2] else report(999,2);af_next();', 0, 'Q1:4 A1 Q2:4 A2 NEXT F1 F2'),
	('generic-success', 'var a=make<int>(2,40);var b=forward<int>(3,41);af_next();', 0, 'C2 Q2:4 A1 C3 Q3:4 A2 NEXT F2 F1'),
	('generic-zero', 'var a=make<int>(0,40);af_next();', 0, 'C0 NEXT'),
	('generic-negative', 'var a=make<int>(-1,40);af_next();', -signal.SIGILL, 'C-1'),
	('generic-failure', 'af_fail();var a=forward<int>(2,40);af_next();', -signal.SIGILL, 'C2 Q2:4 NULL G1:40 G2:2 H40:2:L0 RET'),
	('generic-action-inferred', 'af_fail();var a=new int[2] else generic_report(af_arg(1,7),af_arg(2,2));af_next();', -signal.SIGILL, 'Q2:4 NULL G1:7 G2:2 H12:2:L0 RET'),
	('generic-action-explicit', 'af_fail();var a=new int[2] else generic_report<int>(af_arg(1,7),af_arg(2,2));af_next();', -signal.SIGILL, 'Q2:4 NULL G1:7 G2:2 H12:2:L0 RET'),
	('bounds', 'var a=new int[1] else report(999,1);af_assert(a[af_count(1)],0);af_next();', -signal.SIGILL, 'Q1:4 A1 C1'),
	('shortcircuit-skipped', 'if(false&&condition()){af_next();}', 0, ''),
	('metadata', 'af_fail();var a=new int[2] else metadata(af_arg(1, 2));af_next();', -signal.SIGILL, 'Q2:4 NULL G1:2 H15:2:L0 RET'),
	('argument-splits', 'af_fail();var a=new int[2] else report_bool(label(af_arg(1,1))=="written"&&(af_arg(2,1)>0||af_arg(3,0)>0),(4.0d/(af_arg(4,2) as f64)) as int);af_next();', -signal.SIGILL, 'Q2:4 NULL G1:1 G2:1 G4:2 H14:2:L0 RET'),
	('argument-conversion-trap', 'af_fail();var a=new int[2] else report(8,(4.0d/(af_arg(1,0) as f64)) as int);af_next();', -signal.SIGILL, 'Q2:4 NULL G1:0'),
	('default-still-traps', 'af_fail();var a=new int[af_count(2)];af_next();', -signal.SIGILL, 'C2 Q2:4 NULL'),
	('generic-independent-move-success', 'var old=new int[1];var a=move_failure(move old,2);af_next();', 0, 'Q1:4 A1 Q2:4 A2 F1 NEXT F2'),
	('generic-independent-move-failure', 'var old=new int[1];af_fail();var a=move_failure(move old,2);af_next();', -signal.SIGILL, 'Q1:4 A1 Q2:4 NULL H21:1:L1 RET F1'),
	('mixed-success', 'var old=new int[1];var resource=resource(1);var token=Token.init();var a=new int[2] else consume_resources(move resource,move token);af_next();', 0, 'Q1:4 A1 R+1 H70:0:L1 Q2:4 A2 NEXT F2 H71:0:L1 R-1 F1'),
	('mixed-failure', 'var old=new int[1];var resource=resource(1);var token=Token.init();af_fail();var a=new int[2] else consume_resources(move resource,move token);af_next();', -signal.SIGILL, 'Q1:4 A1 R+1 H70:0:L1 Q2:4 NULL H22:0:L1 RET H71:0:L1 R-1'),
]


def qualify(compiler, out):
	out.mkdir(parents=True, exist_ok=False)
	(out / 'tmp').mkdir()
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	env = dict(os.environ, CCACHE_DISABLE='1', TMPDIR=str(out / 'tmp'))
	rows = []
	def run(argv, label, status=0, trace=None, case=None):
		p = subprocess.run(list(map(str, argv)), cwd=out, env=env | ({} if case is None else {'ASTRA_ALLOC_CASE': str(case)}), capture_output=True)
		(out / (label + '.stdout')).write_bytes(p.stdout)
		(out / (label + '.stderr')).write_bytes(p.stderr)
		rows.append(dict(label=label, argv=list(map(str, argv)), status=p.returncode, stdout_sha256=hashlib.sha256(p.stdout).hexdigest(), stderr_sha256=hashlib.sha256(p.stderr).hexdigest(), case=case))
		(out / 'commands.json').write_text(json.dumps(rows, indent='\t') + '\n')
		assert p.returncode == status and not p.stderr and (trace is None or p.stdout == trace), (label, status, trace, p)
		return p.stdout.decode()
	parts = [PRELUDE]
	for number, (name, body, status, trace) in enumerate(CASES):
		parts.append(f'int case{number}(){{{body}return 0;}}\n')
	parts.append('int main(){int selection=af_case();' + ''.join(f'if(selection=={i}){{return case{i}();}}' for i in range(len(CASES))) + 'return 99;}\n')
	source = ''.join(parts)
	metadata_line = next(i for i, line in enumerate(source.splitlines(), 1) if 'else metadata(' in line)
	(out / 'effects.astra').write_text(source.replace('META_LINE', str(metadata_line)))
	(out / 'resource.vapi').write_text('[CCode(destroy_function="af_drop")] handle Resource;\n[CCode(cname="af_resource")] owned Resource resource(int id);\n')
	dumps = {}
	for stage in STAGES:
		dumps[stage] = run([compiler, '--dump-' + stage, 'effects.astra', *([] if stage == 'syntax' else ['--vapi', 'resource.vapi'])], 'effects-' + stage)
		(out / ('effects.' + stage)).write_text(dumps[stage])
	assert dumps['ssa'].count('(buffer-allocation-branch ') > 20
	assert dumps['ssa'].count('(allocation-failure-trap)') == dumps['ssa'].count('(buffer-allocation-branch ')
	assert 'nobuiltin' in dumps['llvm'] and '@llvm.trap' in dumps['llvm']
	ordinal = re.search(r'\(function #(\d+) "main" -> int', dumps['ssa'])[1]
	wrapped = dumps['llvm'] + '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.' + ordinal + '()\n\tret i32 %r\n}\n'
	observers = {}
	for cc in ['gcc', 'clang']:
		observers[cc] = out / (cc + '-observer.o')
		run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', ROOT / 'tests/alloc-fail-1/companion.c', '-o', observers[cc]], cc + '-observer')
	for mode in ['O0', 'O2', 'O2-fma', 'preserved-O2']:
		ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', wrapped, flags=re.M) if mode == 'preserved-O2' else wrapped
		(out / (mode + '-input.ll')).write_text(ir)
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', mode + '-input.ll', '-o', mode + '.ll'], mode + '-opt')
		run(['opt', '-passes=verify', '-disable-output', mode + '.ll'], mode + '-verify')
		run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'O2-fma' else []), mode + '.ll', '-o', mode + '.o'], mode + '-llc')
		for cc, observer in observers.items():
			binary = out / (mode + '-' + cc)
			run([cc, mode + '.o', observer, '-Wl,--wrap=calloc,--wrap=free', '-o', binary], binary.name + '-link')
			for number, (name, body, status, trace) in enumerate(CASES):
				run([binary], binary.name + '-' + name, status, ''.join(part + '\n' for part in trace.split()).encode(), number)
		for suffix, command in [('machine', ['objdump', '-dr']), ('symbols', ['readelf', '-h', '-Ws', '-r']), ('cost', ['size', '-A']), ('dependencies', ['nm', '-u'])]:
			run([*command, mode + '.o'], mode + '-' + suffix)
	(out / 'result.json').write_text(json.dumps(dict(compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), cases=len(CASES), modes=4, observers=2, executions=8 * len(CASES), fatal_traces='nonunwinding; reporter may clean its own consumed parameters', cases_by_name=[row[0] for row in CASES]), indent='\t') + '\n')
	print(f'{len(CASES) * 8} exact effect/ownership/status traces')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
