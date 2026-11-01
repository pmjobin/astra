# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent source annotations and targets, frozen before any native run.

Markers give byte spans in original UTF-8. Neither C0 nor the candidate writes
these expectations. Unmarked names are still checked through C0's projection.
"""
import re


def materialize(files):
	texts, marks = {}, {}
	for path, template in files.items():
		out = bytearray()
		last = 0
		for match in re.finditer(r'\{\{([^|]+)\|([^}]+)\}\}', template):
			out.extend(template[last:match.start()].encode())
			name, text = match.groups()
			assert name not in marks
			start = len(out)
			out.extend(text.encode())
			marks[name] = (path, start, len(out))
			last = match.end()
		out.extend(template[last:].encode())
		texts[path] = bytes(out)
	return texts, marks


def cases():
	base = {'a.astra': 'namespace A;struct {{typeA|Item}}{int {{fieldA|value}};}const int {{constA|K}}=3;int {{funcA|f}}(int {{paramA|x}}){return {{readA|x}}+{{readK|K}};}', 'b.astra': 'namespace B;using A;int {{funcB|g}}(){int {{localB|v}}={{callA|f}}(2);return {{readB|v}}+{{qualK|A.K}};}'}
	yield dict(name='cross-file', files=base, refs={'readA':'paramA','readK':'constA','callA':'funcA','readB':'localB','qualK':'constA'}, oracle='positive')
	yield dict(name='same-namespace', files={'a.astra':'namespace A;int {{a|f}}(){return 1;}', 'b.astra':'namespace B;int {{b|f}}(){return 2;}int g(){return {{r|f}}();}', 'c.astra':'namespace C;using A;using B;int h(){return B.{{q|f}}();}'}, refs={'r':'b','q':'b'}, oracle='positive')
	yield dict(name='import-A', files={'a.astra':'namespace A;int {{a|f}}(){return 1;}', 'b.astra':'namespace B;int {{b|f}}(){return 2;}', 'c.astra':'using A;int g(){return {{r|f}}();}'}, refs={'r':'a'}, oracle='positive')
	yield dict(name='import-B', files={'a.astra':'namespace A;int {{a|f}}(){return 1;}', 'b.astra':'namespace B;int {{b|f}}(){return 2;}', 'c.astra':'using B;int g(){return {{r|f}}();}'}, refs={'r':'b'}, oracle='positive')
	yield dict(name='ambiguity', files={'a.astra':'namespace A;int f(){return 1;}', 'b.astra':'namespace B;int f(){return 2;}', 'c.astra':'using A;using B;int g(){return {{error|f}}();}'}, error="ambiguous imported name 'f': 'A.f' and 'B.f'; qualify the reference", oracle='error')
	yield dict(name='import-order', files={'a.astra':'namespace A;int f(){return 1;}', 'b.astra':'namespace B;int f(){return 2;}', 'c.astra':'using B;using A;int g(){return {{error|f}}();}'}, error="ambiguous imported name 'f': 'B.f' and 'A.f'; qualify the reference", oracle='error')
	yield dict(name='unknown-import', files={'a.astra':'using {{error|Absent}};int f(){return missing;}'}, error="unknown imported namespace 'Absent'; supply its source files explicitly", oracle='error')
	yield dict(name='internal-allowed', files={'a.astra':'namespace A;internal int {{f|f}}(){return 1;}', 'b.astra':'namespace A;int g(){return {{r|f}}();}'}, refs={'r':'f'}, oracle='positive')
	yield dict(name='internal-denied', files={'a.astra':'namespace A;internal int f(){return 1;}', 'b.astra':'namespace B;int g(){return A.{{error|f}}();}'}, error="internal declaration 'A.f' is accessible only within namespace 'A'", oracle='error')
	yield dict(name='lexical-siblings', files={'a.astra':'const int {{global|x}}=1;int f(int {{p|p}}){if(true){int {{error|x}}={{rp1|p}};int u={{r1|x}};}if(false){int {{two|x}}={{rp2|p}};int v={{r2|x}};}return {{r3|x}};}'}, error="duplicate local 'x'", oracle='error')
	yield dict(name='sibling-locals', files={'a.astra':'int f(int {{p|p}}){if(true){int {{one|x}}={{rp1|p}};int u={{r1|x}};}if(false){int {{two|x}}={{rp2|p}};int v={{r2|x}};}return {{r3|p}};}'}, refs={'rp1':'p','rp2':'p','r1':'one','r2':'two','r3':'p'}, oracle='positive')
	yield dict(name='nested-collision', files={'a.astra':'int f(int p){int x=1;if(true){int {{error|x}}=2;}return p;}'}, error="duplicate local 'x'", oracle='error')
	yield dict(name='parameter-collision', files={'a.astra':'int f(int p){int {{error|p}}=1;return p;}'}, error="local 'p' conflicts with parameter", oracle='error')
	yield dict(name='before-declaration', files={'a.astra':'int f(){int x={{error|y}};int y=2;return x;}'}, error="unknown name 'y'", oracle='error')
	yield dict(name='out-of-scope', files={'a.astra':'int f(){if(true){int x=1;}return {{error|x}};}'}, error="unknown name 'x'", oracle='error')
	yield dict(name='unknown-first', files={'a.astra':'int f(){return {{error|missing}}+other;}'}, error="unknown name 'missing'", oracle='error')
	yield dict(name='duplicate-function', files={'a.astra':'int {{first|f}}(){return 1;}int {{error|f}}(){return 2;}'}, error="duplicate function 'f'; overloading is not implemented", oracle='error')
	yield dict(name='forward', files={'a.astra':'int {{f|f}}(){return {{r|later}}();}', 'b.astra':'int {{later|later}}(){return 7;}'}, refs={'r':'later'}, oracle='positive')
	yield dict(name='domain', files={'a.astra':'struct {{t|Thing}}{int value;}int {{v|Thing}}(){return 1;}int f(){ {{rt|Thing}} x={value=2};return {{rv|Thing}}();}'}, refs={'rt':'t','rv':'v'}, oracle='positive')
	yield dict(name='members', files={'a.astra':'class {{c|C}}{int {{field|value}};{{init|init}}(int {{p|v}}){this.{{f1|value}}={{r|v}};}int {{method|get}}(){return this.{{f2|value}};}property int {{prop|number}}{get{return this.{{f3|value}};}}}int f(){var {{local|c}}=new {{tc|C}}(1);return {{rc|c}}.{{select|get}}();}'}, refs={'r':'p','tc':'c','rc':'local'}, owners={'field':'c','init':'c','method':'c','prop':'c','p':'init'}, deferred={'f1':1,'f2':1,'f3':1,'select':1}, oracle='positive')
	yield dict(name='generic', files={'a.astra':'struct {{box|Box}}<{{t|T}}>{ {{rt|T}} value;}int {{id|id}}<{{u|U}}>({{ru|U}} {{x|x}}){return 1;}int f(){return {{ri|id}}<int>(1);}'}, refs={'rt':'t','ru':'u','ri':'id'}, oracle='positive')
	yield dict(name='nested-types', files={'a.astra':'struct {{box|Box}}<T>{T value;}struct {{s|S}}{int value;}int f({{b1|Box}}<{{b2|Box}}<{{rs|S}}>> x){return 0;}'}, refs={'b1':'box','b2':'box','rs':'s'}, oracle='positive')
	yield dict(name='for-loop', files={'a.astra':'int f(){for(int {{i|i}}=0;{{r1|i}}<3;{{r2|i}}={{r3|i}}+1){int x={{r4|i}};}return 0;}'}, refs={'r1':'i','r2':'i','r3':'i','r4':'i'}, oracle='positive')
	yield dict(name='utf8-crlf', files={'a.astra':'// é😀\r\nint {{f|f}}(int {{x|x}}){\r\nreturn {{r|x}};\r\n}'}, refs={'r':'x'}, oracle='positive')
	yield dict(name='later-types', files={'a.astra':'int f(int {{p|x}}){return {{r|x}}+true;}'}, refs={'r':'p'}, oracle='later', later='')
	yield dict(name='lexical-first', files={'a.astra':'int f(){return missing;}\x00'}, error='source contains NUL byte', oracle='syntax', raw_error=True)
	yield dict(name='syntax-first', files={'a.astra':'int f( {return missing;}'}, oracle='syntax', raw_error=True)
	yield dict(name='foreach', files={'a.astra':'int f(int[] {{xs|xs}}){int {{sum|sum}}=0;foreach(var {{x|x}} in {{rxs|xs}}){ {{rs1|sum}}={{rs2|sum}}+{{rx|x}};}return {{rs3|sum}};}'}, refs={'rxs':'xs','rx':'x','rs1':'sum','rs2':'sum','rs3':'sum'}, oracle='positive')
	yield dict(name='catch', files={'a.astra':'class {{e|E}}{}int f(){try{return 1;}catch({{re|E}} {{v|error}}){return {{rv|error}}.{{member|code}};}}'}, refs={'re':'e','rv':'v'}, deferred={'member':1}, oracle='later', later='')
	yield dict(name='with', files={'a.astra':'int f(){with(var {{v|value}}=1){return {{r|value}};}}'}, refs={'r':'v'}, oracle='later', later='')
	yield dict(name='enum', files={'a.astra':'enum {{e|Result}}{ {{variant|Good}}(int {{payload|value}}),Bad }int f({{t|Result}} {{p|r}}){match({{r|r}}){case {{q|Result}}.{{select|Good}}({{binding|x}}):{return {{rx|x}};}case Result.Bad():{return 0;}}}'}, refs={'t':'e','r':'p','q':'e','rx':'binding'}, owners={'variant':'e','payload':'variant'}, deferred={'select':4}, oracle='positive')
	yield dict(name='generic-nominal-collision', files={'a.astra':'struct Existing{int value;}int f<{{error|Existing}}>(int x){return x;}'}, error="type parameter 'Existing' cannot shadow an outer type in GEN-1", oracle='error')
	yield dict(name='duplicate-parameter', files={'a.astra':'int f(int x,int {{error|x}}){return x;}'}, error="duplicate parameter 'x'", oracle='error')
	yield dict(name='call-precedence', files={'a.astra':'int {{f|f}}(){return 2;}int g(){int {{v|f}}=1;return {{r|f}}();}'}, refs={'r':'f'}, oracle='positive')
	yield dict(name='intrinsic', files={'a.astra':'int f(int[] {{v|xs}}){return {{len|len}}({{r|xs}});}'}, refs={'r':'v'}, deferred={'len':5}, oracle='positive')
	yield dict(name='separate-owners', files={'a.astra':'namespace A;int {{fa|f}}(){return 1;}', 'b.astra':'namespace B;int {{fb|f}}(){return 1;}', 'c.astra':'int client(){return A.{{a|f}}()+B.{{b|f}}();}'}, refs={'a':'fa','b':'fb'}, oracle='positive')
	yield dict(name='duplicate-cross-source', files={'a.astra':'int f(){return 1;}', 'b.astra':'int {{error|f}}(){return 1;}'}, error="duplicate function 'f'; overloading is not implemented", oracle='previous')
	yield dict(name='caller-information', files={'a.astra':'int f(int {{x|x}},[CallerArgumentExpression({{target|"x"}})]string text){return {{r|x}};}int g(){return f(2);}'}, refs={'target':'x','r':'x'}, oracle='positive')
	yield dict(name='caller-unknown', files={'a.astra':'int f(int x,{{error|[CallerArgumentExpression("missing")]}}string text){return x;}'}, error='CallerArgumentExpression must name an earlier required non-annotated parameter; unknown names, self, caller parameters, this and member paths are unsupported', oracle='error')
	yield dict(name='duplicate-field', files={'a.astra':'struct S{int x;int {{error|x}};}'}, error="duplicate field 'x' in struct 'S'", oracle='error')
	yield dict(name='duplicate-method', files={'a.astra':'class C{init(){}int f(){return 1;}int {{error|f}}(){return 2;}}'}, error="duplicate method 'f' in class 'C'; overloading is not implemented", oracle='error')
	yield dict(name='duplicate-variant', files={'a.astra':'enum E{One,{{error|One}}}'}, error="duplicate enum variant 'E.One'", oracle='error')
	yield dict(name='owner-slots', files={'a.astra':'class C<T>{owned T[slots] entries;init(){this.entries=new T[{{slot|slots}}];}}'}, deferred={'slot':6}, oracle='positive')
	yield dict(name='ordinary-slots-unknown', files={'a.astra':'int f(){return {{error|slots}};}'}, error="unknown name 'slots'", oracle='error')
	yield dict(name='rename-local', files={'a.astra':'int f(){int renamed=1;return {{error|original}};}'}, error="unknown name 'original'", oracle='error')
	yield dict(name='where', files={'a.astra':'{{ret|T}} add<{{t|T}}>({{paramtype|T}} {{a|a}},T b)where {{where|T}}:Numeric{return {{ra|a}}+b;}int f(){return add<int>(1,2);}'}, refs={'ret':'t','paramtype':'t','where':'t','ra':'a'}, oracle='positive')
	yield dict(name='address', files={'a.astra':'int f(){int {{x|x}}=1;int* {{p|p}}=&{{addr|x}};return *{{rp|p}};}'}, refs={'addr':'x','rp':'p'}, oracle='positive')
	yield dict(name='invalid-utf8', files={'a.astra':''}, raw_hex={'a.astra':'696e74206628297b72657475726e2022ff223b7d'}, raw_error=True, oracle='syntax')

	yield dict(name='com-type', files={'a.astra':'[COMImport(name="View")]interface {{com|View}};'}, declarations={'com':(4,1)}, oracle='later',later='')
	yield dict(name='foreign-owner', files={'a.astra':'[CImport(name="Foreign")]class {{c|Foreign}}{ {{init|init}}();int {{method|read}}(int {{p|x}});}'}, owners={'init':'c','method':'c','p':'method'}, oracle='later',later='')
