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
namespace Astra.Tests.NativeExceptions {
private string declarations() {
	return "[ExceptionRoot]class Error{readonly string text;init(string s){this.text=s;}virtual property string message{get{return this.text;}}}class RuntimeError:Error{init(string s):base(s){}}class DecodeError:RuntimeError{init(string s):base(s){}}";
}
private SsaProgram build(string body) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("exceptions", declarations () + body));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.message);
	}
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
}
private string slice() {
	return "int fail() throws DecodeError{throw new DecodeError(\"x\");}int main(){try{fail();}catch(Error e){return 1;}return 42;}";
}
private void checked_bounds() {
	try {
		var ssa = build ("void leaf() throws DecodeError{throw new DecodeError(\"x\");}void relay() throws DecodeError{try{leaf();}catch(Error e){throw;}}int main(){try{relay();}catch(DecodeError e){return 42;}return 1;}");
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
	foreach (string body in new string[] { "void f(){throw new DecodeError(\"x\");}", "void f() throws DecodeError{throw new RuntimeError(\"x\");}", "void f() throws Error{}int main(){try{f();}catch(DecodeError e){}return 0;}", "int main(){try{throw new DecodeError(\"x\");}catch(Error e){}catch(DecodeError e){}return 0;}", "int main(){throw;return 0;}", "int main(){try{throw new DecodeError(\"x\");}catch(Error e){throw e;}return 0;}", "int main(){owned DecodeError e=DecodeError.init(\"x\");throw move e;return 0;}", "int main(){var view=\"x\";try{throw new Error(\"x\");}catch(Error e){view=e.message;}return view.byte_length;}", "void f() throws Error{var error=new Error(\"x\");var view=error.message;throw move error;}" }) {
		var parsed = Parser.parse (new SourceFile.from_text ("negative", declarations () + body));
		assert (parsed.diagnostic == null);
		assert (SemanticAnalyzer.analyze (parsed.unit).diagnostic != null);
	}
}
private void getter_negatives() {
	foreach (string body in new string[] {
			"class Bad:Error{init():base(\"x\"){}override property string message{get{var error=new Error(\"x\");return error.message;}}}",
			"extern(C) void output();class Bad:Error{init():base(\"x\"){}override property string message{get{output();return this.text;}}}",
			"string helper(){return \"x\";}class Bad:Error{init():base(\"x\"){}override property string message{get{return helper();}}}",
			"class Bad:Error{int state;init():base(\"x\"){this.state=1;}override property string message{get{if(this.state==1){return \"x\";}return \"y\";}}}",
			"class Bad:Error{init():base(\"x\"){}override property string message{get{return this.message;}}}",
			"class Bad:Error{init():base(\"x\"){}override property string message{get{return this.text;}set(string value){}}}",
			"class Base{init(){}virtual int run() throws DecodeError{return 1;}}class Child:Base{init():base(){}override int run() throws Error{return 1;}}"
		}) {
		var parsed = Parser.parse (new SourceFile.from_text ("getter-negative", declarations () + body));
		assert (parsed.diagnostic == null);
		var result = SemanticAnalyzer.analyze (parsed.unit);
		assert (result.diagnostic != null);
		Test.message ("%s", result.diagnostic.message);
	}
}
private void success_guard() {
	try {
		var ssa = build (slice ());
		SsaVerifier.verify (ssa);
		SsaBlock? source = null;
		SsaBlock? failure = null;
		SsaCallSuccess? success = null;
		int position = -1;
		foreach (var block in ssa.functions[1].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] is SsaCallSuccess) {
					source = block;
					position = i;
					success = (SsaCallSuccess) block.instructions[i];
				}
			}
			var branch = block.terminator as SsaConditionalBranch;
			if (branch != null) {
				foreach (var instruction in block.instructions) {
					if (instruction is SsaCallInstruction) {
						failure = branch.false_edge.target;
					}
				}
			}
		}
		assert (source != null && success != null && failure != null);
		source.instructions.remove_index (position);
		failure.instructions.insert (0, success);
		bool rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("success load");
		}
		assert (rejected);
		failure.instructions.remove_index (0);
		source.instructions.insert (position, success);
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void catch_guard() {
	try {
		var ssa = build (slice ());
		SsaVerifier.verify (ssa);
		bool tested = false;
		foreach (var block in ssa.functions[1].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var caught = block.instructions[i] as SsaCatchBorrow;
				if (caught == null) {
					continue;
				}
				block.instructions[i] = new SsaCatchBorrow (caught.span, new SsaNullPointerConstant (caught.span, caught.exception.semantic_type), (ClassType) caught.result.semantic_type, caught.result.ordinal);
				bool rejected = false;
				try {
					SsaVerifier.verify (ssa);
				} catch (SsaError error) {
					Test.message ("%s", error.message);
					rejected = error.message.contains ("exact guarded borrowed binding");
				}
				assert (rejected);
				block.instructions[i] = caught;
				SsaVerifier.verify (ssa);
				tested = true;
			}
		}
		assert (tested);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void class_correspondence() {
	try {
		var ssa = build ("class OtherRuntimeError:Error{init(string s):base(s){}}" + slice ());
		var native = NativeAbiBuilder.build (ssa);
		var foreign = CAbiBuilder.build (ssa, native);
		var saved = native.classes[1];
		var other = native.classes[3];
		native.classes[1] = new NativeClassPlan (other.span, other.name, saved.ordinal, other.parent_ordinal, saved.destructor_ordinal, other.polymorphic, other.exception_root, other.fields, other.virtual_targets);
		NativeAbiVerifier.verify (native);
		bool rejected = false;
		try {
			LlvmLowering.lower (ssa, native, foreign);
		} catch (LlvmError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("class correspondence");
		}
		assert (rejected);
		native.classes[1] = saved;
		LlvmLowering.lower (ssa, native, foreign).verify ();
		saved.parent_ordinal = other.ordinal;
		NativeAbiVerifier.verify (native);
		rejected = false;
		try {
			LlvmLowering.lower (ssa, native, foreign);
		} catch (LlvmError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("class correspondence");
		}
		assert (rejected);
		saved.parent_ordinal = 0;
		NativeAbiVerifier.verify (native);
		LlvmLowering.lower (ssa, native, foreign).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_contracts() {
	try {
		var ssa = build ("class OtherRuntimeError:Error{init(string s):base(s){}}" + slice ());
		var native = NativeAbiBuilder.build (ssa);
		var foreign = CAbiBuilder.build (ssa, native);
		var prior = native.functions[0].signature.exception_plan;
		var other = native.classes[3];
		native.functions[0].signature.exception_plan = new NativeExceptionPlan (other.ordinal, other.name, prior.root_ordinal, prior.root_name);
		NativeAbiVerifier.verify (native);
		bool rejected = false;
		try {
			LlvmLowering.lower (ssa, native, foreign);
		} catch (LlvmError error) {
			rejected = error.message.contains ("declared class bound correspondence");
		}
		assert (rejected);
		native.functions[0].signature.exception_plan = prior;
		LlvmLowering.lower (ssa, native, foreign).verify ();
		int ordinal = ssa.classes[0].properties[0].getter.ordinal;
		var saved = native.functions[ordinal];
		var signature = new NativeSignature (saved.signature.abi_version, saved.signature.parameters, new NativeResult.typed (new NativeTextType (NativeTextContract.STATIC_TEXT)), saved.signature.receiver);
		var wrong = new NativeFunction (saved.span, saved.name_span, saved.name, saved.ordinal, signature, saved.linkage, saved.declaring_type_ordinal, saved.method_ordinal, saved.declaring_type_is_class, saved.kind, saved.property_ordinal);
		wrong.claim_owner (native);
		native.functions[ordinal] = wrong;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("text result");
		}
		assert (rejected);
		native.functions[ordinal] = saved;
		NativeAbiVerifier.verify (native);
		LlvmLowering.lower (ssa, native, foreign).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void exhaustive_bound() {
	try {
		var ssa = build ("int fail() throws DecodeError{throw new DecodeError(\"x\");}int main(){try{fail();}catch(DecodeError e){return 42;}return 1;}");
		SsaVerifier.verify (ssa);
		var saved = ssa.functions[0].throws_type;
		ssa.functions[0].throws_type = (ClassType) ssa.classes[0].semantic_type;
		bool rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("exception exhaustion") && error.message.contains ("open checked exception bound");
		}
		assert (rejected);
		ssa.functions[0].throws_type = saved;
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void argument_abort() {
	try {
		var ssa = build ("int fail() throws Error{throw new Error(\"later\");}int consume(owned int[] data,int n){return len(data)+n;}int main(){owned int[] data=new int[2];try{consume(move data,fail());}catch(Error e){return len(data)+40;}return 1;}");
		SsaVerifier.verify (ssa);
		SsaBlock? source = null;
		SsaOwnedArgumentAbort? aborted = null;
		int position = -1;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					if (block.instructions[i] is SsaOwnedArgumentAbort) {
						source = block;
						position = i;
						aborted = (SsaOwnedArgumentAbort) block.instructions[i];
					}
				}
			}
		}
		assert (source != null && aborted != null);
		source.instructions.remove_index (position);
		bool rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("pending transfer reaches an exit");
		}
		assert (rejected);
		source.instructions.insert (position, aborted);
		SsaVerifier.verify (ssa);
		source.instructions.insert (position + 1, new SsaOwnedArgumentAbort (aborted.span, aborted.reservation));
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = error.message.contains ("already aborted");
		}
		assert (rejected);
		source.instructions.remove_index (position + 1);
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void generic_valid(LlvmModuleArtifact artifact) {
	char* message;
	int result = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	if (message != null) {
		if (result != 0) {
			Test.message ("LLVM structural rejection: %s", (string) message);
		}
		CApi.dispose_message (message);
	}
	assert (result == 0);
}
private void llvm_correspondence() {
	try {
		SsaProgram? ssa = build (slice ());
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		CAbiProgram? foreign = CAbiBuilder.build (ssa, native);
		var predecessor = WeakRef (ssa.classes[0]);
		var artifact = LlvmLowering.lower (ssa, native, foreign);
		ssa = null;
		native = null;
		foreign = null;
		assert (predecessor.get () == null);
		artifact.verify ();
		generic_valid (artifact);
		assert (artifact.class_layouts.length >= 3);
		var layout = artifact.class_layouts[0];
		int count = (int) CApi.count_struct_element_types (layout.type);
		var fields = new CApi.TypeRef[count];
		for (int f = 0; f < count; f++) {
			fields[f] = CApi.struct_get_type_at_index (layout.type, f);
		}
		var saved_type = fields[0];
		fields[0] = CApi.int_type_in_context (artifact.context, 64);
		CApi.struct_set_body (layout.type, fields, fields.length, 0);
		generic_valid (artifact);
		bool layout_rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError error) {
			layout_rejected = error.message.contains ("class layout");
		}
		assert (layout_rejected);
		fields[0] = saved_type;
		CApi.struct_set_body (layout.type, fields, fields.length, 0);
		artifact.verify ();
		assert (artifact.class_globals.length >= 5 && artifact.class_functions.length > 0);
		foreach (var binding in artifact.class_globals) {
			var initializer = CApi.get_initializer (binding.value);
			CApi.set_global_constant (binding.value, 0);
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = error.message.contains ("immutable publication");
			}
			assert (rejected);
			CApi.set_global_constant (binding.value, 1);
			CApi.set_initializer (binding.value, initializer);
			artifact.verify ();
		}
		int checked_calls = 0;
		foreach (var binding in artifact.class_functions) {
			for (var block = CApi.first_block (binding.value); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.instruction_call_conv (instruction) != LlvmLowering.CALL_CONVENTION) {
						continue;
					}
					CApi.set_instruction_call_conv (instruction, CApi.CallConv.C);
					generic_valid (artifact);
					bool rejected = false;
					try {
						artifact.verify ();
					} catch (LlvmError error) {
						rejected = error.message.contains ("call convention");
					}
					assert (rejected);
					CApi.set_instruction_call_conv (instruction, LlvmLowering.CALL_CONVENTION);
					artifact.verify ();
					checked_calls++;
				}
			}
		}
		assert (checked_calls >= 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void heap_owner_forgeries() {
	try {
		var ssa = build ("owned Error make() throws Error{var e=new DecodeError(\"x\");return move e;}owned Error forward() throws Error{return make();}int consume(owned Error e){return 42;}int main(){try{var a=forward();var b=make();release a;return consume(move b);}catch(Error e){return 1;}}");
		SsaVerifier.verify (ssa);
		bool acquired_tested = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var event = block.instructions[i] as SsaHeapOwnerEvent;
					if (event == null || event.action != SsaHeapOwnerAction.ACQUIRE) {
						continue;
					}
					block.instructions.insert (i + 1, new SsaHeapOwnerEvent (event.span, event.owner, event.action, event.value));
					bool rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						Test.message ("%s", error.message);
						rejected = error.message.contains ("every control edge");
					}
					assert (rejected);
					block.instructions.remove_index (i + 1);
					SsaVerifier.verify (ssa);
					block.instructions.remove_index (i);
					rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						rejected = error.message.contains ("every control edge");
					}
					assert (rejected);
					block.instructions.insert (i, event);
					SsaVerifier.verify (ssa);
					acquired_tested = true;
					break;
				}
				if (acquired_tested) {
					break;
				}
			}
			if (acquired_tested) {
				break;
			}
		}
		assert (acquired_tested);
		bool tested = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var event = block.instructions[i] as SsaHeapOwnerEvent;
					if (event == null || event.owner == null || !(event.effect is SsaCleanupInstruction)) {
						continue;
					}
					var cleanup = (SsaCleanupInstruction) event.effect;
					block.instructions.insert (i + 1, new SsaCleanupInstruction (cleanup.span, cleanup.value, cleanup.cleanup));
					bool rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						Test.message ("%s", error.message);
						rejected = error.message.contains ("unassociated or duplicate cleanup");
					}
					assert (rejected);
					block.instructions.remove_index (i + 1);
					SsaVerifier.verify (ssa);
					block.instructions.remove_index (i);
					rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						rejected = error.message.contains ("unassociated or duplicate cleanup");
					}
					assert (rejected);
					block.instructions.insert (i, event);
					SsaVerifier.verify (ssa);
					block.instructions[i] = new SsaHeapOwnerEvent (event.span, event.owner, event.action, new SsaNullPointerConstant (event.span, event.value.semantic_type), event.effect);
					rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						Test.message ("%s", error.message);
						rejected = error.message.contains ("original transfer/cleanup operand");
					}
					assert (rejected);
					block.instructions[i] = event;
					SsaVerifier.verify (ssa);
					tested = true;
					break;
				}
				if (tested) {
					break;
				}
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void nested_reservation_forgeries() {
	try {
		var ssa = build ("int fail() throws Error{throw new Error(\"x\");}int consume(owned int[] data,int marker){return len(data)+marker;}int main(){owned int[] outer=new int[2];owned int[] inner=new int[3];try{consume(move outer,consume(move inner,fail()));}catch(Error error){return len(outer)+len(inner)+37;}return 1;}");
		SsaVerifier.verify (ssa);
		var reservations = new GenericArray<SsaOwnedArgumentReservation> ();
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var reservation = instruction as SsaOwnedArgumentReservation;
					if (reservation != null) {
						reservations.add (reservation);
					}
				}
			}
		}
		assert (reservations.length == 2 && reservations[0].consumer != reservations[1].consumer);
		var saved = reservations[0].consumer;
		reservations[0].consumer = reservations[1].consumer;
		bool rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("exact reservation") || error.message.contains ("exact captured owner");
		}
		assert (rejected);
		reservations[0].consumer = saved;
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void getter_and_export_contracts() {
	try {
		var ssa = build ("void side_effect(){}int fail() throws Error{throw new Error(\"x\");}export(C) int adapter(){try{return fail();}catch(Error error){return 42;}}int other(){return 42;}int main(){return adapter();}");
		SsaVerifier.verify (ssa);
		var getter = ssa.classes[0].properties[0].getter;
		getter.entry.instructions.insert (0, new SsaCallInstruction (getter.span, null, -1, ssa.functions[0], new GenericArray<SsaValue> ()));
		bool rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("without effects");
		}
		assert (rejected);
		getter.entry.instructions.remove_index (0);
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var foreign = CAbiBuilder.build (ssa, native);
		var saved = foreign.exports[0];
		var wrong = new CAbiExport (saved.span, saved.name_span, saved.external_symbol, saved.ordinal, saved.signature, 3);
		wrong.claim_owner (foreign);
		foreign.exports[0] = wrong;
		CAbiVerifier.verify (foreign);
		rejected = false;
		try {
			LlvmLowering.lower (ssa, native, foreign);
		} catch (LlvmError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("exact native function ordinal");
		}
		assert (rejected);
		foreign.exports[0] = saved;
		var artifact = LlvmLowering.lower (ssa, native, foreign);
		artifact.verify ();
		assert (artifact.c_exports.length == 1);
		var binding = artifact.c_exports[0];
		var original = CApi.called_value (binding.call);
		var other = CApi.named_function (artifact.module, "astra.fn.3");
		assert ((void*) other != null && (void*) CApi.global_value_type (other) == (void*) CApi.called_function_type (binding.call));
		CApi.set_operand (binding.call, CApi.argument_count (binding.call), other);
		generic_valid (artifact);
		rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("exact internal fastcc target");
		}
		assert (rejected);
		CApi.set_operand (binding.call, CApi.argument_count (binding.call), original);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void inherited_getter_authority() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("inherited-getter", declarations () + "class Inherited:DecodeError{init(string text):base(text){}override property string message{get{return this.text;}}}class Other{readonly string text;init(string text){this.text=text;}}int main(){var error=new Inherited(\"inherited\");if(error.message==\"inherited\"){return 42;}return 1;}"));
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var core = CoreBuilder.build (checked.program);
		CoreVerifier.verify (core);
		var getter = core.classes[3].properties[0].getter;
		var returned = (CoreReturn) getter.body.statements[0];
		var load = (CoreLoadValue) returned.value;
		var place = (CoreIndirectFieldPlace) load.source;
		assert (place.pointer is CoreClassUpcast);
		var wrong = new CoreLoadValue (load.span, new CoreIndirectFieldPlace (place.span, place.pointer, core.classes[4].fields[0]));
		getter.body.statements[0] = new CoreReturn (returned.span, wrong);
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("exact readonly receiver snapshot");
		}
		assert (rejected);
		getter.body.statements[0] = returned;
		CoreVerifier.verify (core);
		var ssa = SsaBuilder.build (CfgBuilder.build (core));
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native)).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void fresh_staging_forgeries() {
	try {
		var ssa = build ("enum Packet{Empty,Data(owned int[] data,int marker)}int fail() throws Error{throw new Error(\"x\");}int main(){try{var packet=Packet.Data(new int[3],fail());}catch(Error error){return 42;}return 1;}");
		SsaVerifier.verify (ssa);
		bool tested = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var aborted = block.instructions[i] as SsaEnumBufferAbort;
					if (aborted == null || !aborted.capture.fresh) {
						continue;
					}
					block.instructions.remove_index (i);
					bool rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						Test.message ("%s", error.message);
						rejected = error.message.contains ("pending reservation owner") || error.message.contains ("without exact disposition");
					}
					assert (rejected);
					block.instructions.insert (i, aborted);
					SsaVerifier.verify (ssa);
					block.instructions.insert (i + 1, new SsaEnumBufferAbort (aborted.span, aborted.capture));
					rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						Test.message ("%s", error.message);
						rejected = error.message.contains ("exact original cleanup owner") || error.message.contains ("already committed or aborted");
					}
					assert (rejected);
					block.instructions.remove_index (i + 1);
					SsaVerifier.verify (ssa);
					var cleanup = block.instructions[i + 2];
					assert (cleanup is SsaBufferDeallocateInstruction);
					block.instructions.remove_index (i + 2);
					rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						Test.message ("%s", error.message);
						rejected = error.message.contains ("exact original cleanup owner");
					}
					assert (rejected);
					block.instructions.insert (i + 2, cleanup);
					SsaVerifier.verify (ssa);
					tested = true;
					break;
				}
				if (tested) {
					break;
				}
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void heap_origin_correspondence() {
	try {
		var ssa = build ("owned Error make(){var error=new Error(\"x\");return move error;}int consume(owned Error error){return 42;}int main(){var error=make();return consume(move error);}");
		var native = NativeAbiBuilder.build (ssa);
		var foreign = CAbiBuilder.build (ssa, native);
		var saved = native.functions[0].signature.heap_result;
		var other = native.classes[1];
		native.functions[0].signature.heap_result = new NativeObjectOriginPlan (other.ordinal, other.name, true);
		NativeAbiVerifier.verify (native);
		bool rejected = false;
		try {
			LlvmLowering.lower (ssa, native, foreign);
		} catch (LlvmError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("exact source class and origin");
		}
		assert (rejected);
		native.functions[0].signature.heap_result = saved;
		LlvmLowering.lower (ssa, native, foreign).verify ();
		var parameter = native.functions[1].signature.parameters[0];
		saved = parameter.object_origin;
		parameter.object_origin = new NativeObjectOriginPlan (saved.class_ordinal, saved.class_name, false);
		NativeAbiVerifier.verify (native);
		rejected = false;
		try {
			LlvmLowering.lower (ssa, native, foreign);
		} catch (LlvmError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("allocation origin correspondence");
		}
		assert (rejected);
		parameter.object_origin = saved;
		LlvmLowering.lower (ssa, native, foreign).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void wrong_active_owner() {
	try {
		var ssa = build ("int fail() throws Error{throw new Error(\"x\");}int main(){try{fail();}catch(Error outer){try{fail();}catch(Error inner){return 42;}}return 1;}");
		SsaVerifier.verify (ssa);
		bool tested = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				var events = new GenericArray<SsaHeapOwnerEvent> ();
				foreach (var instruction in block.instructions) {
					var event = instruction as SsaHeapOwnerEvent;
					if (event != null && event.owner == null && event.effect is SsaCleanupInstruction) {
						events.add (event);
					}
				}
				if (events.length < 2 || events[0].value == events[1].value) {
					continue;
				}
				var original = (SsaCleanupInstruction) events[0].effect;
				int position = -1;
				int marker = -1;
				for (int i = 0; i < block.instructions.length; i++) {
					if (block.instructions[i] == original) {
						position = i;
					}
					if (block.instructions[i] == events[0]) {
						marker = i;
					}
				}
				assert (position >= 0 && marker >= 0);
				var changed = new SsaCleanupInstruction (original.span, events[1].value, original.cleanup);
				block.instructions[position] = changed;
				block.instructions[marker] = new SsaHeapOwnerEvent (events[0].span, null, events[0].action, changed.value, changed);
				bool rejected = false;
				try {
					SsaVerifier.verify (ssa);
				} catch (SsaError error) {
					Test.message ("%s", error.message);
					rejected = error.message.contains ("original active catch owner");
				}
				assert (rejected);
				block.instructions[position] = original;
				block.instructions[marker] = events[0];
				SsaVerifier.verify (ssa);
				tested = true;
				break;
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void handler_order() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("handlers", declarations () + "void fail() throws Error{throw new DecodeError(\"x\");}int main(){try{fail();}catch(DecodeError e){return 42;}catch(Error e){return 2;}return 1;}"));
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var core = CoreBuilder.build (checked.program);
		var protected_group = (CoreTry) core.functions[1].body.statements[0];
		assert (protected_group.catches.length == 2);
		var first = protected_group.catches[0];
		var second = protected_group.catches[1];
		protected_group.catches[0] = second;
		protected_group.catches[1] = first;
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("source-ordered");
		}
		assert (rejected);
		protected_group.catches[0] = first;
		protected_group.catches[1] = second;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		SsaVerifier.verify (ssa);
		assert (cfg.functions[1].handlers.length == 2 && ssa.functions[1].handlers.length == 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void independent_physical_forgeries() {
	try {
		SsaProgram? ssa = build ("class Base{init(){}virtual int run() throws Error{return 42;}}class Child:Base{init():base(){}override int run(){return 42;}}class Loud:DecodeError{init(string text):base(text){}override property string message{get{return this.text;}}}owned Error make(bool bad) throws DecodeError{var e=new Loud(\"dynamic\\0é\");if(bad){throw new DecodeError(\"failure\");}return move e;}int main(){try{var first=make(false);var view=first.message;var second=new Error(view);var object=new Child();if(value(object)!=42){return 3;}if(second.message==\"dynamic\\0é\"){return 42;}return 2;}catch(Error e){return 1;}}int value(Base object) throws Error{return object.run();}");
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		CAbiProgram? foreign = CAbiBuilder.build (ssa, native);
		var predecessor = WeakRef (ssa.classes[0]);
		var artifact = LlvmLowering.lower (ssa, native, foreign);
		ssa = null;
		native = null;
		foreign = null;
		assert (predecessor.get () == null);
		artifact.verify ();
		generic_valid (artifact);
		int addresses = 0;
		foreach (var binding in artifact.class_addresses) {
			var instruction = binding.instruction;
			if ((void*) CApi.is_instruction (instruction) == null) {
				continue;
			}
			var saved = CApi.operand (instruction, 0);
			CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (saved)));
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				Test.message ("%s", error.message);
				rejected = error.message.contains ("class address");
			}
			assert (rejected);
			CApi.set_operand (instruction, 0, saved);
			artifact.verify ();
			addresses++;
		}
		assert (addresses >= 10);
		bool other_receiver = false;
		var main = CApi.named_function (artifact.module, "astra.fn.1");
		foreach (var binding in artifact.class_addresses) {
			var instruction = binding.instruction;
			if ((void*) CApi.is_instruction (instruction) == null || (void*) CApi.block_parent (CApi.instruction_parent (instruction)) != (void*) main) {
				continue;
			}
			var original = CApi.operand (instruction, 0);
			if ((void*) CApi.is_instruction (original) == null || CApi.opcode (original) != CApi.Opcode.PHI) {
				continue;
			}
			foreach (var candidate in artifact.class_addresses) {
				if ((void*) CApi.is_instruction (candidate.instruction) == null || (void*) CApi.block_parent (CApi.instruction_parent (candidate.instruction)) != (void*) main) {
					continue;
				}
				var alternate = CApi.operand (candidate.instruction, 0);
				if ((void*) CApi.is_instruction (alternate) == null || CApi.opcode (alternate) != CApi.Opcode.LOAD || (void*) alternate == (void*) original) {
					continue;
				}
				size_t length;
				unowned string name = CApi.value_name (alternate, out length);
				if (!name.has_prefix ("v")) {
					continue;
				}
				CApi.set_operand (instruction, 0, alternate);
				generic_valid (artifact);
				bool rejected = false;
				try {
					artifact.verify ();
				} catch (LlvmError error) {
					Test.message ("%s", error.message);
					rejected = error.message.contains ("exact backing receiver");
				}
				assert (rejected);
				CApi.set_operand (instruction, 0, original);
				artifact.verify ();
				other_receiver = true;
				break;
			}
			if (other_receiver) {
				break;
			}
		}
		assert (other_receiver);
		int selections = 0;
		foreach (var binding in artifact.class_addresses) {
			var instruction = binding.instruction;
			if ((void*) CApi.is_instruction (instruction) == null) {
				continue;
			}
			int last = CApi.operand_count (instruction) - 1;
			var saved = CApi.operand (instruction, last);
			uint64 index = CApi.const_int_zext (saved);
			uint64 alternate = index == 0 ? 1 : 0;
			if (last == 2) {
				var layout = CApi.gep_source_type (instruction);
				alternate = index;
				for (uint field = 0; field < CApi.count_struct_element_types (layout); field++) {
					if (field != index && (void*) CApi.struct_get_type_at_index (layout, field) == (void*) CApi.struct_get_type_at_index (layout, (uint) index)) {
						alternate = field;
						break;
					}
				}
				if (alternate == index) {
					continue;
				}
			}
			CApi.set_operand (instruction, last, CApi.const_int (CApi.type_of (saved), alternate, 0));
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = error.message.contains ("exact field/header/virtual slot");
			}
			assert (rejected);
			CApi.set_operand (instruction, last, saved);
			artifact.verify ();
			selections++;
		}
		assert (selections >= 10);
		int branches = 0;
		foreach (var binding in artifact.class_branches) {
			var instruction = binding.instruction;
			var first = CApi.successor (instruction, 0);
			var second = CApi.successor (instruction, 1);
			if ((void*) first == (void*) second) {
				continue;
			}
			CApi.set_successor (instruction, 0, second);
			CApi.set_successor (instruction, 1, first);
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = error.message.contains ("source-ordered target");
			}
			assert (rejected);
			CApi.set_successor (instruction, 0, first);
			CApi.set_successor (instruction, 1, second);
			artifact.verify ();
			branches++;
		}
		assert (branches >= 3);
		int pairs = 0;
		foreach (var binding in artifact.class_values) {
			var instruction = binding.instruction;
			var operation = CApi.opcode (instruction);
			if (operation != CApi.Opcode.EXTRACT_VALUE && operation != CApi.Opcode.INSERT_VALUE && operation != CApi.Opcode.ICMP) {
				continue;
			}
			int operand = operation == CApi.Opcode.INSERT_VALUE ? 1 : 0;
			var saved = CApi.operand (instruction, operand);
			var changed = CApi.const_null (CApi.type_of (saved));
			if ((void*) saved == (void*) changed) {
				continue;
			}
			CApi.set_operand (instruction, operand, changed);
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = error.message.contains ("association");
			}
			assert (rejected);
			CApi.set_operand (instruction, operand, saved);
			artifact.verify ();
			pairs++;
		}
		assert (pairs >= 5);
		int reads = 0;
		int stores = 0;
		int origins = 0;
		foreach (var binding in artifact.class_values) {
			var instruction = binding.instruction;
			var operation = CApi.opcode (instruction);
			if (operation != CApi.Opcode.LOAD && operation != CApi.Opcode.STORE && operation != CApi.Opcode.SELECT) {
				continue;
			}
			int operand = operation == CApi.Opcode.SELECT ? 2 : 0;
			var saved = CApi.operand (instruction, operand);
			var changed = CApi.const_null (CApi.type_of (saved));
			if ((void*) changed == (void*) saved) {
				continue;
			}
			CApi.set_operand (instruction, operand, changed);
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				Test.message ("%s", error.message);
				rejected = error.message.contains ("class ") && error.message.contains ("association");
			}
			assert (rejected);
			CApi.set_operand (instruction, operand, saved);
			artifact.verify ();
			if (operation == CApi.Opcode.LOAD) {
				reads++;
			} else if (operation == CApi.Opcode.STORE) {
				stores++;
			} else {
				origins++;
			}
		}
		assert (reads >= 5 && stores >= 3 && origins >= 1);
		int tables = 0;
		foreach (var binding in artifact.class_globals) {
			size_t length;
			unowned string name = CApi.value_name (binding.value, out length);
			if (!name.has_prefix ("astra.class.slots.")) {
				continue;
			}
			var original = CApi.get_initializer (binding.value);
			int count = CApi.operand_count (original);
			var fields = new CApi.ValueRef[count];
			for (int i = 0; i < count; i++) {
				fields[i] = CApi.operand (original, i);
			}
			var selected = fields[0];
			CApi.ValueRef? alternate = null;
			foreach (var function in artifact.class_functions) {
				if ((void*) function.value != (void*) selected && (void*) CApi.global_value_type (function.value) == (void*) CApi.global_value_type (selected)) {
					alternate = function.value;
					break;
				}
			}
			if ((void*) alternate == null) {
				continue;
			}
			fields[0] = alternate;
			CApi.set_initializer (binding.value, CApi.const_array (CApi.type_of (selected), fields, fields.length));
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				Test.message ("%s", error.message);
				rejected = error.message.contains ("publication correspondence");
			}
			assert (rejected);
			CApi.set_initializer (binding.value, original);
			artifact.verify ();
			tables++;
		}
		assert (tables >= 2);
		int targets = 0;
		foreach (var binding in artifact.class_calls) {
			var instruction = binding.instruction;
			var original = CApi.called_value (instruction);
			foreach (var function in artifact.class_functions) {
				if ((void*) function.value == (void*) original || (void*) CApi.global_value_type (function.value) != (void*) CApi.called_function_type (instruction) || CApi.function_call_conv (function.value) != CApi.instruction_call_conv (instruction)) {
					continue;
				}
				CApi.set_operand (instruction, CApi.argument_count (instruction), function.value);
				generic_valid (artifact);
				bool rejected = false;
				try {
					artifact.verify ();
				} catch (LlvmError error) {
					rejected = error.message.contains ("exact target");
				}
				assert (rejected);
				CApi.set_operand (instruction, CApi.argument_count (instruction), original);
				artifact.verify ();
				targets++;
				break;
			}
		}
		assert (targets >= 3 && artifact.class_allocations.length >= 3);
		int calls = 0;
		foreach (var binding in artifact.class_calls) {
			var instruction = binding.instruction;
			if (CApi.argument_count (instruction) == 0) {
				continue;
			}
			for (int argument = 0; argument < CApi.argument_count (instruction); argument++) {
				var saved = CApi.operand (instruction, argument);
				var changed = CApi.const_null (CApi.type_of (saved));
				if ((void*) changed == (void*) saved) {
					continue;
				}
				CApi.set_operand (instruction, argument, changed);
				generic_valid (artifact);
				bool rejected = false;
				try {
					artifact.verify ();
				} catch (LlvmError error) {
					Test.message ("%s", error.message);
					rejected = error.message.contains ("class ") && error.message.contains ("channel");
				}
				assert (rejected);
				CApi.set_operand (instruction, argument, saved);
				artifact.verify ();
				calls++;
			}
		}
		assert (calls >= 10);
		Test.message ("independent bindings: addresses=%d reads=%d publications=%d origins=%d calls=%d; all LLVM valid, rejected and restored; selections=%d branches=%d pairs/comparisons=%d tables=%d targets=%d target-aligned-allocations=%u", addresses, reads, stores, origins, calls, selections, branches, pairs, tables, targets, artifact.class_allocations.length);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/error-1/exceptions/inherited-getter-exact-parent-field-rejected-and-restored", inherited_getter_authority);
	Test.add_func ("/error-1/exceptions/nested-exact-consumer-reservation-identity", nested_reservation_forgeries);
	Test.add_func ("/error-1/exceptions/getter-helper-selection-I-O-allocation-and-override-source-controls", getter_negatives);
	Test.add_func ("/error-1/exceptions/getter-effects-and-explicit-C-adapter-correspondence", getter_and_export_contracts);
	Test.add_func ("/error-1/exceptions/fresh-staged-acquisition-abort-and-cleanup", fresh_staging_forgeries);
	Test.add_func ("/error-1/exceptions/locally-valid-heap-result-and-parameter-origin", heap_origin_correspondence);
	Test.add_func ("/error-1/exceptions/balanced-cleanup-wrong-active-owner-rejected-and-restored", wrong_active_owner);
	Test.add_func ("/error-1/exceptions/source-ordered-handlers-rejected-and-restored", handler_order);
	Test.add_func ("/error-1/exceptions/independent-generic-valid-physical-relationships", independent_physical_forgeries);
	Test.add_func ("/error-1/exceptions/heap-owner-missing-duplicate-and-original-operand", heap_owner_forgeries);
	Test.add_func ("/error-1/exceptions/other-bound-correspondence-and-false-static-lifetime", native_contracts);
	Test.add_func ("/error-1/exceptions/open-bound-false-exhaustion-rejected-and-restored", exhaustive_bound);
	Test.add_func ("/error-1/exceptions/exact-argument-abort-rejected-and-restored", argument_abort);
	Test.add_func ("/error-1/exceptions/checked-bounds-and-narrow-rethrow", checked_bounds);
	Test.add_func ("/error-1/exceptions/failure-success-load-rejected-and-restored", success_guard);
	Test.add_func ("/error-1/exceptions/unmatched-catch-borrow-rejected-and-restored", catch_guard);
	Test.add_func ("/error-1/exceptions/locally-valid-other-class-correspondence", class_correspondence);
	Test.add_func ("/error-1/exceptions/retained-generic-valid-llvm-publications-and-conventions", llvm_correspondence);
	return Test.run ();
}
}
