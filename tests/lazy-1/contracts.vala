// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.LazyProperties {
private string errors() {
	return "[ExceptionRoot]class Error{readonly string text;init(string s){this.text=s;}virtual property string message{get{return this.text;}}}class DecodeError:Error{init():base(\"decode\"){}}class OtherError:Error{init():base(\"other\"){}}";
}

private SemanticResult check(string body) {
	var parsed = Parser.parse (new SourceFile.from_text ("lazy-contract", body));
	if (parsed.diagnostic != null) {
		GLib.error ("parse: %s; input: %s", parsed.diagnostic.message, body);
	}
	return SemanticAnalyzer.analyze (parsed.unit);
}

private SsaProgram build(string body) throws GLib.Error {
	var checked = check (body);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.message);
	}
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
}

private string sample() {
	return errors () + "class Sample{int input;init(int n){this.input=n;}lazy property int first throws DecodeError{get{if(this.input<0){throw new DecodeError();}return this.input;}}lazy property int second throws DecodeError{get{return this.input+1;}}property int ordinary throws DecodeError{get{return this.input;}}}class Same{int input;init(int n){this.input=n;}lazy property int first throws DecodeError{get{return this.input+2;}}}int main(){var a=new Sample(42);var b=new Sample(40);var c=new Same(40);try{return a.first+b.second-c.first;}catch(Error e){return 1;}}";
}

private void source_scope() {
	// Approved symbolic generic declaration; demanded int, cache/lifetime and
	// bool return-mismatch controls live in structural-generics-15.
	assert (check ("class C<T>{init(){}lazy property T value{get{return 1;}}}").diagnostic == null);
	assert (Parser.parse (new SourceFile.from_text ("context", "class lazy{init(){}}class Use{lazy property;init(){}lazy property(){return null;}}int lazy(int property){return property;}int main(){return lazy(42);}")).diagnostic == null);
	assert (check ("int lazy(int property){return property;}int main(){return lazy(42);}").diagnostic == null);
	foreach (string body in new string[] {
			"class C{init(){}lazy property int value{get{return 1;}set(int value){}}}",
			"struct C{int marker;lazy property int value{get{return 1;}}}",
			"class C{init(){}virtual lazy property int value{get{return 1;}}}",
			"class B{init(){}virtual property int value{get{return 1;}}}class C:B{init():base(){}override lazy property int value{get{return 1;}}}",
			"class C{init(){}lazy property string value{get{return \"x\";}}}",
			"struct S{int n;}class C{init(){}lazy property S value{get{return S();}}}",
			"enum E{A,B}class C{init(){}lazy property E value{get{return E.A;}}}",
			"class C{init(){}lazy property int[] value{get{return null;}}}",
			"class C{init(){}lazy property C value{get{return null;}}}",
			"class C{init(){}lazy property Task value{get{return null;}}}",
			"class C{init(){var n=this.value;}lazy property int value{get{return 1;}}}",
			"class C{init(){}lazy property int value{get{return 1;}}}int main(){var c=new C();c.value=2;return 1;}"
		}) {
		var result = check (body);
		assert (result.diagnostic != null);
		Test.message ("%s", result.diagnostic.message);
	}
	foreach (string body in new string[] { "lazy property int value{get{return 1;}}", "class C{init(){}lazy property int value{set(int value){}}}", "class C{init(){}static lazy property int value{get{return 1;}}}", "class C{init(){}async lazy property int value{get{return 1;}}}" }) {
		var parsed = Parser.parse (new SourceFile.from_text ("unsupported", body));
		assert (parsed.diagnostic != null || SemanticAnalyzer.analyze (parsed.unit).diagnostic != null);
	}
}

private void checked_effects() {
	string property = "class C{init(){}lazy property int value throws DecodeError{get{throw new DecodeError();}}property int ordinary throws DecodeError{get{return 42;}}}";
	foreach (string body in new string[] { "int main(){var c=new C();return c.value;}", "int main(){var c=new C();try{return c.value;}catch(OtherError e){return 1;}}", "int main(){var c=new C();try{var warm=c.value;}catch(Error e){}return c.value;}", "int f() throws OtherError{var c=new C();return c.value;}", "int main(){var c=new C();return c.ordinary;}" }) {
		var result = check (errors () + property + body);
		assert (result.diagnostic != null);
	}
	foreach (string body in new string[] { "class C{init(){}property int value throws Error{get{return 1;}set(int value){}}}", "struct C{property int value throws Error{get{return 1;}}}", "class C{init(){}virtual property int value throws Error{get{return 1;}}}", "class C:Error{init():base(\"x\"){}override property string message throws Error{get{return this.text;}}}", "class C{init(){}lazy property int value throws OtherError{get{throw new DecodeError();}}}" }) {
		assert (check (errors () + body).diagnostic != null);
	}
	try {
		var ssa = build (errors () + property + "int relay(C c) throws DecodeError{try{return c.value;}catch(Error e){throw;}}int main(){var c=new C();try{return relay(c);}catch(DecodeError e){try{return c.ordinary;}catch(DecodeError nested){return 1;}}}");
		var native = NativeAbiBuilder.build (ssa);
		LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native)).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void reservation_effects() {
	string prefix = errors () + "enum Packet{Data(owned int[] data)}int consume(owned int[] data,int n){return len(data)+n;}int ordinary() throws Error{throw new Error(\"ordinary\");}class C{init(){}lazy property int value throws Error{get{throw new Error(\"lazy\");}}}";
	try {
		foreach (string last in new string[] { "ordinary()", "c.value" }) {
			var ssa = build (prefix + "int main(){var c=new C();owned int[] outer=new int[2];owned int[] inner=new int[3];try{consume(move outer,consume(move inner," + last + "));}catch(Error e){return len(outer)+len(inner)+37;}return 1;}");
			var native = NativeAbiBuilder.build (ssa);
			LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native)).verify ();
			assert (check (prefix + "int main(){var c=new C();owned int[] outer=new int[2];owned int[] inner=new int[3];try{consume(move outer,consume(move inner,0)+" + last + ");}catch(Error e){return len(inner);}return 1;}").diagnostic != null);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void projections_and_release() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("projection", sample ()));
		assert (parsed.diagnostic == null);
		SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		CoreProgram? core = CoreBuilder.build (checked.program);
		CfgProgram? cfg = CfgBuilder.build (core);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		assert (checked.program.classes[3].properties[0].is_lazy && core.classes[3].properties[0].is_lazy && cfg.classes[3].properties[0].is_lazy && ssa.classes[3].properties[0].is_lazy);
		assert (!core.classes[3].properties[2].is_lazy && !cfg.classes[3].properties[2].is_lazy && !ssa.classes[3].properties[2].is_lazy);
		assert (core.classes[3].properties[0].getter.throws_type.name == "DecodeError" && cfg.classes[3].properties[0].getter.throws_type.name == "DecodeError" && ssa.classes[3].properties[0].getter.throws_type.name == "DecodeError");
		var semantic_ref = WeakRef (checked.program.classes[3]);
		var core_ref = WeakRef (core.classes[3]);
		var cfg_ref = WeakRef (cfg.classes[3]);
		var ssa_ref = WeakRef (ssa.classes[3]);
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		CAbiProgram? foreign = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, foreign);
		checked = null;
		core = null;
		cfg = null;
		ssa = null;
		foreign = null;
		assert (semantic_ref.get () == null && core_ref.get () == null && cfg_ref.get () == null && ssa_ref.get () == null);
		NativeAbiVerifier.verify (native);
		native = null;
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void bounded_stage_controls() {
	try {
		var checked = check ("struct S{int marker;property int value{get{return 1;}}}int main(){return 42;}");
		assert (checked.diagnostic == null);
		var core = CoreBuilder.build (checked.program);
		var cfg = CfgBuilder.build (core);
		var ssa = SsaBuilder.build (cfg);
		core.structs[0].properties[0].is_lazy = true;
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		core.structs[0].properties[0].is_lazy = false;
		CoreVerifier.verify (core);
		cfg.structs[0].properties[0].is_lazy = true;
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		cfg.structs[0].properties[0].is_lazy = false;
		CfgVerifier.verify (cfg);
		ssa.structs[0].properties[0].is_lazy = true;
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		ssa.structs[0].properties[0].is_lazy = false;
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_rejected(SsaProgram ssa, NativeAbiProgram native, CAbiProgram foreign) throws GLib.Error {
	NativeAbiVerifier.verify (native);
	bool rejected = false;
	try {
		LlvmLowering.lower (ssa, native, foreign);
	} catch (LlvmError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}

private void native_correspondence() {
	try {
		var ssa = build (sample ());
		var native = NativeAbiBuilder.build (ssa);
		var foreign = CAbiBuilder.build (ssa, native);
		var owner = native.classes[3];
		var first = owner.lazy_caches[0];
		var second = owner.lazy_caches[1];
		var wrong = new NativeLazyCache (second.span, second.name, first.class_ordinal, first.property_ordinal, first.getter_ordinal, first.cache_ordinal, first.state_member, first.value_type);
		var wrong_second = new NativeLazyCache (first.span, first.name, second.class_ordinal, second.property_ordinal, second.getter_ordinal, second.cache_ordinal, second.state_member, second.value_type);
		owner.lazy_caches[0] = wrong;
		owner.lazy_caches[1] = wrong_second;
		native.functions[first.getter_ordinal].lazy_cache = wrong;
		native.functions[second.getter_ordinal].lazy_cache = wrong_second;
		native_rejected (ssa, native, foreign);
		owner.lazy_caches[0] = first;
		owner.lazy_caches[1] = second;
		native.functions[first.getter_ordinal].lazy_cache = first;
		native.functions[second.getter_ordinal].lazy_cache = second;
		LlvmLowering.lower (ssa, native, foreign).verify ();
		var first_getter = native.functions[first.getter_ordinal];
		var second_getter = native.functions[second.getter_ordinal];
		var first_swap = new NativeLazyCache (first.span, first.name, first.class_ordinal, first.property_ordinal, second.getter_ordinal, first.cache_ordinal, first.state_member, first.value_type);
		var second_swap = new NativeLazyCache (second.span, second.name, second.class_ordinal, second.property_ordinal, first.getter_ordinal, second.cache_ordinal, second.state_member, second.value_type);
		var swapped_first = new NativeFunction (first_getter.span, first_getter.name_span, first_getter.name, first_getter.ordinal, first_getter.signature, first_getter.linkage, first_getter.declaring_type_ordinal, first_getter.method_ordinal, true, first_getter.kind, second.property_ordinal);
		var swapped_second = new NativeFunction (second_getter.span, second_getter.name_span, second_getter.name, second_getter.ordinal, second_getter.signature, second_getter.linkage, second_getter.declaring_type_ordinal, second_getter.method_ordinal, true, second_getter.kind, first.property_ordinal);
		swapped_first.claim_owner (native);
		swapped_second.claim_owner (native);
		swapped_first.lazy_cache = second_swap;
		swapped_second.lazy_cache = first_swap;
		native.functions[first.getter_ordinal] = swapped_first;
		native.functions[second.getter_ordinal] = swapped_second;
		owner.lazy_caches[0] = first_swap;
		owner.lazy_caches[1] = second_swap;
		native_rejected (ssa, native, foreign);
		native.functions[first.getter_ordinal] = first_getter;
		native.functions[second.getter_ordinal] = second_getter;
		owner.lazy_caches[0] = first;
		owner.lazy_caches[1] = second;
		LlvmLowering.lower (ssa, native, foreign).verify ();
		owner.lazy_caches.remove_index (1);
		native.functions[second.getter_ordinal].lazy_cache = null;
		native_rejected (ssa, native, foreign);
		owner.lazy_caches.add (second);
		native.functions[second.getter_ordinal].lazy_cache = second;
		LlvmLowering.lower (ssa, native, foreign).verify ();
		var bound = native.functions[first.getter_ordinal].signature.exception_plan;
		native.functions[first.getter_ordinal].signature.exception_plan = new NativeExceptionPlan (2, "OtherError", bound.root_ordinal, bound.root_name);
		native_rejected (ssa, native, foreign);
		native.functions[first.getter_ordinal].signature.exception_plan = bound;
		LlvmLowering.lower (ssa, native, foreign).verify ();
		var pointer_ssa = build (errors () + "class Pointer{init(){}lazy property void* cached{get{return null;}}property void* checked throws DecodeError{get{return null;}}}int main(){var object=new Pointer();try{void* first=object.cached;void* next=object.checked;return 42;}catch(Error error){return 1;}}");
		var pointer_native = NativeAbiBuilder.build (pointer_ssa);
		var pointer_foreign = CAbiBuilder.build (pointer_ssa, pointer_native);
		foreach (var property in pointer_ssa.classes[3].properties) {
			var signature = pointer_native.functions[property.getter.ordinal].signature;
			signature.heap_result = new NativeObjectOriginPlan (3, "Pointer", true);
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (pointer_native);
			} catch (NativeAbiError error) {
				Test.message ("%s", error.message);
				rejected = true;
			}
			assert (rejected);
			signature.heap_result = null;
			NativeAbiVerifier.verify (pointer_native);
			LlvmLowering.lower (pointer_ssa, pointer_native, pointer_foreign).verify ();
		}
		Test.message ("cached and checked copied pointer getters reject hidden heap ownership; restored");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_valid(LlvmModuleArtifact artifact) {
	char* message;
	int result = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	if (message != null) {
		if (result != 0) {
			Test.message ("%s", (string) message);
		}
		CApi.dispose_message (message);
	}
	assert (result == 0);
}

private void physical_rejected(LlvmModuleArtifact artifact) {
	generic_valid (artifact);
	bool rejected = false;
	try {
		artifact.verify ();
	} catch (LlvmError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}

private bool lazy_function(CApi.ValueRef instruction) {
	if ((void*) CApi.is_instruction (instruction) == null) {
		return false;
	}
	size_t length;
	unowned string name = CApi.value_name (CApi.block_parent (CApi.instruction_parent (instruction)), out length);
	return name == "astra.propget.class.3.0" || name == "astra.propget.class.3.1";
}

private void physical_associations() {
	try {
		var ssa = build (sample ());
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		artifact.verify ();
		int addresses = 0;
		int values = 0;
		int calls = 0;
		int branches = 0;
		int effects = 0;
		foreach (var binding in artifact.class_addresses) {
			var instruction = binding.instruction;
			if (!lazy_function (instruction)) {
				continue;
			}
			var original = CApi.operand (instruction, 0);
			CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (original)));
			physical_rejected (artifact);
			CApi.set_operand (instruction, 0, original);
			artifact.verify ();
			uint last = CApi.operand_count (instruction) - 1;
			var member = CApi.operand (instruction, last);
			uint64 index = CApi.const_int_zext (member);
			CApi.set_operand (instruction, last, CApi.const_int (CApi.type_of (member), index >= 3 ? index - 2 : index + 2, 0));
			physical_rejected (artifact);
			CApi.set_operand (instruction, last, member);
			artifact.verify ();
			addresses += 2;
		}
		foreach (var binding in artifact.class_values) {
			var instruction = binding.instruction;
			if (!lazy_function (instruction)) {
				continue;
			}
			var opcode = CApi.opcode (instruction);
			if (opcode == CApi.Opcode.ICMP || opcode == CApi.Opcode.STORE || opcode == CApi.Opcode.RET) {
				uint position = opcode == CApi.Opcode.ICMP ? 1 : 0;
				var original = CApi.operand (instruction, position);
				var alternate = CApi.const_null (CApi.type_of (original));
				if ((void*) original == (void*) alternate) {
					alternate = opcode == CApi.Opcode.STORE ? CApi.const_int (CApi.type_of (original), 2, 0) : original;
				}
				if ((void*) original != (void*) alternate) {
					CApi.set_operand (instruction, position, alternate);
					physical_rejected (artifact);
					CApi.set_operand (instruction, position, original);
					artifact.verify ();
					values++;
				}
			}
			if (opcode == CApi.Opcode.LOAD || opcode == CApi.Opcode.STORE) {
				CApi.set_volatile (instruction, 1);
				physical_rejected (artifact);
				CApi.set_volatile (instruction, 0);
				artifact.verify ();
				uint alignment = CApi.get_alignment (instruction);
				CApi.set_alignment (instruction, 2);
				physical_rejected (artifact);
				CApi.set_alignment (instruction, alignment);
				artifact.verify ();
				effects += 2;
			}
		}
		foreach (var binding in artifact.class_calls) {
			var instruction = binding.instruction;
			if (!lazy_function (instruction) || CApi.argument_count (instruction) == 0) {
				continue;
			}
			var original = CApi.operand (instruction, 0);
			CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (original)));
			physical_rejected (artifact);
			CApi.set_operand (instruction, 0, original);
			artifact.verify ();
			CApi.set_instruction_call_conv (instruction, CApi.CallConv.C);
			physical_rejected (artifact);
			CApi.set_instruction_call_conv (instruction, LlvmLowering.CALL_CONVENTION);
			artifact.verify ();
			var target = CApi.called_value (instruction);
			var gate = CApi.block_parent (CApi.instruction_parent (instruction));
			CApi.set_operand (instruction, CApi.argument_count (instruction), gate);
			physical_rejected (artifact);
			CApi.set_operand (instruction, CApi.argument_count (instruction), target);
			artifact.verify ();
			calls += 3;
		}
		foreach (var binding in artifact.class_branches) {
			var instruction = binding.instruction;
			if (!lazy_function (instruction)) {
				continue;
			}
			var yes = CApi.successor (instruction, 0);
			var no = CApi.successor (instruction, 1);
			CApi.set_successor (instruction, 0, no);
			CApi.set_successor (instruction, 1, yes);
			physical_rejected (artifact);
			CApi.set_successor (instruction, 0, yes);
			CApi.set_successor (instruction, 1, no);
			artifact.verify ();
			branches++;
		}
		bool exchanged = false;
		foreach (var call in artifact.class_calls) {
			size_t length;
			if (CApi.value_name (CApi.called_value (call.instruction), out length) != "astra.propget.class.3.0" || lazy_function (call.instruction)) {
				continue;
			}
			foreach (var address in artifact.class_addresses) {
				if ((void*) CApi.is_instruction (address.instruction) == null) {
					continue;
				}
				var other = CApi.operand (address.instruction, 0);
				if (CApi.value_name (other, out length) != "object1.heap.base") {
					continue;
				}
				var original = CApi.operand (call.instruction, 0);
				assert ((void*) original != (void*) other);
				CApi.set_operand (call.instruction, 0, other);
				physical_rejected (artifact);
				CApi.set_operand (call.instruction, 0, original);
				artifact.verify ();
				exchanged = true;
				break;
			}
			if (exchanged) {
				break;
			}
		}
		assert (exchanged);
		Test.message ("other live same-class receiver: generic-valid rejected and restored with unchanged cache/effect counts");
		assert (addresses >= 8 && values >= 12 && calls >= 6 && branches >= 6 && effects >= 24);
		Test.message ("generic-valid rejected/restored associations: addresses=%d values=%d calls=%d branches=%d effects=%d", addresses, values, calls, branches, effects);
		uint kind = CApi.enum_attribute_kind ("memory", 6);
		assert (kind != 0);
		foreach (string name in new string[] { "astra.propget.class.3.0", "astra.lazy.body.3.0" }) {
			var function = CApi.named_function (artifact.module, name);
			CApi.add_attribute (function, uint.MAX, CApi.create_enum_attribute (artifact.context, kind, 0));
			physical_rejected (artifact);
			CApi.remove_enum_attribute (function, uint.MAX, kind);
			artifact.verify ();
		}
		Test.message ("false memory(none) on gate and initializer: generic-valid rejected/restored");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void physical_sequence() {
	try {
		var ssa = build (sample ());
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		var builder = CApi.create_builder_in_context (artifact.context);
		int stores = 0;
		int reorder = 0;
		int slots = 0;
		foreach (var binding in artifact.class_values) {
			var instruction = binding.instruction;
			if (CApi.opcode (instruction) != CApi.Opcode.STORE || (void*) CApi.is_constant_int (CApi.operand (instruction, 0)) == null || CApi.get_alignment (instruction) != 1) {
				continue;
			}
			var next = CApi.next_instruction (instruction);
			if (lazy_function (instruction)) {
				var entry = CApi.entry_block (CApi.block_parent (CApi.instruction_parent (instruction)));
				var guarded = CApi.next_instruction (CApi.next_instruction (CApi.first_instruction (entry)));
				CApi.remove_instruction (instruction);
				CApi.position_builder_before (builder, guarded);
				CApi.insert_instruction (builder, instruction);
				physical_rejected (artifact);
				CApi.remove_instruction (instruction);
				CApi.position_builder_before (builder, next);
				CApi.insert_instruction (builder, instruction);
				artifact.verify ();
				stores++;
			} else {
				var original = CApi.operand (instruction, 0);
				CApi.set_operand (instruction, 0, CApi.const_int (CApi.type_of (original), CApi.const_int_zext (original) == 0 ? 1 : 0, 0));
				physical_rejected (artifact);
				CApi.set_operand (instruction, 0, original);
				artifact.verify ();
				stores++;
			}
			if (lazy_function (instruction) && (void*) CApi.is_constant_int (CApi.operand (instruction, 0)) != null) {
				var first = CApi.first_instruction (CApi.instruction_parent (instruction));
				if ((void*) first == (void*) instruction && CApi.block_name (CApi.instruction_parent (instruction)) == "lazy.initialize") {
					first = CApi.next_instruction (CApi.next_instruction (next));
				}
				if ((void*) first != (void*) instruction) {
					CApi.remove_instruction (instruction);
					CApi.position_builder_before (builder, first);
					CApi.insert_instruction (builder, instruction);
					physical_rejected (artifact);
					CApi.remove_instruction (instruction);
					CApi.position_builder_before (builder, next);
					CApi.insert_instruction (builder, instruction);
					artifact.verify ();
					reorder++;
				}
			}
		}
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.ALLOCA || !lazy_function (instruction)) {
						continue;
					}
					var count = CApi.operand (instruction, 0);
					CApi.set_operand (instruction, 0, CApi.const_int (CApi.type_of (count), 0, 0));
					physical_rejected (artifact);
					CApi.set_operand (instruction, 0, count);
					artifact.verify ();
					slots++;
				}
			}
		}
		var plain_ssa = build ("class Plain{init(){}lazy property int value{get{return 42;}}}int main(){var object=new Plain();return object.value;}");
		var plain_native = NativeAbiBuilder.build (plain_ssa);
		assert (plain_native.abi_version != NativeAbiVersion.NATIVE_EXCEPTIONS_V14);
		var plain = LlvmLowering.lower (plain_ssa, plain_native, CAbiBuilder.build (plain_ssa, plain_native));
		var plain_builder = CApi.create_builder_in_context (plain.context);
		bool construction = false;
		foreach (var binding in plain.class_values) {
			var instruction = binding.instruction;
			if (CApi.opcode (instruction) != CApi.Opcode.STORE || (void*) CApi.is_constant_int (CApi.operand (instruction, 0)) == null || CApi.const_int_zext (CApi.operand (instruction, 0)) != 0) {
				continue;
			}
			var next = CApi.next_instruction (instruction);
			foreach (var call in plain.class_calls) {
				size_t length;
				if (CApi.value_name (CApi.called_value (call.instruction), out length) != "astra.propget.class.0.0") {
					continue;
				}
				var after = CApi.next_instruction (call.instruction);
				assert ((void*) after != null);
				CApi.remove_instruction (instruction);
				CApi.position_builder_before (plain_builder, after);
				CApi.insert_instruction (plain_builder, instruction);
				physical_rejected (plain);
				CApi.remove_instruction (instruction);
				CApi.position_builder_before (plain_builder, next);
				CApi.insert_instruction (plain_builder, instruction);
				plain.verify ();
				construction = true;
				break;
			}
			break;
		}
		CApi.dispose_builder (plain_builder);
		assert (construction);
		Test.message ("generic-valid plain lazy construction Empty after first read: rejected and restored without exception-profile coverage");
		CApi.dispose_builder (builder);
		assert (stores >= 10 && reorder >= 4 && slots == 2);
		Test.message ("generic-valid wrong construction Empty or unguarded initialization/publication/reset=%d wrong order=%d wrong private extent=%d; restored", stores, reorder, slots);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/lazy-1/source/context-and-bounded-scope", source_scope);
	Test.add_func ("/lazy-1/source/static-checked-effects", checked_effects);
	Test.add_func ("/lazy-1/source/pending-versus-committed-reservations", reservation_effects);
	Test.add_func ("/lazy-1/proof/projection-and-predecessor-release", projections_and_release);
	Test.add_func ("/lazy-1/proof/bounded-core-cfg-ssa-restored-controls", bounded_stage_controls);
	Test.add_func ("/lazy-1/proof/independent-valid-wrong-native-plans", native_correspondence);
	Test.add_func ("/lazy-1/proof/generic-valid-wrong-physical-associations", physical_associations);
	Test.add_func ("/lazy-1/proof/generic-valid-missing-and-reordered-transitions", physical_sequence);
	return Test.run ();
}

}
