# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reject real nominal, constructor and temporary receiver lifetime violations."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main(compiler_path, output_path, selected=None):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='refusals-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	owner = (HERE / 'owned-substitution.astra').read_text()
	copied = (HERE / 'copied-record.astra').read_text()
	methods = (HERE / 'method-tuples.astra').read_text()
	constraints = (HERE / 'substituted-constraints.astra').read_text()
	owned_formals = (HERE / 'open-class-owned-formals.astra').read_text()
	deferred = (HERE / 'deferred-instantiation.astra').read_text()
	nested_fields = (HERE / 'nested-field-observation.astra').read_text()
	bounded = (HERE / 'constrained-declarations.astra').read_text()
	closure = (HERE / 'closed-closure-environment.astra').read_text()
	async_owner = (HERE / 'owned-generic-async.astra').read_text()
	record_async = (HERE / 'generic-record-async.astra').read_text()
	comparator = (HERE / 'copied-record-comparator.astra').read_text()
	comparator_field = (HERE / 'generic-comparator-field.astra').read_text()
	inspection = (HERE / 'indexed-method-inspection.astra').read_text()
	lexical = (HERE / 'lexical-construction.astra').read_text()
	projections = (HERE / 'record-projections.astra').read_text()
	readonly_buffer = (HERE / 'readonly-buffer-view.astra').read_text()
	closure_channels = ('class ClosureInput{int code;init(){this.code=42;}}'
		'class ClosureOtherInput{init(){}}class ClosureEnv{init(){}}'
		'int observe_closure(borrowed ClosureEnv environment,borrowed ClosureInput input,int tag){return input.code+tag;}'
		'int consume_input(owned ClosureInput input){return 0;}'
		'int consume_closure(owned Closure<ClosureEnv,int,borrowed ClosureInput,int> code){return 0;}')
	closure_records = ('struct RecordPair{int value;i64 wide;}'
		'struct OtherRecordPair{int value;i64 wide;}class RecordEnv{init(){}}'
		'int read_record(borrowed RecordEnv environment,RecordPair value){return value.value;}')
	closure_binding = ('int main(){var environment=new ClosureEnv();var input=new ClosureInput();'
		'owned Closure<ClosureEnv,int,borrowed ClosureInput,int> code=closure_bind(move environment,observe_closure);')
	record_callbacks = ('struct Packet{owned int[] data;int tag;}'
		'struct OtherPacket{owned int[] data;int tag;}'
		'int consume(Packet packet){return packet.tag;}'
		'int two(Packet first,Packet second){return first.tag+second.tag;}'
		'int observe(borrowed Packet packet){return packet.tag;}')
	record_callback_owner = 'owned int[] data=new int[2];Packet packet={data=move data,tag=42};'
	class_callbacks = ('class Child{int value;init(){this.value=42;}}'
		'int consume(owned Child value,int extra){return value.value+extra;}'
		'int observe(borrowed Child value){return value.value;}')
	owned_callbacks = ('int consume_callback(owned R value){return id(value);}'
		'int borrow_callback(borrowed R value){return id(value);}'
		'int two_callbacks(owned R left,owned R right){return id(left)+id(right);}'
		'int overlap_callback(borrowed R left,owned R right){return id(left)+id(right);}'
		'int marked_callback(owned R value,int marker){return id(value)+marker;}')
	other_key = '\nstruct OtherKey { KeyPart part; bool active; }\n'
	transport_cell = 'class Cell<T>{owned T item;init(owned T item){this.item=move item;}}'
	transport_loan = 'int loan<T>(borrowed T value,int code) where T:Ownable{return code;}'
	transport_consume = 'int consume<T>(owned T value) where T:Ownable{return 0;}'
	exact_witness = 'class Witness<T> where T : ExactHeapClass { init() {} }\n'
	view_types = ('class Viewed{int code;init(){this.code=42;}}'
		'struct ViewPair{owned Viewed first;owned Viewed second;int stamp;}'
		'class ViewStore<T>{owned T value;init(owned T value){this.value=move value;}'
		'property borrowed T view{get{return this.value;}}}'
		'int inspect_view(borrowed Viewed value,int tag){return value.code;}'
		'int retire_view(owned ViewStore<ViewPair> value){return 0;}')
	view_main = ('int main(){var first=new Viewed();var second=new Viewed();'
		'ViewPair pair={first=move first,second=move second,stamp=42};'
		'var store=new ViewStore<ViewPair>(move pair);')
	buffer_types = ('struct BufferPair{owned int[] first;owned int[] second;int stamp;}'
		'class BufferStore<T>{owned T value;init(owned T value){this.value=move value;}'
		'property borrowed T view{get{return this.value;}}'
		'void replace(owned T value){this.value=move value;}}'
		'int read_samples(borrowed int[] value,int code){return len(value)+code;}'
		'int retire_buffers(owned BufferStore<BufferPair> value){return 0;}'
		'int consume_samples(owned int[] value){return 0;}'
		'int read_wide(borrowed i64[] value){return len(value);}'
		'int replace_buffers(borrowed BufferStore<BufferPair> store){'
		'var first=new int[7];var second=new int[9];'
		'BufferPair pair={first=move first,second=move second,stamp=84};'
		'store.replace(move pair);return 0;}')
	buffer_main = ('int main(){var first=new int[3];var second=new int[5];'
		'BufferPair pair={first=move first,second=move second,stamp=42};'
		'var store=new BufferStore<BufferPair>(move pair);')
	open_class = ('class Cell<T>{T value;init(T value){this.value=value;}'
		'T read(){return this.value;}'
		'property T item{get{return this.value;}set(T value){this.value=value;}}}')
	cases = {
		'generic-inferred-owner-copy': (
		'void copy<T>(owned T input) where T:Ownable{var alias=input;}int main(){return 0;}',
		'Ownable T cannot be copied'),
		'generic-inferred-owner-reuse': (
		'void reuse<T>(owned T input) where T:Ownable{var first=move input;var second=move input;}int main(){return 0;}',
		'generic local transfer requires a live incoming owner'),
		'fresh-caller-result-local-escape': (
		'class C{int number;init(int number){this.number=number;}}'
		'class Maker<T>{init(){}owned T make(){return C.init(42);}}'
		'owned T relay<T>(borrowed Maker<T> maker) where T:Ownable{'
		'owned T value=maker.make();return move value;}'
		'int main(){var maker=new Maker<C>();var value=relay<C>(maker);return value.number-42;}',
		'generic Class result cannot escape callee-local caller storage'),
		'dependent-fixed-Class-mixed-origins': (
		'class C{init(){}}struct Factory{int stamp;owned C make(){return C.init();}}'
		'class Host<P>{P producer;init(P producer){this.producer=producer;}'
		'owned C make(){P local=this.producer;return local.make();}}'
		'owned C relay<P>(borrowed Host<P> host){return host.make();}'
		'owned C outer<P>(borrowed Host<P> host,bool branch){if(branch){return relay<P>(host);}'
		'var value=new C();return move value;}'
		'int main(){Factory factory={stamp=42};var host=new Host<Factory>(factory);'
		'var value=outer<Factory>(host,true);return 0;}',
		'generic Class result joins incompatible heap and caller-backed storage origins'),
		'dead-owned-return-wrong-Class': (
		'class C{init(){}}class D{init(){}}'
		'owned C make(){if(false){var value=new D();return move value;}return C.init();}'
		'int main(){var value=make();return 0;}',
		'owned return requires exact lexical storage or a heap subtype of the result ClassType'),
		'dead-owned-return-caller-local-escape': (
		'class C{init(){}}'
		'owned C make(){if(false){owned C value=C.init();return move value;}return C.init();}'
		'int main(){var value=make();return 0;}',
		'callee-local owned ObjectStorage cannot escape through an owned result'),
		'member-wrapper-caller-input': (
		'class C{init(){}}class Host<T>{T marker;init(T marker){this.marker=marker;}'
		'owned R echo<R>(owned R value){return move value;}}'
		'owned R relay<T,R>(borrowed Host<T> host,owned R value) where R:Ownable{return host.echo<R>(move value);}'
		'int main(){var host=new Host<int>(1);owned C value=C.init();var result=relay(host,move value);return 0;}',
		'consuming Class member requires an independently heap-owned argument'),
		'member-wrapper-wrong-specialized-result': (
		'class C{init(){}}class D{init(){}}class Host<T>{T marker;init(T marker){this.marker=marker;}'
		'owned R make<R>(){return C.init();}}'
		'owned R relay<T,R>(borrowed Host<T> host) where R:Ownable{return host.make<R>();}'
		'int main(){var host=new Host<int>(1);var result=relay<int,D>(host);return 0;}',
		'return construction requires exact result ClassName.init'),
		'fixed-Class-heap-to-caller-sink': (
		'class C{init(){}}void consume(owned C value){}'
		'void relay<U>(owned C value,U marker){consume(move value);}'
		'int main(){var value=new C();relay<int>(move value,1);return 0;}',
		'generic ownership transfer requires caller-backed storage at a reachable consuming boundary'),
		'generic-storage-checked-consumer-retry': (
		'class Child{init(){}}'
		'void consume<T>(owned T value,bool fail) throws Error where T:Ownable{}'
		'bool argument() throws Error{throw new Error("argument");}'
		'void retire<T>(owned T value) where T:Ownable{}'
		'int main(){var value=new Child();try{consume<Child>(move value,argument());}'
		'catch(Error error){}retire<Child>(move value);return 0;}',
		"owned value 'value' may have been moved", 'cfg'),
		'lexical-class-formal-wrong-specialization': (
		owned_formals.replace('retire_copied_formal<int>(move number)', 'retire_copied_formal<bool>(move number)'),
		"requires exact type 'FormalEnvelope<bool>'"),
		'lexical-class-formal-unmoved': (
		owned_formals.replace('retire_copied_formal<int>(move number)', 'retire_copied_formal<int>(number)'),
		"requires explicit 'move owner'"),
		'lexical-class-formal-borrow-escape': (
		owned_formals.replace('if (retire_owner_formal<R>(move resource) != 1504)',
		'var alias = resource.view;\n\tint retired = retire_owner_formal<R>(move resource);\n\tif (id(alias) != 201 || retired != 1504)'),
		'storing, copying and escape are unsupported'),
		'lexical-class-formal-active-field-borrow': (
		owned_formals.replace('if (retire_owner_formal<R>(move resource) != 1504)',
		'if (inspect_formal_resource(resource.view, retire_owner_formal<R>(move resource)) != 1504)') +
		'\nint inspect_formal_resource(borrowed R value,int marker){return id(value)+marker;}\n',
		'temporary owned-field borrow overlaps'),
		'callable-owner-symbolic-result-missing-bound': (
		'owned T invoke<T>(Fn<owned T,int> code,int number){return code(number);}int main(){return 0;}',
		'owned T requires explicit capability Ownable'),
		'callable-owner-symbolic-result-wrong-type': (
		'owned T invoke<T>(Fn<owned Other> code) where T:Ownable{return code();}int main(){return 0;}',
		'owned generic return requires the exact result type parameter'),
		'closed-closure-symbolic-result-unhandled-error': (
		'class Env{init(){}}owned T invoke<T>(borrowed CheckedClosure<Env,Error,owned T> code) where T:Ownable{return closure_invoke(code);}int main(){return 0;}',
		"unhandled checked exception bound 'Error'"),
		'closed-closure-symbolic-result-wrong-environment': (
		'class Env{init(){}}class OtherEnv{init(){}}owned R create(borrowed OtherEnv environment){var result=make(42);return move result;}'
		'owned T invoke<T>(borrowed Closure<Env,owned T> code) where T:Ownable{return closure_invoke(code);}'
		'int main(){var environment=new OtherEnv();owned Closure<OtherEnv,owned R> code=closure_bind(move environment,create);var result=invoke<R>(code);return 0;}',
		"expects type 'Closure<Env,owned R>', provided 'Closure<OtherEnv,owned R>'"),
		'open-method-result-without-move': (
		'class Host<T>{init(){}owned U relay<U>(owned U value){return move value;}}'
		'owned U invoke<T,U>(borrowed Host<T> host,owned U value) where U:Ownable{return host.relay<U>(value);}'
		'int main(){return 0;}', "requires explicit 'move owner' or null"),
		'open-method-result-wrong-type': (
		'class Host<T>{init(){}owned Other bad<U>(owned U value){return null;}}'
		'owned U invoke<T,U>(borrowed Host<T> host,owned U value) where U:Ownable{return host.bad<U>(move value);}'
		'int main(){return 0;}', 'owned generic return requires the exact result type parameter'),
		'open-method-lexical-consumption': (
		'class Child{init(){}}class Host<T>{init(){}int consume<R>(owned R value){return 0;}}'
		'int invoke<T,R>(borrowed Host<T> host,owned R value) where R:Ownable{return host.consume<R>(move value);}'
		'int main(){var host=new Host<int>();var child=Child.init();return invoke(host,move child);}',
		'consuming Class member requires an independently heap-owned argument'),
		'open-method-use-after-consume': (
		'class Host<T>{init(){}int consume<R>(owned R value){return 0;}}'
		'int invoke<T,R>(borrowed Host<T> host,owned R value,Fn<int,borrowed R> read) where R:Ownable{'
		'host.consume<R>(move value);return read(value);}int main(){return 0;}',
		"use of moved owned value 'value'"),
		'open-method-missing-bound': (
		'class Cell<T>{T value;init(T value){this.value=value;}'
		'R ordered<R>(R value) where R:Ordered{return value;}}'
		'R invoke<T,R>(borrowed Cell<T> cell,R value){return cell.ordered<R>(value);}'
		'int main(){return 0;}', 'generic method type arguments do not satisfy the declared capability constraint'),
		'open-method-wrong-order': (
		'class Cell<T>{T value;init(T value){this.value=value;}'
		'R choose<R,S>(S spare,R value){return value;}}'
		'R invoke<T,R,S>(borrowed Cell<T> cell,R value,S spare){return cell.choose<R,S>(value,spare);}'
		'int main(){return 0;}', "expects type 'S', provided 'R'"),
		'open-method-wrong-result': (
		'class Cell<T>{T value;init(T value){this.value=value;}R choose<R>(R value){return value;}}'
		'int invoke<T,R>(borrowed Cell<T> cell,R value){return cell.choose<R>(value);}'
		'int main(){return 0;}', "expected return value of type 'int', found 'R'"),
		'open-class-member-double-move': (
		'class Cell<T>{owned T value;init(owned T value){this.value=move value;}'
		'void replace(owned T value){this.value=move value;}}'
		'void replace<T>(borrowed Cell<T> cell,owned T value) where T:Ownable{'
		'cell.replace(move value);cell.replace(move value);}int main(){return 0;}',
		"use of moved owned value 'value'"),
		'open-class-member-lexical-forwarding': (
		'class Child{init(){}}class Cell<T>{owned T value;init(owned T value){this.value=move value;}'
		'void replace(owned T value){this.value=move value;}}'
		'void replace<T>(borrowed Cell<T> cell,owned T value) where T:Ownable{cell.replace(move value);}'
		'int main(){var initial=new Child();var cell=new Cell<Child>(move initial);'
		'var next=Child.init();replace(cell,move next);return 0;}',
		'consuming Class member requires an independently heap-owned argument'),
		'open-class-member-wrong-nominal': (
		'class Child{init(){}}class Other{init(){}}'
		'class Cell<T>{owned T value;init(owned T value){this.value=move value;}'
		'void replace(owned T value){this.value=move value;}}'
		'void replace<T>(borrowed Cell<T> cell,owned T value) where T:Ownable{cell.replace(move value);}'
		'int main(){var initial=new Child();var cell=new Cell<Child>(move initial);'
		'var next=new Other();replace(cell,move next);return 0;}',
		"conflicting inferred types for generic parameter 'T': 'Child' and 'Other'"),
		'open-class-wrong-result': (open_class +
		'int wrong<T>(borrowed Cell<T> cell){return cell.read();}'
		'int main(){var cell=new Cell<int>(42);return wrong(cell);}',
		"expected return value of type 'int', found 'T'"),
		'open-class-wrong-write': (open_class +
		'void wrong<T>(borrowed Cell<T> cell){cell.item=1;}int main(){return 0;}',
		"requires exact value type 'T', found 'int'"),
		'open-class-wrong-nominal': (open_class +
		'class Other<T>{T value;init(T value){this.value=value;}}'
		'T read<T>(borrowed Cell<T> cell){return cell.value;}'
		'int main(){var cell=new Other<int>(42);return read(cell);}',
		"requires exact nominal type pattern 'Cell<T>', found 'Other<int>'"),
		'open-class-private-field': (
		'class Cell<T>{private T value;init(T value){this.value=value;}}'
		'T wrong<T>(borrowed Cell<T> cell){return cell.value;}int main(){return 0;}',
		"private field 'Cell<T>.value' is accessible only within its declaring Class"),
		'parameter-leaf-class-escape': ('// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\nclass ParameterLeafChild {\n\tint code;\n\tinit(int code) { this.code = code; }\n\tint read() { return this.code; }\n\tdeinit() { mark(this.code); }\n}\nstruct ParameterLeafStats { int count; i64 total; }\nstruct ParameterLeaves {\n\towned ParameterLeafChild child;\n\towned R first;\n\towned Other second;\n\towned int[] samples;\n\towned i64[] wide;\n}\nstruct ParameterLeafEnvelope { ParameterLeaves leaves; ParameterLeafStats stats; }\nint inspect_parameter_leaves(borrowed ParameterLeafEnvelope value) {\n\tvar alias = value.leaves.child;\n\ti64 expected = 9000000001;\n\tParameterLeafStats copied = value.stats;\n\tif (copied.total != expected || value.leaves.wide[0] != expected) { return 0; }\n\tif (value.leaves.child.code != 19) { return 0; }\n\treturn copied.count + value.leaves.child.read() + id(value.leaves.first) + other_id(value.leaves.second) + len(value.leaves.samples) + value.leaves.samples[0] + len(value.leaves.wide);\n}\nint forward_parameter_leaves(borrowed ParameterLeafEnvelope value) { return inspect_parameter_leaves(value); }\nint inspect_two_parameter_leaves(borrowed ParameterLeafEnvelope left, borrowed ParameterLeafEnvelope right) {\n\treturn inspect_parameter_leaves(left) + inspect_parameter_leaves(right);\n}\nint exercise_parameter_leaves() {\n\tvar child = new ParameterLeafChild(19);\n\tvar first = make(201);\n\tvar second = make_other(202);\n\tvar samples = new int[3];\n\tvar wide = new i64[5];\n\ti64 expected = 9000000001;\n\tsamples[0] = 11;\n\twide[0] = expected;\n\tParameterLeafEnvelope value = {leaves = {child = move child, first = move first, second = move second, samples = move samples, wide = move wide}, stats = {count = 42, total = expected}};\n\tif (inspect_parameter_leaves(value) != 483 || forward_parameter_leaves(value) != 483) { return 1; }\n\tif (inspect_two_parameter_leaves(value, value) != 966 || live() != 2) { return 2; }\n\tvar moved = move value;\n\tif (inspect_parameter_leaves(moved) != 483) { return 3; }\n\treturn 0;\n}\nint main() {\n\tint result = exercise_parameter_leaves();\n\tif (result != 0) { return result; }\n\treturn live();\n}\n', 'owning record leaf observation requires an exact bounded borrowed use; storing, copying and escape are unsupported'),
		'parameter-leaf-resource-escape': ('// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\nclass ParameterLeafChild {\n\tint code;\n\tinit(int code) { this.code = code; }\n\tint read() { return this.code; }\n\tdeinit() { mark(this.code); }\n}\nstruct ParameterLeafStats { int count; i64 total; }\nstruct ParameterLeaves {\n\towned ParameterLeafChild child;\n\towned R first;\n\towned Other second;\n\towned int[] samples;\n\towned i64[] wide;\n}\nstruct ParameterLeafEnvelope { ParameterLeaves leaves; ParameterLeafStats stats; }\nint inspect_parameter_leaves(borrowed ParameterLeafEnvelope value) {\n\tvar alias = value.leaves.first;\n\ti64 expected = 9000000001;\n\tParameterLeafStats copied = value.stats;\n\tif (copied.total != expected || value.leaves.wide[0] != expected) { return 0; }\n\tif (value.leaves.child.code != 19) { return 0; }\n\treturn copied.count + value.leaves.child.read() + id(value.leaves.first) + other_id(value.leaves.second) + len(value.leaves.samples) + value.leaves.samples[0] + len(value.leaves.wide);\n}\nint forward_parameter_leaves(borrowed ParameterLeafEnvelope value) { return inspect_parameter_leaves(value); }\nint inspect_two_parameter_leaves(borrowed ParameterLeafEnvelope left, borrowed ParameterLeafEnvelope right) {\n\treturn inspect_parameter_leaves(left) + inspect_parameter_leaves(right);\n}\nint exercise_parameter_leaves() {\n\tvar child = new ParameterLeafChild(19);\n\tvar first = make(201);\n\tvar second = make_other(202);\n\tvar samples = new int[3];\n\tvar wide = new i64[5];\n\ti64 expected = 9000000001;\n\tsamples[0] = 11;\n\twide[0] = expected;\n\tParameterLeafEnvelope value = {leaves = {child = move child, first = move first, second = move second, samples = move samples, wide = move wide}, stats = {count = 42, total = expected}};\n\tif (inspect_parameter_leaves(value) != 483 || forward_parameter_leaves(value) != 483) { return 1; }\n\tif (inspect_two_parameter_leaves(value, value) != 966 || live() != 2) { return 2; }\n\tvar moved = move value;\n\tif (inspect_parameter_leaves(moved) != 483) { return 3; }\n\treturn 0;\n}\nint main() {\n\tint result = exercise_parameter_leaves();\n\tif (result != 0) { return result; }\n\treturn live();\n}\n', 'owning record leaf observation requires an exact bounded borrowed use; storing, copying and escape are unsupported'),
		'parameter-leaf-buffer-escape': ('// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\nclass ParameterLeafChild {\n\tint code;\n\tinit(int code) { this.code = code; }\n\tint read() { return this.code; }\n\tdeinit() { mark(this.code); }\n}\nstruct ParameterLeafStats { int count; i64 total; }\nstruct ParameterLeaves {\n\towned ParameterLeafChild child;\n\towned R first;\n\towned Other second;\n\towned int[] samples;\n\towned i64[] wide;\n}\nstruct ParameterLeafEnvelope { ParameterLeaves leaves; ParameterLeafStats stats; }\nint inspect_parameter_leaves(borrowed ParameterLeafEnvelope value) {\n\tvar alias = value.leaves.samples;\n\ti64 expected = 9000000001;\n\tParameterLeafStats copied = value.stats;\n\tif (copied.total != expected || value.leaves.wide[0] != expected) { return 0; }\n\tif (value.leaves.child.code != 19) { return 0; }\n\treturn copied.count + value.leaves.child.read() + id(value.leaves.first) + other_id(value.leaves.second) + len(value.leaves.samples) + value.leaves.samples[0] + len(value.leaves.wide);\n}\nint forward_parameter_leaves(borrowed ParameterLeafEnvelope value) { return inspect_parameter_leaves(value); }\nint inspect_two_parameter_leaves(borrowed ParameterLeafEnvelope left, borrowed ParameterLeafEnvelope right) {\n\treturn inspect_parameter_leaves(left) + inspect_parameter_leaves(right);\n}\nint exercise_parameter_leaves() {\n\tvar child = new ParameterLeafChild(19);\n\tvar first = make(201);\n\tvar second = make_other(202);\n\tvar samples = new int[3];\n\tvar wide = new i64[5];\n\ti64 expected = 9000000001;\n\tsamples[0] = 11;\n\twide[0] = expected;\n\tParameterLeafEnvelope value = {leaves = {child = move child, first = move first, second = move second, samples = move samples, wide = move wide}, stats = {count = 42, total = expected}};\n\tif (inspect_parameter_leaves(value) != 483 || forward_parameter_leaves(value) != 483) { return 1; }\n\tif (inspect_two_parameter_leaves(value, value) != 966 || live() != 2) { return 2; }\n\tvar moved = move value;\n\tif (inspect_parameter_leaves(moved) != 483) { return 3; }\n\treturn 0;\n}\nint main() {\n\tint result = exercise_parameter_leaves();\n\tif (result != 0) { return result; }\n\treturn live();\n}\n', 'owning record leaf observation requires an exact bounded borrowed use; storing, copying and escape are unsupported'),
		'parameter-leaf-wrong-buffer': ('// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\nclass ParameterLeafChild {\n\tint code;\n\tinit(int code) { this.code = code; }\n\tint read() { return this.code; }\n\tdeinit() { mark(this.code); }\n}\nstruct ParameterLeafStats { int count; i64 total; }\nstruct ParameterLeaves {\n\towned ParameterLeafChild child;\n\towned R first;\n\towned Other second;\n\towned int[] samples;\n\towned i64[] wide;\n}\nstruct ParameterLeafEnvelope { ParameterLeaves leaves; ParameterLeafStats stats; }\nint inspect_parameter_leaves(borrowed ParameterLeafEnvelope value) {\n\tint invalid = inspect_wrong_buffer(value.leaves.wide);\n\ti64 expected = 9000000001;\n\tParameterLeafStats copied = value.stats;\n\tif (copied.total != expected || value.leaves.wide[0] != expected) { return 0; }\n\tif (value.leaves.child.code != 19) { return 0; }\n\treturn copied.count + value.leaves.child.read() + id(value.leaves.first) + other_id(value.leaves.second) + len(value.leaves.samples) + value.leaves.samples[0] + len(value.leaves.wide);\n}\nint forward_parameter_leaves(borrowed ParameterLeafEnvelope value) { return inspect_parameter_leaves(value); }\nint inspect_two_parameter_leaves(borrowed ParameterLeafEnvelope left, borrowed ParameterLeafEnvelope right) {\n\treturn inspect_parameter_leaves(left) + inspect_parameter_leaves(right);\n}\nint exercise_parameter_leaves() {\n\tvar child = new ParameterLeafChild(19);\n\tvar first = make(201);\n\tvar second = make_other(202);\n\tvar samples = new int[3];\n\tvar wide = new i64[5];\n\ti64 expected = 9000000001;\n\tsamples[0] = 11;\n\twide[0] = expected;\n\tParameterLeafEnvelope value = {leaves = {child = move child, first = move first, second = move second, samples = move samples, wide = move wide}, stats = {count = 42, total = expected}};\n\tif (inspect_parameter_leaves(value) != 483 || forward_parameter_leaves(value) != 483) { return 1; }\n\tif (inspect_two_parameter_leaves(value, value) != 966 || live() != 2) { return 2; }\n\tvar moved = move value;\n\tif (inspect_parameter_leaves(moved) != 483) { return 3; }\n\treturn 0;\n}\nint main() {\n\tint result = exercise_parameter_leaves();\n\tif (result != 0) { return result; }\n\treturn live();\n}\n\nint inspect_wrong_buffer(borrowed int[] value){return len(value);}\n', 'owning record leaf observation requires an exact bounded borrowed use; storing, copying and escape are unsupported'),
		'parameter-leaf-wrong-resource': ('// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\nclass ParameterLeafChild {\n\tint code;\n\tinit(int code) { this.code = code; }\n\tint read() { return this.code; }\n\tdeinit() { mark(this.code); }\n}\nstruct ParameterLeafStats { int count; i64 total; }\nstruct ParameterLeaves {\n\towned ParameterLeafChild child;\n\towned R first;\n\towned Other second;\n\towned int[] samples;\n\towned i64[] wide;\n}\nstruct ParameterLeafEnvelope { ParameterLeaves leaves; ParameterLeafStats stats; }\nint inspect_parameter_leaves(borrowed ParameterLeafEnvelope value) {\n\ti64 expected = 9000000001;\n\tParameterLeafStats copied = value.stats;\n\tif (copied.total != expected || value.leaves.wide[0] != expected) { return 0; }\n\tif (value.leaves.child.code != 19) { return 0; }\n\treturn copied.count + value.leaves.child.read() + other_id(value.leaves.first) + other_id(value.leaves.second) + len(value.leaves.samples) + value.leaves.samples[0] + len(value.leaves.wide);\n}\nint forward_parameter_leaves(borrowed ParameterLeafEnvelope value) { return inspect_parameter_leaves(value); }\nint inspect_two_parameter_leaves(borrowed ParameterLeafEnvelope left, borrowed ParameterLeafEnvelope right) {\n\treturn inspect_parameter_leaves(left) + inspect_parameter_leaves(right);\n}\nint exercise_parameter_leaves() {\n\tvar child = new ParameterLeafChild(19);\n\tvar first = make(201);\n\tvar second = make_other(202);\n\tvar samples = new int[3];\n\tvar wide = new i64[5];\n\ti64 expected = 9000000001;\n\tsamples[0] = 11;\n\twide[0] = expected;\n\tParameterLeafEnvelope value = {leaves = {child = move child, first = move first, second = move second, samples = move samples, wide = move wide}, stats = {count = 42, total = expected}};\n\tif (inspect_parameter_leaves(value) != 483 || forward_parameter_leaves(value) != 483) { return 1; }\n\tif (inspect_two_parameter_leaves(value, value) != 966 || live() != 2) { return 2; }\n\tvar moved = move value;\n\tif (inspect_parameter_leaves(moved) != 483) { return 3; }\n\treturn 0;\n}\nint main() {\n\tint result = exercise_parameter_leaves();\n\tif (result != 0) { return result; }\n\treturn live();\n}\n', 'owning record leaf observation requires an exact bounded borrowed use; storing, copying and escape are unsupported'),
		'record-getter-overlap': ('// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\nclass ParameterLeafChild {\n\tint code;\n\tinit(int code) { this.code = code; }\n\tint read() { return this.code; }\n\tdeinit() { mark(this.code); }\n}\nstruct ParameterLeafStats { int count; i64 total; }\nstruct ParameterLeaves {\n\towned ParameterLeafChild child;\n\towned R first;\n\towned Other second;\n\towned int[] samples;\n\towned i64[] wide;\n}\nstruct ParameterLeafEnvelope { int tag; ParameterLeaves leaves; ParameterLeafStats stats; }\nint inspect_parameter_leaves(borrowed ParameterLeafEnvelope value) {\n\ti64 expected = 9000000001;\n\tParameterLeafStats copied = value.stats;\n\tif (value.tag != 7 || copied.total != expected || value.leaves.wide[0] != expected) { return 0; }\n\tif (value.leaves.child.code != 19) { return 0; }\n\treturn copied.count + value.leaves.child.read() + id(value.leaves.first) + other_id(value.leaves.second) + len(value.leaves.samples) + value.leaves.samples[0] + len(value.leaves.wide);\n}\nint forward_parameter_leaves(borrowed ParameterLeafEnvelope value) { return inspect_parameter_leaves(value); }\nint inspect_two_parameter_leaves(borrowed ParameterLeafEnvelope left, borrowed ParameterLeafEnvelope right) {\n\treturn inspect_parameter_leaves(left) + inspect_parameter_leaves(right);\n}\nint tagged_parameter_leaves(borrowed ParameterLeafEnvelope value, int tag) { return inspect_parameter_leaves(value) + tag; }\nint finish_parameter_getter(int copied, owned Box<ParameterLeafEnvelope> box) { return copied; }\nint exercise_parameter_leaves() {\n\tvar child = new ParameterLeafChild(19);\n\tvar first = make(201);\n\tvar second = make_other(202);\n\tvar samples = new int[3];\n\tvar wide = new i64[5];\n\ti64 expected = 9000000001;\n\tsamples[0] = 11;\n\twide[0] = expected;\n\tParameterLeafEnvelope value = {tag = 7, leaves = {child = move child, first = move first, second = move second, samples = move samples, wide = move wide}, stats = {count = 42, total = expected}};\n\tvar box = new Box<ParameterLeafEnvelope>(move value);\n\tif (inspect_parameter_leaves(box.view) != 483 || forward_parameter_leaves(box.view) != 483) { return 1; }\n\tif (inspect_two_parameter_leaves(box.view, box.view) != 966 || live() != 2) { return 2; }\n\tif (tagged_parameter_leaves(box.view, retire_getter_root(move box)) != 488) { return 3; }\n\tif (finish_parameter_getter(box.view.stats.count, move box) != 42) { return 4; }\n\treturn 0;\n}\nint main() {\n\tint result = exercise_parameter_leaves();\n\tif (result != 0) { return result; }\n\treturn live();\n}\n\nint retire_getter_root(owned Box<ParameterLeafEnvelope> box){return 0;}\n', 'temporary owned-field borrow overlaps a possibly aliasing containing-object argument or receiver; finish the borrow before passing the object'),
		'record-getter-owning-store': ('// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\nclass ParameterLeafChild {\n\tint code;\n\tinit(int code) { this.code = code; }\n\tint read() { return this.code; }\n\tdeinit() { mark(this.code); }\n}\nstruct ParameterLeafStats { int count; i64 total; }\nstruct ParameterLeaves {\n\towned ParameterLeafChild child;\n\towned R first;\n\towned Other second;\n\towned int[] samples;\n\towned i64[] wide;\n}\nstruct ParameterLeafEnvelope { int tag; ParameterLeaves leaves; ParameterLeafStats stats; }\nint inspect_parameter_leaves(borrowed ParameterLeafEnvelope value) {\n\ti64 expected = 9000000001;\n\tParameterLeafStats copied = value.stats;\n\tif (value.tag != 7 || copied.total != expected || value.leaves.wide[0] != expected) { return 0; }\n\tif (value.leaves.child.code != 19) { return 0; }\n\treturn copied.count + value.leaves.child.read() + id(value.leaves.first) + other_id(value.leaves.second) + len(value.leaves.samples) + value.leaves.samples[0] + len(value.leaves.wide);\n}\nint forward_parameter_leaves(borrowed ParameterLeafEnvelope value) { return inspect_parameter_leaves(value); }\nint inspect_two_parameter_leaves(borrowed ParameterLeafEnvelope left, borrowed ParameterLeafEnvelope right) {\n\treturn inspect_parameter_leaves(left) + inspect_parameter_leaves(right);\n}\nint tagged_parameter_leaves(borrowed ParameterLeafEnvelope value, int tag) { return inspect_parameter_leaves(value) + tag; }\nint finish_parameter_getter(int copied, owned Box<ParameterLeafEnvelope> box) { return copied; }\nint exercise_parameter_leaves() {\n\tvar child = new ParameterLeafChild(19);\n\tvar first = make(201);\n\tvar second = make_other(202);\n\tvar samples = new int[3];\n\tvar wide = new i64[5];\n\ti64 expected = 9000000001;\n\tsamples[0] = 11;\n\twide[0] = expected;\n\tParameterLeafEnvelope value = {tag = 7, leaves = {child = move child, first = move first, second = move second, samples = move samples, wide = move wide}, stats = {count = 42, total = expected}};\n\tvar box = new Box<ParameterLeafEnvelope>(move value);\n\tParameterLeafEnvelope stolen = box.view;\n\tif (inspect_parameter_leaves(box.view) != 483 || forward_parameter_leaves(box.view) != 483) { return 1; }\n\tif (inspect_two_parameter_leaves(box.view, box.view) != 966 || live() != 2) { return 2; }\n\tif (tagged_parameter_leaves(box.view, mark(5)) != 488) { return 3; }\n\tif (finish_parameter_getter(box.view.stats.count, move box) != 42) { return 4; }\n\treturn 0;\n}\nint main() {\n\tint result = exercise_parameter_leaves();\n\tif (result != 0) { return result; }\n\treturn live();\n}\n', 'owning record copy is forbidden; use a fresh whole-local move destination'),
		'readonly-record-element-write': ('// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\nstruct ReaderBuffers { owned R handle; owned int[] first; owned int[] second; }\nstruct ReaderPayload { ReaderBuffers contents; int stamp; }\nint inspect_borrowed_payload(borrowed ReaderPayload value) {\n\tvalue.contents.first[0] = 99; return len(value.contents.first) + value.contents.second[0];\n}\nclass SlotReader {\n\tprivate owned Box<ReaderPayload>[slots] values;\n\tinit() { this.values = new Box<ReaderPayload>[slots]; }\n\tbool add(owned Box<ReaderPayload> value) {\n\t\tif (!this.values.reserve(1)) { return false; }\n\t\tthis.values.append(move value);\n\t\treturn true;\n\t}\n\tint inspect(borrowed Box<ReaderPayload> value) {\n\t\treturn inspect_borrowed_payload(value.view);\n\t}\n\tint read(int index) { return this.inspect(this.values[index]); }\n}\nint exercise_readonly_view() {\n\tvar handle = make(181);\n\tvar first = new int[3];\n\tvar second = new int[5];\n\tsecond[0] = 23;\n\tReaderPayload payload = {contents = {handle = move handle, first = move first, second = move second}, stamp = 42};\n\tvar value = new Box<ReaderPayload>(move payload);\n\tvar reader = new SlotReader();\n\tif (!reader.add(move value)) { return 1; }\n\treturn reader.read(0) - 26;\n}\nint main() {\n\tint result = exercise_readonly_view();\n\tif (result != 0) { return result; }\n\treturn live();\n}\n', 'readonly scoped inspector cannot write object fields or indirect storage'),
		'readonly-record-mutating-helper': ('// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\nstruct ReaderBuffers { owned R handle; owned int[] first; owned int[] second; }\nstruct ReaderPayload { ReaderBuffers contents; int stamp; }\nint inspect_borrowed_payload(borrowed ReaderPayload value) {\n\tint changed = mutate_parameter_samples(value.contents.first); return len(value.contents.first) + value.contents.second[0] + changed;\n}\nclass SlotReader {\n\tprivate owned Box<ReaderPayload>[slots] values;\n\tinit() { this.values = new Box<ReaderPayload>[slots]; }\n\tbool add(owned Box<ReaderPayload> value) {\n\t\tif (!this.values.reserve(1)) { return false; }\n\t\tthis.values.append(move value);\n\t\treturn true;\n\t}\n\tint inspect(borrowed Box<ReaderPayload> value) {\n\t\treturn inspect_borrowed_payload(value.view);\n\t}\n\tint read(int index) { return this.inspect(this.values[index]); }\n}\nint exercise_readonly_view() {\n\tvar handle = make(181);\n\tvar first = new int[3];\n\tvar second = new int[5];\n\tsecond[0] = 23;\n\tReaderPayload payload = {contents = {handle = move handle, first = move first, second = move second}, stamp = 42};\n\tvar value = new Box<ReaderPayload>(move payload);\n\tvar reader = new SlotReader();\n\tif (!reader.add(move value)) { return 1; }\n\treturn reader.read(0) - 26;\n}\nint main() {\n\tint result = exercise_readonly_view();\n\tif (result != 0) { return result; }\n\treturn live();\n}\n\nint mutate_parameter_samples(borrowed int[] value){value[0]=99;return 0;}\n', 'readonly scoped inspector cannot write object fields or indirect storage'),
		'borrowed-record-overlapping-move': ('class LoanChild{int code;init(){this.code=42;}}struct LoanPack{owned LoanChild child;int stamp;}int retire_pack(LoanPack value){return value.stamp;}int read_pack(borrowed LoanPack value,int tag){return value.stamp+tag;}int main(){var child=new LoanChild();LoanPack pack={child=move child,stamp=42};return read_pack(pack,retire_pack(move pack));}', 'record ownership mutation overlaps an active borrowed record argument'),
		'borrowed-record-move-before-loan': ('class LoanChild{int code;init(){this.code=42;}}struct LoanPack{owned LoanChild child;int stamp;}int retire_pack(LoanPack value){return value.stamp;}int read_pack(borrowed LoanPack value,int tag){return value.stamp+tag;}int last_pack(int tag,borrowed LoanPack value){return value.stamp+tag;}int main(){var child=new LoanChild();LoanPack pack={child=move child,stamp=42};return last_pack(retire_pack(move pack),pack);}', "use of moved owned value 'pack'"),
		'borrowed-record-loan-after-move': ('class LoanChild{int code;init(){this.code=42;}}struct LoanPack{owned LoanChild child;int stamp;}int retire_pack(LoanPack value){return value.stamp;}int read_pack(borrowed LoanPack value,int tag){return value.stamp+tag;}int main(){var child=new LoanChild();LoanPack pack={child=move child,stamp=42};var moved=move pack;return read_pack(pack,0);}', "use of moved owned value 'pack'"),
		'borrowed-record-loan-after-partial-move': ('class LoanChild{int code;init(){this.code=42;}}struct LoanPack{owned LoanChild child;int stamp;}int retire_pack(LoanPack value){return value.stamp;}int read_pack(borrowed LoanPack value,int tag){return value.stamp+tag;}int main(){var child=new LoanChild();LoanPack pack={child=move child,stamp=42};var moved=move pack.child;return read_pack(pack,0);}', "use of moved owned value 'pack.0'"),
		'borrowed-record-move-borrowed-parameter': ('class LoanChild{int code;init(){this.code=42;}}struct LoanPack{owned LoanChild child;int stamp;}int retire_pack(LoanPack value){return value.stamp;}int read_pack(borrowed LoanPack value,int tag){return value.stamp+tag;}int bad(borrowed LoanPack value){var moved=move value;return 0;}int main(){return 0;}', "move source 'value' must be an owned void* local"),
		'borrowed-record-return-borrowed-parameter': ('class LoanChild{int code;init(){this.code=42;}}struct LoanPack{owned LoanChild child;int stamp;}int retire_pack(LoanPack value){return value.stamp;}int read_pack(borrowed LoanPack value,int tag){return value.stamp+tag;}LoanPack bad(borrowed LoanPack value){return move value;}int main(){return 0;}', 'record MOVE_VALUE requires an explicit whole move of the exact owning local'),
		'borrowed-record-write-borrowed-parameter': ('class LoanChild{int code;init(){this.code=42;}}struct LoanPack{owned LoanChild child;int stamp;}int retire_pack(LoanPack value){return value.stamp;}int read_pack(borrowed LoanPack value,int tag){return value.stamp+tag;}int bad(borrowed LoanPack value){value.stamp=9;return value.stamp;}int main(){return 0;}', 'by-value struct parameter storage is read-only; copy to a local before mutation'),
		'borrowed-record-owning-leaf-take': ('class LoanChild{int code;init(){this.code=42;}}struct LoanPack{owned LoanChild child;int stamp;}int retire_pack(LoanPack value){return value.stamp;}int read_pack(borrowed LoanPack value,int tag){return value.stamp+tag;}int bad(borrowed LoanPack value){var moved=move value.child;return 0;}int main(){return 0;}', 'moving ownership out of an owned field requires a named owning record root'),
		'borrowed-record-nominal-mismatch': ('class LoanChild{int code;init(){this.code=42;}}struct LoanPack{owned LoanChild child;int stamp;}int retire_pack(LoanPack value){return value.stamp;}int read_pack(borrowed LoanPack value,int tag){return value.stamp+tag;}struct OtherPack{owned LoanChild child;int stamp;}int read_other(borrowed OtherPack value){return value.stamp;}int main(){var child=new LoanChild();LoanPack pack={child=move child,stamp=42};return read_other(pack);}', 'borrowed record requires an exact live named owner or forwarded borrowed parameter'),
		'readonly-buffer-element-write': (readonly_buffer.replace(
		'return len(value.view.contents.first) + value.view.contents.second[0];',
		'value.view.contents.first[0] = 99; return len(value.view.contents.first) + value.view.contents.second[0];'),
		'readonly scoped inspector cannot write object fields or indirect storage'),
		'readonly-buffer-slot-extraction': (readonly_buffer.replace(
		'return len(value.view.contents.first) + value.view.contents.second[0];',
		'var stolen = this.values.take(0); release stolen; return 0;'),
		'readonly scoped inspector'),
		'buffer-view-slice-escape': (buffer_types + buffer_main +
		'var alias=store.view.first;return 0;}', 'owning record leaf observation requires an exact bounded borrowed use'),
		'buffer-view-record-copy': (buffer_types + buffer_main +
		'BufferPair alias=store.view;return 0;}', 'owning record copy is forbidden'),
		'buffer-view-owned-argument': (buffer_types + buffer_main +
		'return consume_samples(store.view.first);}', "requires explicit 'move owner'"),
		'buffer-view-overlapping-transfer': (buffer_types + buffer_main +
		'return read_samples(store.view.first,retire_buffers(move store));}', 'temporary owned-field borrow overlaps'),
		'buffer-view-overlapping-replacement': (buffer_types + buffer_main +
		'return read_samples(store.view.first,replace_buffers(store));}', 'temporary owned-field borrow overlaps'),
		'buffer-view-index-invalidates': (buffer_types + buffer_main +
		'return store.view.first[retire_buffers(move store)];}', 'temporary owned-field borrow overlaps'),
		'buffer-view-wrong-element': (buffer_types + buffer_main +
		'return read_wide(store.view.first);}', 'owning record leaf observation requires an exact bounded borrowed use'),
		'owning-view-class-escape': (view_types + view_main +
		'var alias=store.view.first;return 0;}', 'owning record leaf observation requires an exact bounded borrowed use'),
		'owning-view-record-escape': (view_types + view_main +
		'ViewPair alias=store.view;return 0;}', 'owning record copy is forbidden'),
		'owning-view-overlapping-transfer': (view_types + view_main +
		'return inspect_view(store.view.first,retire_view(move store));}', 'temporary owned-field borrow overlaps'),
		'owning-view-projected-write': (view_types + view_main +
		'store.view.first.code=99;return 0;}', 'projected Class field mutation requires a complete enclosing receiver loan'),
		'owning-view-wrong-type': (view_types + 'class Different{init(){}}void read_other(borrowed Different value){}' + view_main +
		'read_other(store.view.first);return 0;}', 'owning record leaf observation requires an exact bounded borrowed use'),
		'owning-view-impure-getter': (view_types.replace('get{return this.value;}', 'get{int effect=1;return this.value;}') + view_main +
		'return store.view.stamp;}', 'borrowed property getter requires', 'syntax'),
		'closed-owner-copy': (transport_cell + 'T copy<T>(T value){return value;}'
		'int main(){var value=new Cell<int>(1);copy(value);return 0;}', 'GEN1_PLAIN_COPY'),
		'closed-owner-wrong-specialization': (transport_cell + transport_loan +
		'int main(){var value=new Cell<int>(1);return loan<Cell<bool>>(value,0);}', "expects type 'Cell<bool>', provided 'Cell<int>'"),
		'closed-owner-unmoved': (transport_cell + transport_consume +
		'int main(){var value=new Cell<int>(1);return consume(value);}', "requires explicit 'move owner'"),
		'closed-owner-overlap': (transport_cell + transport_loan + transport_consume +
		'int main(){var value=new Cell<int>(1);return loan(value,consume(move value));}', 'cannot borrow moved', 'cfg'),
		'closed-owner-moved-use': (transport_cell + transport_consume +
		'int main(){var value=new Cell<int>(1);consume(move value);return value.item;}', 'use of moved owned value', 'cfg'),
		'empty-class-construction': ('class Empty<T>{}int main(){var value=new Empty<int>();return 0;}', 'requires an explicit init constructor'),
		'projection-undefined-nominal': ('void f(){Pair p=make().field;}', "unknown type 'Pair'"),
		'open-formal-wrong-nominal': ('struct Box<T>{T value;}struct Other<T>{T value;}'
		'T f<T>(Box<T> value){return value.value;}'
		'int main(){Other<int> x={value=1};return f(x);}', 'exact nominal type pattern'),
		'open-formal-repeat-binder': ('struct Pair<A,B>{A first;B second;}'
		'T f<T>(Pair<T,T> value){return value.first;}'
		'int main(){Pair<int,bool> x={first=1,second=true};return f(x);}', "'int' and 'bool'"),
		'open-formal-fixed-nested-type': ('struct Pair<A,B>{A first;B second;}'
		'T f<T>(Pair<T,bool> value){return value.first;}'
		'int main(){Pair<int,int> x={first=1,second=2};return f(x);}', "type pattern 'bool', found 'int'"),
		'open-formal-constraint': ('struct Box<T>{T value;}'
		'T f<T>(Box<T> value) where T:Numeric{return value.value;}'
		'int main(){Box<bool> x={value=true};f(x);return 0;}', "does not satisfy capability 'Numeric'"),
		'open-formal-readonly': ('struct Box<T>{T value;}'
		'void f<T>(Box<T> value){value.value=value.value;}', 'parameter storage is read-only'),
		'open-formal-no-result-inference': ('struct Box<T>{T value;}'
		'Box<T> make<T>(){return make<T>();}'
		'int main(){Box<int> x=make();return x.value;}', "cannot infer generic type argument 'T'"),
		'open-formal-distinct-binders': ('struct Box<T>{T value;}'
		'T get<T>(Box<T> value){return value.value;}'
		'U f<T,U>(Box<T> value,U other){return get(value);}', "type 'U', found 'T'"),
		'open-formal-owner-copy': ('struct Box<T>{T value;}'
		'void f<T>(Box<T> value) where T:Ownable{}', 'requires GEN1_PLAIN_COPY'),
		'open-formal-missing-return': ('struct Box<T>{T value;}Box<T> f<T>(T value){}\n'
		'int main(){var value=f(1);return value.value;}', 'not all paths', 'cfg'),
		'projection-unknown-field': (projections.replace('store.value.part.code', 'store.value.part.missing', 1), "unknown field 'missing' in record producer"),
		'projection-wrong-nominal-subrecord': (projections.replace('ProjectionPart explicit_value =', 'OtherProjectionPart explicit_value =') + '\nstruct OtherProjectionPart { i64 wide; int code; }\n', 'exact nominal copied destination type'),
		'lexical-child-storage': (lexical.replace('var heap = new LexicalCell<int, int>(42, 42, 206);', 'var heap = LexicalCell<int, int>.init(42, 42, 206);'), 'incompatible heap and lexical'),
		'lexical-wrong-specialization': (lexical.replace('explicit_value = LexicalCell<int, bool>.init(42, true, 203)', 'explicit_value = LexicalCell<int, int>.init(42, 1, 203)'), 'construction initializer requires exact'),
		'lexical-escaping-storage': (lexical.replace('return LexicalCell<int, int>.init(value, 99, 202);', 'var local = LexicalCell<int, int>.init(value, 99, 202); return move local;'), 'callee-local'),
		'lexical-mixed-parameter': ('class Origin<T> { T value; init(T value) { this.value = value; } }\n'
		'int consume(owned Origin<int> value) { return value.value; }\n'
		'int main() { var heap = new Origin<int>(1); var local = Origin<int>.init(2); return consume(move heap) + consume(move local); }\n', 'incompatible heap and lexical'),
		'inspection-receiver-removal': (inspection.replace('if (this.marker == 7)', 'var removed = this.values.take(0); release removed; if (this.marker == 7)'), 'readonly scoped inspector'),
		'inspection-transitive-reserve': (inspection.replace('bool inspect(borrowed', 'bool mutate() { return this.values.reserve(4); }\n\tbool inspect(borrowed').replace('if (this.marker == 7)', 'if (!this.mutate()) { return false; } if (this.marker == 7)'), 'readonly scoped inspector'),
		'symbolic-consuming-unconstrained': ('int apply<T>(Fn<int,owned T> code,owned T value){return code(move value);}int main(){return 0;}', 'owned T requires explicit capability Ownable'),
		'symbolic-consuming-borrowed-target': ('class Child{init(){}}int read(borrowed Child value){return 0;}int apply<T>(Fn<int,owned T> code,owned T value) where T:Ownable{return code(move value);}int main(){var value=new Child();return apply<Child>(read,move value);}', 'function address parameter requires exact type and ownership channel identity'),
		'symbolic-consuming-wrong-nominal': ('class Child{init(){}}class Other{init(){}}int consume(owned Other value){return 0;}int apply<T>(Fn<int,owned T> code,owned T value) where T:Ownable{return code(move value);}int main(){var value=new Child();return apply<Child>(consume,move value);}', 'function address parameter requires exact type and ownership channel identity'),
		'symbolic-consuming-missing-move': ('int apply<T>(Fn<int,owned T> code,owned T value) where T:Ownable{return code(value);}int main(){return 0;}', "requires explicit 'move owner'"),
		'symbolic-consuming-borrowed-source': ('int apply<T>(Fn<int,owned T> code,borrowed T value) where T:Ownable{return code(move value);}int main(){return 0;}', 'borrowed T cannot be moved'),
		'symbolic-consuming-double-move': ('int apply<T>(Fn<int,owned T> code,owned T value) where T:Ownable{code(move value);return code(move value);}int main(){return 0;}', 'moved'),
		'symbolic-consuming-lexical-Class': ('class Child{init(){}}int consume(owned Child value){return 0;}int apply<T>(Fn<int,owned T> code,owned T value) where T:Ownable{return code(move value);}int main(){var value=Child.init();return apply<Child>(consume,move value);}', 'consuming callable Class channel requires an independently heap-owned argument'),
		'symbolic-consuming-transitive-lexical-Class': ('class Child{init(){}}int consume(owned Child value){return 0;}int apply<T>(Fn<int,owned T> code,owned T value) where T:Ownable{return code(move value);}int relay<T>(owned T value,Fn<int,owned T> code) where T:Ownable{return apply<T>(code,move value);}int main(){var value=Child.init();return relay<Child>(move value,consume);}', 'consuming callable Class channel requires an independently heap-owned argument'),
		'symbolic-callable-wrong-nominal-input': ('struct Left{int value;}struct Right{int value;}int read(Right value){return value.value;}int apply<T>(Fn<int,T> code,T value){return code(value);}int main(){Left value={value=42};return apply<Left>(read,value);}', 'function address parameter requires exact copied scalar identity'),
		'symbolic-callable-wrong-nominal-result': ('struct Left{int value;}struct Right{int value;}Right read(Left value){Right result={value=value.value};return result;}T apply<T>(Fn<T,T> code,T value){return code(value);}int main(){Left value={value=42};Left result=apply<Left>(read,value);return result.value;}', 'function address requires an exact'),
		'symbolic-callable-inference-conflict': ('int read(int value){return value;}int apply<T>(Fn<int,T> code,T value){return code(value);}int main(){return apply(read,true);}', 'conflicting inferred types'),
		'symbolic-callable-unconstrained-borrow': ('int apply<T>(Fn<int,borrowed T> code,borrowed T value){return code(value);}int main(){return 0;}', 'borrowed T requires explicit capability Ownable'),
		'symbolic-callable-owner-copy': ('int apply<T>(Fn<int,T> code,borrowed T value) where T:Ownable{return 0;}int main(){return 0;}', 'Fn parameters require'),
		'symbolic-callable-owner-result-copy': ('int apply<T>(Fn<T> code) where T:Ownable{return 0;}int main(){return 0;}', 'Fn result requires'),
		'symbolic-callable-unsupported-result': ('void* read(void* value){return value;}T apply<T>(Fn<T,T> code,T value){return code(value);}int main(){void* value=apply<void*>(read,null);return 0;}', 'specialized callable result requires'),
		'symbolic-callable-consuming-target-for-loan': ('class Child{init(){}}int consume(owned Child value){return 0;}int apply<T>(Fn<int,borrowed T> code,borrowed T value) where T:Ownable{return code(value);}int main(){var value=new Child();return apply<Child>(consume,value);}', 'function address parameter requires exact type and ownership channel identity'),
		'comparator-field-wrong-argument': (comparator_field.replace('Comparator<LookupKey>(same_lookup_key)', 'Comparator<LookupKey>(same_number)'), 'function address parameter'),
		'comparator-field-uninitialized': (comparator_field.replace('this.compare = compare;', ''), 'not definitely initialized'),
		'comparator-wrong-record-argument': (comparator.replace('Key other =', 'OtherKey other =') + other_key, 'exact nominal type'),
		'comparator-wrong-record-target': (comparator.replace('bool same_key(Key left, Key right)', 'bool same_key(OtherKey left, OtherKey right)') + other_key, 'function address parameter'),
		'borrow-store': (owner.replace('if (read(nested.view.view)',
		'var escaped = nested.view;\n\tif (read(nested.view.view)'), 'borrowed property result'),
		'receiver-moved-by-later-argument': (owner.replace('inspect(0)',
		'inspect(consume(move nested))') +
		'\nint consume(owned Box<Box<Child>> value) { return 0; }\n', 'borrow'),
		'receiver-aliased-by-later-argument': (owner.replace('inspect(0)',
		'inspect(mutate(nested))') +
		'\nint mutate(borrowed Box<Box<Child>> value) { return 0; }\n', 'overlap'),
		'wrong-closed-borrow': (owner.replace('read(nested.view.view)',
		'read(nested.view)'), 'exact temporary borrowed argument'),
		'missing-record-field': (copied.replace('this.payload = move value;', ''),
		'not definitely initialized'),
		'duplicate-record-field': (copied.replace('this.payload = move value;',
		'this.payload = move value; this.payload = move value;'), 'only once'),
		'wrong-record-nominal': (copied.replace('Cell<Stats>(input)',
		'Cell<OtherStats>(input)') +
		'\nstruct OtherStats { int bytes; i64 lines; }\n', 'nominal'),
		'method-tuple-missing-argument': (methods.replace('choose_value<int, bool>',
		'choose_value<int>'), 'explicit ordered type arguments'),
		'method-tuple-extra-argument': (methods.replace('choose_value<int, bool>',
		'choose_value<int, bool, i64>'), 'explicit ordered type arguments'),
		'method-tuple-wrong-later-argument': (methods.replace('choose_value<int, Pair>',
		'choose_value<int, OtherNote>') +
		'\nstruct OtherNote { int code; i64 total; }\n', 'nominal'),
		'method-tuple-duplicate-binder': (methods.replace('choose_value<U, V>',
		'choose_value<U, U>'), 'duplicate generic method type parameter'),
		'class-capability-constraint': (constraints.replace('new Gate<int>()',
		'new Gate<bool>()'), 'capability constraint'),
		'method-capability-constraint': (constraints.replace('add<int, bool>(20, 22, true)',
		'add<bool, bool>(true, false, true)'), 'capability constraint'),
		'method-class-parameter-constraint': (constraints.replace('class Calculator<T> where T : Numeric',
		'class Calculator<T> where T : Eq').replace('new Calculator<int>(1)',
		'new Calculator<bool>(true)').replace('increase<bool>(41, true)',
		'increase<bool>(true, true)'), 'capability constraint'),
		'unknown-class-capability': (constraints.replace('class Gate<T> where T : Numeric',
		'class Gate<T> where T : MissingCapability'), 'unknown generic capability'),
		'ownable-class-rejects-scalar': ('class Guard<T> where T : Ownable { init() {} }'
		'\nint main() { var value = new Guard<int>(); return 0; }\n', 'capability constraint'),
		'deferred-lexical-owner': (deferred.replace('var child = new Child(47);',
		'owned Child child = Child.init(47);'), 'incompatible heap and lexical storage origins'),
		'deferred-owning-cycle': ('class Link<T> { owned Link<T> next; '
		'init(owned Link<T> next) { this.next = move next; } }\n'
		'class Probe<Tag> { Tag tag; init(Tag tag) { this.tag = tag; } '
		'int force<U>() { return this.marker<Link<U>>(); } '
		'int marker<V>() { return 0; } }\n'
		'int main() { var probe = new Probe<bool>(true); return probe.force<int>(); }\n',
		'cyclic owned child composition'),
		'nested-field-receiver-move': (nested_fields.replace('outer.payload.payload.inspect(0)',
		'outer.payload.payload.inspect(consume_projection(move outer))', 1), 'borrow overlaps'),
		'nested-field-receiver-alias': (nested_fields.replace('outer.payload.payload.inspect(0)',
		'outer.payload.payload.inspect(touch(outer))', 1) +
		'\nint touch(borrowed FieldBox<FieldBox<FieldChild>> value) { return 0; }\n', 'borrow overlaps'),
		'nested-field-owner-copy': (nested_fields.replace('if (outer.payload.payload.code',
		'var escaped = outer.payload.payload; if (outer.payload.payload.code'), 'temporary borrowed argument'),
		'nested-field-private': (nested_fields.replace('\tint code;', '\tprivate int code;'), 'private field'),
		'exact-bound-scalar': (exact_witness + 'int main() { var value = new Witness<int>(); return 0; }\n',
		'concrete nongeneric native Class argument'),
		'exact-bound-record': (exact_witness + 'struct Value { int code; }\n'
		'int main() { var value = new Witness<Value>(); return 0; }\n',
		'concrete nongeneric native Class argument'),
		'exact-bound-resource': (exact_witness + 'int main() { var value = new Witness<R>(); return 0; }\n',
		'concrete nongeneric native Class argument'),
		'exact-bound-closed-generic': (exact_witness + 'class Value<U> { init() {} }\n'
		'int main() { var value = new Witness<Value<int>>(); return 0; }\n',
		'concrete nongeneric native Class argument'),
		'exact-bound-virtual-phantom': (exact_witness +
		'class Value { init() {} virtual int code() { return 42; } }\n'
		'int main() { var value = new Witness<Value>(); return 0; }\n',
		'nonpolymorphic'),
		'exact-bound-derived-phantom': (exact_witness +
		'class Value { init() {} }\n'
		'int probe() { var value = new Witness<Value>(); return 0; }\n'
		'class Child : Value { init() : base() {} }\n'
		'int main() { return probe(); }\n', 'nonpolymorphic'),
		'exact-bound-method-phantom': (bounded.replace('constrained<SecondValue>()',
		'constrained<bool>()'), 'concrete nongeneric nonpolymorphic native Class argument'),
		'exact-bound-duplicate': (exact_witness.replace('ExactHeapClass {',
		'ExactHeapClass, ExactHeapClass {') + 'int main() { return 0; }\n',
		"duplicate capability 'ExactHeapClass'", 'syntax'),
		'exact-bound-mixed-value': (exact_witness.replace('ExactHeapClass {',
		'ExactHeapClass, Eq {') + 'int main() { return 0; }\n',
		'cannot combine with value capabilities'),
		'closed-closure-raw-capture': (closure.replace('owned R second;',
		'owned R second;\n\tvoid* context;').replace('second = move second};',
		'second = move second, context = null};'), 'cannot contain unmanaged raw or typed pointers'),
		'closed-closure-wrong-nominal-code': (closure.replace(
		'int plain_apply(borrowed CallEnvironment<int, bool>',
		'int plain_apply(borrowed CallEnvironment<int, int>'),
		'closure code requires an exact nonthrowing native function'),
		'closed-closure-copy': (closure.replace('try {\n\t\tint invalid',
		'var copied = function;\n\ttry {\n\t\tint invalid'), 'cannot be copied'),
		'closed-closure-consume-during-call': (closure.replace('closure_invoke(plain, 22)',
		'closure_invoke(plain, consume_plain(move plain))') +
		'\nint consume_plain(owned Closure<CallEnvironment<int, bool>, int, int> value) { return 22; }\n',
		'forbids moving its backing'),
		'owned-async-borrowed-capture': (async_owner.replace(
		'async void analyze_input(owned TaskInput<AsyncResources>',
		'async void analyze_input(borrowed TaskInput<AsyncResources>'),
		'borrowed Class/Resource/text/pointer captures are excluded'),
		'owned-async-lexical-capture': ('class LexicalInput { init() {} }\n'
		'async void inspect_later(owned LexicalInput input) throws Error { await delay_ticks(1); }\n'
		'int main() { owned LexicalInput input = LexicalInput.init(); var task = inspect_later(move input); return 0; }\n',
		'incompatible heap and lexical'),
		'owned-async-unjoined-started': (async_owner.replace(
		'if (live() != 2) { throw new Error("cancel capture before deadline"); }',
		'if (live() != 2) { return 3; }'), 'unjoined started obligation', 'cfg'),
		'callable-record-other-definition': ('struct AppPair<A,B>{A value;B wide;}struct OtherAppPair<A,B>{A value;B wide;}'
		'int read_app(AppPair<int,i64> input){return input.value;}'
		'int main(){Fn<int,AppPair<int,i64>> code=read_app;i64 wide=9000000001;OtherAppPair<int,i64> input={value=42,wide=wide};return code(input);}',
		'equal layout is insufficient'),
		'callable-record-wrong-tuple': ('struct AppPair<A,B>{A value;B wide;}'
		'int read_app(AppPair<i64,int> input){return input.wide;}'
		'int main(){Fn<int,AppPair<int,i64>> code=read_app;return 0;}',
		'function address parameter requires exact copied scalar identity'),
		'closure-record-wrong-nominal': (closure_records +
		'int main(){var environment=new RecordEnv();var code=closure_bind(move environment,read_record);'
		'i64 wide=9000000001;OtherRecordPair value={value=42,wide=wide};return closure_invoke(code,value);}',
		'equal layout is insufficient'),
		'closure-record-wrong-signature': (closure_records +
		'int main(){var environment=new RecordEnv();owned Closure<RecordEnv,int,OtherRecordPair> code=closure_bind(move environment,read_record);return 0;}',
		'expected initializer of type'),
		'closure-channel-owner-transfer': (closure_channels + closure_binding +
		'return closure_invoke(code,input,consume_input(move input));}',
		'owner transfer overlaps an active borrowed callable argument'),
		'closure-channel-carrier-transfer': (closure_channels + closure_binding +
		'return closure_invoke(code,input,consume_closure(move code));}',
		'forbids moving its backing'),
		'closure-channel-wrong-nominal': (closure_channels + closure_binding +
		'var other=new ClosureOtherInput();return closure_invoke(code,other,0);}',
		'closure invocation argument requires its exact scalar signature type'),
		'closure-channel-copy': (closure_channels + closure_binding +
		'var alias=code;return 0;}', 'cannot be copied'),
		'closure-channel-unowned-binding': (closure_channels +
		'int main(){var environment=new ClosureEnv();Closure<ClosureEnv,int,borrowed ClosureInput,int> code=closure_bind(move environment,observe_closure);return 0;}',
		'closure_bind requires a fresh owned destination'),
		'callable-channel-duplicate-qualifier': ('int main(){Fn<int,borrowed owned int> code;return 0;}',
		'callable channel requires at most one ownership qualifier', 'syntax'),
		'callable-record-owner-missing-move': (record_callbacks +
		'int main(){' + record_callback_owner + 'Fn<int,Packet> code=consume;return code(packet);}',
		'MOVE_VALUE argument requires an explicit move of a named owning record'),
		'callable-record-owner-duplicate-move': (record_callbacks +
		'int main(){' + record_callback_owner + 'Fn<int,Packet,Packet> code=two;return code(move packet,move packet);}',
		'record MOVE_VALUE requires every field definitely live', 'cfg'),
		'callable-record-owner-wrong-nominal': (record_callbacks +
		'int main(){owned int[] data=new int[2];OtherPacket packet={data=move data,tag=42};Fn<int,Packet> code=consume;return code(move packet);}',
		'record MOVE_VALUE requires an explicit whole move of the exact owning local'),
		'callable-record-owner-after-move': (record_callbacks +
		'int main(){' + record_callback_owner + 'Fn<int,Packet> code=consume;code(move packet);return packet.tag;}',
		"cannot borrow moved owned value 'packet'", 'cfg'),
		'callable-record-owner-borrowed-source': (record_callbacks +
		'int forward(borrowed Packet packet){Fn<int,Packet> code=consume;return code(move packet);}int main(){return 0;}',
		'record MOVE_VALUE requires an explicit whole move of the exact owning local'),
		'callable-record-owner-borrowed-target': (record_callbacks +
		'int main(){Fn<int,Packet> code=observe;return 0;}',
		'function address parameter requires exact type and ownership channel identity'),
		'callable-Class-lexical': (class_callbacks +
		'int main(){var value=Child.init();Fn<int,owned Child,int> code=consume;return code(move value,0);}',
		"owned Class argument changed the parameter's resolved heap or lexical allocation origin"),
		'callable-Class-pending-borrow': (class_callbacks +
		'int main(){var value=new Child();Fn<int,owned Child,int> code=consume;return code(move value,observe(value));}',
		'owned value is already captured by an unfinished callable argument'),
		'callable-Class-pending-field': (class_callbacks +
		'int main(){var value=new Child();Fn<int,owned Child,int> code=consume;return code(move value,value.value);}',
		"use of moved owned value 'value'", 'cfg'),
		'callable-Class-wrong-target': (class_callbacks +
		'int main(){Fn<int,owned Child> code=observe;return 0;}',
		'function address parameter requires exact type and ownership channel identity'),
		'callable-Class-after-move': (class_callbacks +
		'int main(){var value=new Child();Fn<int,owned Child,int> code=consume;code(move value,0);return observe(value);}',
		"cannot borrow moved owned value 'value'", 'cfg'),
		'callable-owner-borrowed-target': (owned_callbacks +
		'int main(){Fn<int,owned R> code=borrow_callback;return 0;}',
		'function address parameter requires exact type and ownership channel identity'),
		'callable-owner-wrong-resource': (owned_callbacks +
		'int main(){var value=make_other(42);Fn<int,owned R> code=consume_callback;return code(move value);}',
		"requires exact type 'R' and its cleanup contract, found 'Other'"),
		'callable-owner-missing-move': (owned_callbacks +
		'int main(){var value=make(42);Fn<int,owned R> code=consume_callback;return code(value);}',
		"requires explicit 'move owner' or null"),
		'callable-owner-borrowed-source': (owned_callbacks +
		'int forward(borrowed R value){Fn<int,owned R> code=consume_callback;return code(move value);}int main(){return 0;}',
		'must be an owned nominal handle local or parameter'),
		'callable-owner-duplicate-move': (owned_callbacks +
		'int main(){var value=make(42);Fn<int,owned R,owned R> code=two_callbacks;return code(move value,move value);}',
		'owner transfer overlaps an already captured callable argument'),
		'callable-owner-borrow-move': (owned_callbacks +
		'int main(){var value=make(42);Fn<int,borrowed R,owned R> code=overlap_callback;return code(value,move value);}',
		'owner transfer overlaps an active borrowed callable argument'),
		'callable-owner-after-move': (owned_callbacks +
		'int main(){var value=make(42);Fn<int,owned R> code=consume_callback;code(move value);return id(value);}',
		"cannot borrow moved owned value 'value'", 'cfg'),
		'callable-owner-pending-read': (owned_callbacks +
		'int main(){var value=make(42);Fn<int,owned R,int> code=marked_callback;return code(move value,id(value));}',
		'owned value is already captured by an unfinished callable argument'),
		'callable-owner-nested-move': (owned_callbacks +
		'int main(){var value=make(42);Fn<int,owned R,int> code=marked_callback;return code(move value,consume_callback(move value));}',
		'owner transfer overlaps an already captured callable argument'),
		'callable-loan-transfer': ('class LoanTarget{int x;init(){this.x=42;}}'
		'int observe(borrowed LoanTarget value,int tag){return value.x+tag;}'
		'int consume(owned LoanTarget value){return 0;}'
		'int main(){var value=new LoanTarget();Fn<int,borrowed LoanTarget,int> code=observe;return code(value,consume(move value));}',
		'owner transfer overlaps an active borrowed callable argument'),
		'callable-loan-wrong-owner-mode': ('class LoanTarget{init(){}}'
		'int consume(owned LoanTarget value){return 0;}'
		'int main(){Fn<int,borrowed LoanTarget> code=consume;return 0;}',
		'function address parameter requires exact type and ownership channel identity'),
		'callable-loan-wrong-resource': ('int observe(borrowed R value){return id(value);}'
		'int main(){var other=make_other(213);Fn<int,borrowed R> code=observe;return code(other);}',
		'function value argument requires its exact scalar type'),
		'callable-loan-wrong-class': ('class LoanTarget{init(){}}class DifferentTarget{init(){}}'
		'int observe(borrowed LoanTarget value){return 0;}'
		'int main(){var other=new DifferentTarget();Fn<int,borrowed LoanTarget> code=observe;return code(other);}',
		'function value argument requires its exact scalar type'),
		'callable-loan-move-to-borrow': ('class LoanTarget{init(){}}'
		'int observe(borrowed LoanTarget value){return 0;}'
		'int main(){var value=new LoanTarget();Fn<int,borrowed LoanTarget> code=observe;return code(move value);}',
		'move'),
		'callable-loan-property-overlap': ('class LoanTarget{init(){}}'
		'class Holder{owned LoanTarget child;init(owned LoanTarget child){this.child=move child;}property borrowed LoanTarget view{get{return this.child;}}}'
		'int observe(borrowed LoanTarget value,int tag){return tag;}'
		'int consume(owned Holder value){return 0;}'
		'int main(){var child=new LoanTarget();var holder=new Holder(move child);Fn<int,borrowed LoanTarget,int> code=observe;return code(holder.view,consume(move holder));}',
		'borrow'),
		'callable-owner-result-wrong-nominal': ('owned R result(int tag){var value=make(tag);return move value;}'
		'int main(){Fn<owned Other,int> code=result;return 0;}',
		'function address requires an exact nonthrowing native copied-scalar signature'),
		'callable-owner-result-discard': ('owned R result(int tag){var value=make(tag);return move value;}'
		'int main(){Fn<owned R,int> code=result;code(42);return 0;}',
		'owned callable result requires a complete owned value consumer'),
		'callable-owner-result-use-after-move': ('owned R result(int tag){var value=make(tag);return move value;}'
		'int consume(owned R value){return id(value);}'
		'int main(){Fn<owned R,int> code=result;var value=code(42);consume(move value);return id(value);}',
		'cannot borrow moved owned value', 'cfg'),

		'callable-owner-class-result-lexical-target': ('class ResultChild{init(){}}'
		'owned ResultChild lexical(){return ResultChild.init();}'
		'int main(){Fn<owned ResultChild> code=lexical;return 0;}', 'heap'),
		'callable-owner-class-result-wrong-nominal': ('class ResultChild{init(){}}class ResultOther{init(){}}'
		'owned ResultChild produce(){var value=new ResultChild();return move value;}'
		'int main(){Fn<owned ResultOther> code=produce;return 0;}',
		'function address requires an exact nonthrowing native copied-scalar signature'),
		'callable-owner-class-result-use-after-move': ('class ResultChild{int code;init(){this.code=42;}}'
		'owned ResultChild produce(){var value=new ResultChild();return move value;}'
		'int consume(owned ResultChild value){return value.code;}int observe(borrowed ResultChild value){return value.code;}'
		'int main(){Fn<owned ResultChild> create=produce;var value=create();Fn<int,owned ResultChild> code=consume;code(move value);return observe(value);}',
		'moved', 'cfg'),


		'callable-record-result-wrong-nominal': ('struct ResultA{int value;}struct ResultB{int value;}'
		'ResultA produce(){ResultA result={value=42};return result;}'
		'int main(){Fn<ResultB> code=produce;return 0;}',
		'function address requires an exact nonthrowing native copied-scalar signature'),
		'callable-record-result-borrow-without-lifetime': ('struct ResultA{int value;}'
		'int main(){Fn<borrowed ResultA> code=null;return 0;}',
		'callable borrowed results require an explicit result lifetime contract'),
		'callable-record-result-use-after-move': ('struct ResultPacket{owned R value;}'
		'ResultPacket produce(int ticket){var resource=make(ticket);ResultPacket result={value=move resource};return move result;}'
		'int consume(ResultPacket value){return observe(value);}int observe(borrowed ResultPacket value){return id(value.value);}'
		'int main(){Fn<ResultPacket,int> code=produce;ResultPacket first=code(42);consume(move first);return observe(first);}',
		'moved'),


		'callable-record-loan-consuming-target': ('struct LoanPacket{owned R value;}'
		'int consume(LoanPacket value){return 0;}int main(){Fn<int,borrowed LoanPacket> code=consume;return 0;}',
		'function address parameter requires exact type and ownership channel identity'),
		'callable-record-loan-move-argument': ('struct LoanPacket{owned R value;}'
		'int observe(borrowed LoanPacket value){return 0;}'
		'int main(){var resource=make(42);LoanPacket value={value=move resource};Fn<int,borrowed LoanPacket> code=observe;return code(move value);}',
		'borrowed record requires an exact live named owner or forwarded borrowed parameter'),
		'callable-record-loan-later-move': ('struct LoanPacket{owned R value;}'
		'int observe(borrowed LoanPacket value,int tag){return tag;}int consume(LoanPacket value){return 0;}'
		'int main(){var resource=make(42);LoanPacket value={value=move resource};Fn<int,borrowed LoanPacket,int> code=observe;return code(value,consume(move value));}',
		'overlaps an active borrowed record argument'),

	}
	code_inspection = (HERE / 'scoped-code-inspection.astra').read_text()
	cases.update({
		'scoped-code-converted-write': (code_inspection.replace(
		'i64 converted = integers.replace_callback(inspect_code) as i64;',
		'i64 converted = integers.replace_callback(change_unobserved_code) as i64;'),
		'readonly scoped inspector'),
		'scoped-code-owner-write': (code_inspection.replace(
		'CodeObservation inspect_code(borrowed CodeItem item) {',
		'CodeObservation inspect_code(borrowed CodeItem item) { item.value = 99;'),
		'readonly scoped inspector'),
		'scoped-code-alternate-write': (code_inspection.replace(
		'CodeObservation inspect_other_code(borrowed CodeItem item) {',
		'CodeObservation inspect_other_code(borrowed CodeItem item) { item.value = 99;'),
		'readonly scoped inspector'),
		'owned-async-record-result-nominal': ('struct OtherAsyncTag { int generation; bool accepted; }\n' +
		record_async.replace('var first = await produce_record',
		'AsyncPair<int, OtherAsyncTag> first = await produce_record', 1),
		'struct boundary requires exact nominal type'),
		'scoped-code-transitive-write': (code_inspection.replace(
		'CodeObservation inspect_code(borrowed CodeItem item) {',
		'int change_code(borrowed CodeItem item) { item.value = 99; return 0; }'
		'CodeObservation inspect_code(borrowed CodeItem item) { change_code(item);'),
		'readonly scoped inspector'),
	})
	cases.update({
		'runtime-duplicate-namespace': ((ROOT / 'lib/astra/base/errors.astra').read_text() + '\n' +
		(ROOT / 'lib/astra/async/virtual.astra').read_text() + '\n' +
		'async runtime OtherExecutor throws AsyncError returns RunStatus; int main(){return 0;}',
		'one exact runtime nomination is supported per namespace'),
		'owned-async-borrowed-closure': ('class AsyncCaptureEnv{init(){}} async void refuse(borrowed Closure<AsyncCaptureEnv,int,int> code){} int main(){return 0;}', 'async Closure capture'),
		'owned-async-shared-handle': ('class AsyncSharedEnv{init(){}} async void refuse(owned Shared<AsyncSharedEnv> value){} int main(){return 0;}', 'Shared/Weak transfer'),
		'async-closure-threaded-context': ((ROOT / 'lib/astra/base/errors.astra').read_text() + '\n' +
		(ROOT / 'lib/astra/async/threaded.astra').read_text() + '\n' +
		'class AsyncThreadEnv{init(){}} async void refuse(owned Closure<AsyncThreadEnv,int,int> code){} int main(){return 0;}',
		'async Closure captures require an owned handle and a single-threaded executor'),
		'parameter-leaf-parenthesized-owner-read': ('struct P{owned R value;}int f(borrowed P p){return id((p).value);}',
		'owning record Resource field access and extraction are deferred'),
		'parenthesized-record-nominal-copy': ('struct A{int x;}struct B{int x;}void f(){A a={x=1};B b=(a);}',
		"struct copy requires exact nominal type 'B', found 'A'"),
		'lazy-generic-demanded-result-mismatch': ('class C<T>{init(){}lazy property T value{get{return 1;}}}int main(){var c=new C<bool>();bool value=c.value;return 0;}',
		"expected return value of type 'bool', found 'int'"),
		'exchange-expanding-instantiation': ('struct Box<T>{T value;}T expand<T>(T input){Box<T> box={value=input};Box<T> copy=expand(box);return input;}void f<T>(owned T[] a,owned T[] b,T x){swap(a,b);T y=expand(x);}void root(){var a=new int[2];var b=new int[3];f(move a,move b,1);}',
		'generic materialization limit exceeded: type-expression depth 128'),
	})
	receipt = {
		'format': 'astra-m15-declared-refusals/1',
		'compiler_sha256': sha(compiler), 'recipe_sha256': sha(Path(__file__)),
		'checks': [], 'mutants': {},
		'available_cases': list(cases), 'selected_case_filter': selected,
		'support_sources': {**{name: sha(ROOT / name) for name in [
		'lib/astra/base/errors.astra', 'lib/astra/async/virtual.astra', 'lib/astra/async/threaded.astra']},
		'tests/own-field/fixtures/resources.vapi':
		sha(ROOT / 'tests/own-field/fixtures/resources.vapi'),
		'tests/structural-generics-15/open-class-owned-formals.astra': sha(HERE / 'open-class-owned-formals.astra'),
		'lib/astra/collections/box.astra': sha(ROOT / 'lib/astra/collections/box.astra')},
	}
	if selected:
		unknown = set(selected) - cases.keys()
		assert not unknown, unknown
		cases = {name: cases[name] for name in selected}
	for name, specification in cases.items():
		source, diagnostic = specification[:2]
		phases = ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm', 'native']
		first = phases.index(specification[2] if len(specification) == 3 else 'semantics')
		path, binary = out / (name + '.astra'), out / name
		path.write_text(source)
		receipt['mutants'][name] = sha(path)
		for index, stage in enumerate(['--dump-' + phase for phase in phases[:-1]] + ['native']):
			argv = [str(compiler), *([] if stage == 'native' else [stage]),
				*(['--vapi', str(ROOT / 'tests/own-field/fixtures/resources.vapi')]
				if (name.startswith(('open-method-result-', 'nested-field-', 'closed-closure-', 'owned-async-', 'lexical-', 'readonly-buffer-', 'parameter-leaf-', 'record-getter-', 'readonly-record-', 'callable-loan-', 'callable-owner-', 'callable-record-result-', 'callable-record-loan-')) or name == 'exact-bound-resource') and stage != '--dump-syntax' else []),
				str(path), *([str(ROOT / 'lib/astra/collections/box.astra')]
				if name.startswith(('readonly-buffer-', 'record-getter-', 'readonly-record-')) and stage != '--dump-syntax' else []), *([str(ROOT / 'lib/astra/base/errors.astra')]
				if name.startswith(('generic-storage-', 'closed-closure-', 'owned-async-')) and stage != '--dump-syntax' else []),
				*([str(ROOT / 'lib/astra/async/virtual.astra')]
				if name.startswith('owned-async-') and stage != '--dump-syntax' else []),
				*(['-o', str(binary)] if stage == 'native' else [])]
			result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True,
				timeout=60, env=dict(os.environ, CCACHE_DISABLE='1'))
			rejects = index >= first
			passed = result.returncode == (1 if rejects else 0)
			if not rejects:
				passed &= not result.stderr
			else:
				passed &= diagnostic in result.stderr and not result.stdout
				passed &= all(word not in result.stderr for word in
					['internal', 'assertion', 'CRITICAL'])
			passed &= not binary.exists()
			receipt['checks'].append(dict(case=name, argv=argv, exit=result.returncode,
				diagnostic=result.stderr, passed=bool(passed)))
			(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
			assert passed, receipt['checks'][-1]
	receipt['all_passed'] = True
	(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(out / 'checks.json')


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	parser.add_argument('--case', action='append')
	args = parser.parse_args()
	main(args.compiler, args.output, args.case)
