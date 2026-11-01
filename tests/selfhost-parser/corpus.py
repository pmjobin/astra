# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fixed independent cases and bounded grammar generation; no candidate results."""
import random


def cases():
	result = []
	def add(name, text, positive=None, error=None):
		data = text.encode() if isinstance(text, str) else text
		result.append(dict(name=name, data=data, positive=positive, error=error))
	add('empty', '', True)
	add('precedence', 'int f(){return 1+2*3;}', True)
	add('associativity', 'int f(){return 9-3-1;}', True)
	add('comparisons', 'bool f(){return 1<2<3<4;}', True)
	add('generic-shift', 'Box<Bag<int>> f(Box<Bag<int>> x){return choose<Box<int>>(x) >> 2;}', True)
	add('failed-probe', 'bool f(int x,int y){return x < y >> 1;}', True)
	add('enum-application', 'Choice<int> f(){return Choice<int>.Value(2);}', True)
	add('directives', 'namespace Alpha; using Beta; internal int f(){return 1;}', True)
	add('field-policies', 'class C { private owned Item value; readonly string name; init(owned Item value){this.value=move value;this.name="x";} int get(){return 1;} property int number { get {return 1;} } }', True)
	add('enum-generics', 'enum Choice<T>{Value(owned T value),Empty}', True)
	add('loops', 'int f(){for(var i=0;i<3;i=i+1){if(i==2){break;}else{continue;}}while(false){}return 0;}', True)
	add('exception', 'int f() throws Fault {try{throw new Fault();}catch(Fault error){throw;}return 0;}', True)
	add('utf8-text', 'string f(){return "é😀\\0\\u0041";}', True)
	add('vector-dsp', 'int f(){i16<4> x={1,2,3,4};var y=splat(x,4);var z=sat_add(x,x);return dot_wrap(x,x,int);}', True)
	add('syntax-only-semantic-error', 'Missing f(){return 123;}', True)
	add('foreign-empty', '[CImport] int read();', True)
	add('foreign-channel', '[CImport(name="read")] int read(borrowed void* input);', True)
	add('interface', 'interface Contract {int value();}', True)
	add('factory', '[Utf8MessageFactory] owned Utf8Message utf8_message(u8[] bytes) throws InvalidUtf8;', True)
	add('callable-channels', 'Fn<owned Item,borrowed Item> f(Fn<owned Item,borrowed Item> fn){return fn;}', True)
	for newline in ('\n', '\r', '\r\n'):
		text = '// é😀' + newline + 'int f(){return var;}'
		at = text.encode().index(b'var')
		add('coordinates-' + repr(newline), text, False, (at, at + 3, "'var' is a reserved keyword for inferred local declarations"))
	for name, text, token, message in [
		('const-keyword', 'int f(){return const;}', b'const', "'const' is a reserved keyword for compile-time constants"),
		('colon', 'int f(){:}', b':', "unexpected character ':'"),
		('duplicate-using', 'using A;using A;', b'A;', 'duplicate using namespace'),
		('duplicate-nonnull', 'nonnull nonnull Item f(){return null;}', b'nonnull Item', 'duplicate nonnull qualifier'),
	]:
		at = text.encode().rindex(token)
		width = 7 if name == 'duplicate-nonnull' else 1 if name in ('colon', 'duplicate-using') else len(token)
		add(name, text, False, (at, at + width, message))
	add('invalid-utf8', b'@\xff', False, (1, 2, 'invalid UTF-8 encoding'))
	add('raw-nul', b'@\0', False, (1, 2, 'unexpected NUL byte'))
	add('bad-escape', 'int f(){return "\\q";}', False)
	add('namespace-order', 'int f(){return 1;}using A;', False)
	add('duplicate-metadata', '[CImport(name="a",name="b")] int read();', False)
	add('metadata-nul-escape', '[CImport(name="\\0")] int read();', False)
	add('type-argument-trailing', 'Box<int,> f(){return 0;}', False)
	add('failed-keyword-scan', 'class @', False, (6, 7, "unexpected character '@'"))
	declaration = 'namespace A;[CImport]int read(int x);class C{int x;init(){this.x=1;}property int value{get{return 1;}}}'
	for offset in range(len(declaration) + 1):
		add(f'invalid-token-boundary-{offset}', declaration[:offset] + '@' + declaration[offset:], False)
	for count in (0, 1, 254, 255, 256, 257):
		add(f'parentheses-{count}', 'int f(){return ' + '(' * count + '1' + ')' * count + ';}', count <= 255)
		add(f'blocks-{count}', 'int f(){' + '{' * count + 'return 1;' + '}' * count + '}', count <= 255)
		add(f'types-{count}', 'Box<' * count + 'int' + '>' * count + ' f(){return 1;}', count <= 255)
	for count in (255, 256, 257, 2000):
		add(f'left-tree-{count}', 'int f(){return ' + '+'.join(['1'] * count) + ';}', count <= 256)
	add('many-declarations', ''.join(f'int f{i}(){{return {i};}}' for i in range(2048)), True)
	add('pointer-type-long', 'Box<int>' + '*' * 2048 + ' f(){return null;}', True)
	for depth in (256, 1024):
		initializer = '{child=' * depth + '{value=1}' + '}' * depth
		add(f'record-initializer-{depth}', 'int f(){Point value=' + initializer + ';return 0;}', True)
		add(f'array-record-initializer-{depth}', 'int f(){Point[1] values={' + initializer + '};return 0;}', True)
		add(f'bad-record-initializer-{depth}', 'int f(){Point value=' + initializer[:-1] + ',};return 0;}', False)
	rng = random.Random(303)
	ops = ['+', '-', '*', '/', '%', '<<', '>>', '<', '<=', '>', '>=', '==', '!=', '&&', '||', '|', '&', '^']
	atoms = ['x', 'y', '1', '2', 'true', 'false', 'pick<int>(x)', 'Choice<int>.Value(x)', 'x as i32']
	def expression(depth):
		if depth == 0 or rng.randrange(4) == 0:
			return rng.choice(atoms)
		if rng.randrange(4) == 0:
			return rng.choice(['+', '-', '!', '~']) + '(' + expression(depth - 1) + ')'
		return '(' + expression(depth - 1) + ' ' + rng.choice(ops) + ' ' + expression(depth - 1) + ')'
	for index in range(2000):
		expr = expression(rng.randrange(1, 6))
		add(f'generated-positive-{index}', 'int f(int x,int y){return ' + expr + ';}', True)
		if index < 750:
			add(f'generated-negative-{index}', 'int f(int x,int y){return ' + expr + '}', False)
	return result
