// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.ContextContracts {
private const string API = "[CCode(destroy_function=\"context_destroy\",context=\"owned-concurrent\")]handle Context;owned Context context_open();";
private const string PROGRAM =
	"[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
	+ "class Leaf{int value;init(int value){this.value=value;}}"
	+ "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Box{private owned Leaf child;init(owned Leaf input,int mode)throws Fault{this.child=move input;if(mode!=0){throw new Fault(\"partial\");}}}"
	+ "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class GenericBox<T>{private owned T child;init(owned T child){this.child=move child;}}"
	+ "owned GenericBox<T> create<T>(borrowed Context context,owned T child)where T:Ownable{var box=new(context)GenericBox<T>(move child);return move box;}"
	+ "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Scalar{int value;init(int value)throws Fault{if(value<0){throw new Fault(\"scalar\");}this.value=value;}}"
	+ "int execute(borrowed Context context,int mode){try{var input=new Leaf(17);var box=new(context)Box(move input,mode);return 1;}catch(Fault error){return 0;}}"
	+ "int scalar(borrowed Context context){try{var value=try_new(context)Scalar(17);if(value==null){return 1;}return value.value-17;}catch(Fault error){return 2;}}"
	+ "int fallible_input(borrowed Context context){var input=new Leaf(17);try{var value=try_new(context)Box(move input,0);if(value==null){return input.value-17;}if(input!=null){return 1;}}catch(Fault error){if(input!=null){return 2;}}return 0;}"
	+ "int main(){var context=context_open();var input=new Leaf(23);var generic=create<Leaf>(context,move input);return scalar(context)+execute(context,1);} ";
private delegate void Check() throws GLib.Error;
private void refusal_text(owned Check action, string fragment, string? alternative = null, string? second_alternative = null) throws GLib.Error {
	bool rejected = false;
	try {
		action ();
	} catch (GLib.Error failure) {
		Test.message ("%s", failure.message);
		assert (failure.message.contains (fragment) || alternative != null && failure.message.contains (alternative) || second_alternative != null && failure.message.contains (second_alternative));
		rejected = true;
	}
	assert (rejected);
}

private const string SCOPED_API = "[CCode(destroy_function=\"astra_context17_destroy\",context=\"scoped-affine\")]handle Scoped;[CCode(cname=\"astra_context17_query_scoped\")]i64 query(borrowed Scoped context,int key);";
private const string SCOPED_PROGRAM = "int main(){owned u8[] backing=new u8[8197];{var context=scoped_allocator<Scoped>(backing,1,7);if(context==null){return 1;}if(query(context,7)!=1){return 2;}}return len(backing)-8197;}";
private SsaProgram scoped_ssa() throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (SCOPED_PROGRAM, SCOPED_API)))));
}

private void scoped_backing_stages() {
	try {
		CheckedProgram? checked = check (SCOPED_PROGRAM, SCOPED_API);
		bool changed = false;
		foreach (var local in checked.functions[0].locals) {
			if (local.scoped_backing == null) {
				continue;
			}
			var loan = local.scoped_backing;
			local.scoped_backing = null;
			refused (() => CoreBuilder.build (checked));
			local.scoped_backing = loan;
			changed = true;
		}
		assert (changed);
		var checked_reference = WeakRef (checked.functions[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (checked_reference.get () == null);
		CoreVerifier.verify (core);
		changed = false;
		foreach (var local in core.functions[0].locals) {
			if (!local.semantic_type.is_scoped_allocator ()) {
				continue;
			}
			var extent = local.text_extent;
			local.text_extent = null;
			refused (() => CoreVerifier.verify (core));
			local.text_extent = extent;
			CoreVerifier.verify (core);
			changed = true;
		}
		assert (changed);
		core = CoreGenericMonomorphizer.build (core);
		var core_reference = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_reference.get () == null);
		CfgVerifier.verify (cfg);
		changed = false;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				for (int p = 0; p < block.instructions.length; p++) {
					var evaluation = block.instructions[p] as CfgEvaluateInstruction;
					var scoped = evaluation == null ? null : evaluation.value as CfgScopedAllocator;
					if (scoped == null) {
						continue;
					}
					var acquisition = block.instructions[p + 1];
					block.instructions.remove_index (p + 1);
					refused (() => CfgVerifier.verify (cfg));
					block.instructions.insert (p + 1, acquisition);
					CfgVerifier.verify (cfg);
					var access = new CfgCleanupInstruction (scoped.span, new CfgLoadValue (scoped.span, scoped.backing), scoped.backing.cleanup);
					block.instructions.insert (p + 2, access);
					refusal_text (() => { OwnershipFlow.analyze (function);
					}, "exclusively borrowed");
					block.instructions.remove_index (p + 2);
					CfgVerifier.verify (cfg);
					changed = true;
				}
			}
		}
		assert (changed);
		var cfg_reference = WeakRef (cfg.functions[0]);
		SsaProgram? program = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_reference.get () == null);
		SsaVerifier.verify (program);
		changed = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int p = 0; p < block.instructions.length; p++) {
					var scoped = block.instructions[p] as SsaScopedAllocator;
					if (scoped == null) {
						continue;
					}
					var acquired = block.instructions[p + 1];
					block.instructions.remove_index (p + 1);
					refused (() => SsaVerifier.verify (program));
					block.instructions.insert (p + 1, acquired);
					SsaVerifier.verify (program);
					var access = new SsaBufferReadInstruction (scoped.span, new SsaBufferPlace (scoped.span, scoped.backing.cleanup, scoped.backing), 50000);
					block.instructions.insert (p + 2, access);
					refusal_text (() => SsaVerifier.verify (program), "scoped backing:");
					block.instructions.remove_index (p + 2);
					SsaVerifier.verify (program);
					changed = true;
				}
			}
		}
		assert (changed);
		var ssa_reference = WeakRef (program.functions[0]);
		var native = NativeAbiBuilder.build (program);
		program = null;
		assert (ssa_reference.get () == null);
		NativeAbiVerifier.verify (native);
		changed = false;
		foreach (var function in native.functions) {
			if (function.scoped_backings.length == 0) {
				continue;
			}
			var plan = function.scoped_backings[0];
			function.scoped_backings.remove_index (0);
			refused (() => NativeAbiVerifier.verify (native));
			function.scoped_backings.add (plan);
			NativeAbiVerifier.verify (native);
			int ordinal = plan.length_ordinal;
			plan.length_ordinal++;
			refused (() => NativeAbiVerifier.verify (native));
			plan.length_ordinal = ordinal;
			int end = plan.retirements[0];
			plan.retirements[0] = end + 1;
			refused (() => NativeAbiVerifier.verify (native));
			plan.retirements[0] = end;
			NativeAbiVerifier.verify (native);
			changed = true;
		}
		assert (changed);
		SsaProgram? llvm_source = scoped_ssa ();
		var llvm_reference = WeakRef (llvm_source.functions[0]);
		NativeAbiProgram? llvm_native = NativeAbiBuilder.build (llvm_source);
		CAbiProgram? foreign = CAbiBuilder.build (llvm_source, llvm_native);
		var artifact = LlvmLowering.lower (llvm_source, llvm_native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		llvm_source = null;
		llvm_native = null;
		foreign = null;
		assert (llvm_reference.get () == null);
		artifact.verify ();
		changed = false;
		var factory = CApi.named_function (artifact.module, "astra_context17_open_scoped");
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || (void*) CApi.called_value (instruction) != (void*) factory) {
						continue;
					}
					for (uint operand = 0; operand < 4; operand++) {
						var original = CApi.operand (instruction, operand);
						CApi.set_operand (instruction, operand, CApi.const_null (CApi.type_of (original)));
						refused (() => artifact.verify ());
						CApi.set_operand (instruction, operand, original);
						artifact.verify ();
					}
					CApi.ValueRef store = (CApi.ValueRef) null;
					for (var prior = CApi.first_instruction (block); (void*) prior != (void*) instruction; prior = CApi.next_instruction (prior)) {
						if (CApi.opcode (prior) == CApi.Opcode.STORE) {
							store = prior;
						}
					}
					assert ((void*) store != null);
					var next = CApi.next_instruction (store);
					var mutation = CApi.create_builder_in_context (artifact.context);
					CApi.remove_instruction (store);
					CApi.position_builder_before (mutation, CApi.next_instruction (instruction));
					CApi.insert_instruction (mutation, store);
					refusal_text (() => { foreach (var binding in artifact.scoped_backings) {
											  binding.verify ();
										  }
					}, "emitted backing access");
					refused (() => artifact.verify ());
					CApi.remove_instruction (store);
					CApi.position_builder_before (mutation, next);
					CApi.insert_instruction (mutation, store);
					CApi.dispose_builder (mutation);
					artifact.verify ();
					changed = true;
				}
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void refused(owned Check action) throws GLib.Error {
	bool rejected = false;
	try {
		action ();
	} catch (GLib.Error failure) {
		rejected = true;
		Test.message ("%s", failure.message);
	}
	assert (rejected);
}

private CheckedProgram check(string source = PROGRAM, string api = API, string? heap_boundary = null) {
	var parsed = Parser.parse (new SourceFile.from_text ("context-contract.astra", source));
	assert (parsed.diagnostic == null);
	var imported = VapiParser.parse (new SourceFile.from_text ("context-contract.vapi", api));
	assert (imported.diagnostic == null);
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (parsed.unit);
	var boundaries = new GenericArray<FunctionDeclarationSyntax> ();
	if (heap_boundary != null) {
		foreach (string name in heap_boundary.split (",")) {
			bool found = false;
			foreach (var declaration in parsed.unit.functions) {
				if (declaration.name.spelling () == name) {
					boundaries.add (declaration);
					found = true;
				}
			}
			assert (found);
		}
	}
	SemanticResult analyzed;
	try {
		analyzed = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), VapiNormalizer.normalize (imported.file), VapiNormalizer.normalize_handles (imported.file), null, boundaries);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
	if (analyzed.diagnostic != null) {
		error ("%s", analyzed.diagnostic.format ());
	}
	return analyzed.program;
}

private CoreProgram concrete() throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (check ()));
}

private void checked_policy() {
	try {
		var program = check ();
		ClassSymbol? box = null;
		foreach (var owner in program.classes) {
			if (owner.name == "Box") {
				box = owner;
			}
		}
		assert (box != null);
		box.allocation_policy.capacity = 1;
		refused (() => { CoreBuilder.build (program);
		});
		box.allocation_policy.capacity = 0;
		CoreBuilder.build (program);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void core_policy_and_unwind() {
	try {
		CheckedProgram? source = check ();
		var upstream = WeakRef (source.classes[0]);
		var program = CoreBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		assert (program.class_applications.length != 0);
		var application = program.class_applications[0];
		var policy = application.allocation_policy;
		assert (policy != null);
		application.allocation_policy = null;
		refused (() => CoreVerifier.verify (program));
		application.allocation_policy = policy;
		CoreVerifier.verify (program);
		CoreClass? box = null;
		foreach (var owner in program.classes) {
			if (owner.name == "Box") {
				box = owner;
			}
		}
		assert (box != null);
		var inventory = box.constructor.unwind_fields;
		assert (inventory.length == 1);
		var recipe = inventory[0];
		inventory.remove_index (0);
		refused (() => CoreVerifier.verify (program));
		inventory.add (recipe);
		CoreVerifier.verify (program);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cfg_unwind() {
	try {
		CoreProgram? source = concrete ();
		var upstream = WeakRef (source.classes[0]);
		var program = CfgBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		bool changed = false;
		foreach (var owner in program.classes) {
			if (owner.name != "Box") {
				continue;
			}
			foreach (var block in owner.constructor.blocks) {
				if (!(block.terminator is CfgExceptionReturn)) {
					continue;
				}
				uint position = block.instructions.length - 1;
				var abort = block.instructions[position];
				assert (abort is CfgConstructorAbort);
				block.instructions.remove_index (position);
				refused (() => CfgVerifier.verify (program));
				block.instructions.add (abort);
				CfgVerifier.verify (program);
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void ssa_unwind() {
	try {
		CfgProgram? source = CfgBuilder.build (concrete ());
		var upstream = WeakRef (source.classes[0]);
		var program = SsaBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		bool changed = false;
		foreach (var owner in program.classes) {
			if (owner.name != "Box") {
				continue;
			}
			foreach (var block in owner.constructor.blocks) {
				foreach (var instruction in block.instructions) {
					var abort = instruction as SsaConstructorAbort;
					if (abort == null) {
						continue;
					}
					var recipe = abort.fields[0];
					abort.fields.remove_index (0);
					refused (() => SsaVerifier.verify (program));
					abort.fields.add (recipe);
					SsaVerifier.verify (program);
					changed = true;
				}
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private SsaProgram ssa() throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (concrete ()));
}

private const string FRAME_PROGRAM = "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
    + "enum Status{Completed,Cancelled}async runtime Exec throws Fault returns Status provider \"virtual-composed\";"
    + "class Leaf{int value;init(int value){this.value=value;}}async void child(owned Leaf input,owned Context resource){}"
    + "int main(){var context=context_open();var input=new Leaf(17);var resource=context_open();try{var task=checked_task_in(context,child(move input,move resource));}catch(Fault error){if(input==null||resource==null){return 1;}}return 0;}";
private CoreProgram frame_core() throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (check (FRAME_PROGRAM)));
}

private SsaProgram fallible_buffer_ssa() throws GLib.Error {
	string text = PROGRAM.substring (0, PROGRAM.index_of ("[Allocator"))
	    + "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class BufferBox{owned Leaf child;owned u8[] plain;owned ContextBytes<Context> bytes;init(owned Leaf child,owned u8[] plain,owned ContextBytes<Context> bytes,int mode)throws Fault{this.child=move child;this.plain=move plain;if(mode!=0){throw new Fault(\"partial\");}this.bytes=move bytes;}}"
	    + "int main(){var context=context_open();var child=new Leaf(17);var plain=new u8[9];var bytes=new(context)u8[11];try{var box=try_new(context)BufferBox(move child,move plain,move bytes,0);if(box==null){return len(plain)+len(bytes)-20;}}catch(Fault error){}return 0;}";
	CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text))));
	var reference = WeakRef (cfg.functions[0]);
	var result = SsaBuilder.build (cfg);
	cfg = null;
	assert (reference.get () == null);
	SsaVerifier.verify (result);
	return result;
}

private SsaProgram fallible_record_ssa() throws GLib.Error {
	string text = PROGRAM.substring (0, PROGRAM.index_of ("[Allocator"))
	    + "struct Packet{owned Leaf child;owned Context state;owned u8[] plain;owned ContextBytes<Context> bytes;int marker;}"
	    + "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class RecordBox{owned Packet packet;owned u8[] tail;init(Packet packet,owned u8[] tail,int mode)throws Fault{this.packet=move packet;if(mode!=0){throw new Fault(\"partial\");}this.tail=move tail;}}"
	    + "int main(){var context=context_open();var child=new Leaf(17);var state=context_open();var plain=new u8[9];var bytes=new(context)u8[11];Packet packet={child=move child,state=move state,plain=move plain,bytes=move bytes,marker=17};var tail=new u8[13];try{var box=try_new(context)RecordBox(move packet,move tail,0);if(box==null){return packet.marker-17;}}catch(Fault error){}return 0;}";
	CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text))));
	var reference = WeakRef (cfg.functions[0]);
	var extents = new HashTable<int, HashTable<int, Astra.Text.TextLoanExtent>> (direct_hash, direct_equal);
	foreach (var function in cfg.functions) {
		var roots = new HashTable<int, Astra.Text.TextLoanExtent> (direct_hash, direct_equal);
		foreach (var local in function.locals) {
			if (local.cleanup != null && local.cleanup.record_type != null) {
				assert (local.text_extent != null);
				roots.insert (local.ordinal, local.text_extent);
			}
		}
		extents.insert (function.ordinal, roots);
	}
	var result = SsaBuilder.build (cfg);
	cfg = null;
	assert (reference.get () == null);
	int record_buffers = 0;
	foreach (var function in result.functions) {
		foreach (var owner in function.heap_owners) {
			if (owner.record_type != null) {
				assert (owner.text_extent != null && owner.text_extent == extents.lookup (function.ordinal).lookup (owner.source_ordinal));
			}
		}
		foreach (var buffer in function.buffer_storage) {
			if (buffer.record_type != null) {
				record_buffers++;
				assert (buffer.text_extent != null && buffer.text_extent == extents.lookup (function.ordinal).lookup (buffer.record_source_ordinal));
			}
		}
	}
	assert (record_buffers > 0);
	SsaVerifier.verify (result);
	return result;
}

private void fallible_records() {
	try {
		var program = fallible_record_ssa ();
		bool changed = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int p = 0; p < block.instructions.length; p++) {
					var restore = block.instructions[p] as SsaFallibleRecordRestore;
					if (restore == null) {
						continue;
					}
					var call = restore.call;
					call.record_restores.remove_index (0);
					refused (() => SsaVerifier.verify (program));
					call.record_restores.add (restore);
					SsaVerifier.verify (program);
					var acquire = restore.acquisition;
					acquire.admission_restore = null;
					refused (() => SsaVerifier.verify (program));
					acquire.admission_restore = restore;
					SsaVerifier.verify (program);
					var consume = block.instructions[p + 1];
					block.instructions.remove_index (p + 1);
					refused (() => SsaVerifier.verify (program));
					block.instructions.insert (p + 1, consume);
					SsaVerifier.verify (program);
					changed = true;
				}
			}
		}
		assert (changed);
		SsaProgram? source = fallible_record_ssa ();
		var upstream = WeakRef (source.functions[0]);
		var native = NativeAbiBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		changed = false;
		foreach (var function in native.functions) {
			foreach (var site in function.allocation_sites) {
				if (site.records.length == 0) {
					continue;
				}
				var input = site.records[0];
				site.records.remove_index (0);
				refused (() => NativeAbiVerifier.verify (native));
				site.records.add (input);
				NativeAbiVerifier.verify (native);
				int ordinal = input.source_ordinal;
				input.source_ordinal++;
				refused (() => NativeAbiVerifier.verify (native));
				input.source_ordinal = ordinal;
				NativeAbiVerifier.verify (native);
				changed = true;
			}
		}
		assert (changed);
		SsaProgram? llvm_source = fallible_record_ssa ();
		var llvm_upstream = WeakRef (llvm_source.functions[0]);
		NativeAbiProgram? llvm_native = NativeAbiBuilder.build (llvm_source);
		CAbiProgram? foreign = CAbiBuilder.build (llvm_source, llvm_native);
		var artifact = LlvmLowering.lower (llvm_source, llvm_native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		llvm_source = null;
		llvm_native = null;
		foreign = null;
		assert (llvm_upstream.get () == null);
		artifact.verify ();
		changed = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					if (CApi.opcode (instruction) != CApi.Opcode.SELECT || !CApi.value_name (instruction, out length).has_prefix ("allocation.record.leaf")) {
						continue;
					}
					var original = CApi.operand (instruction, 1);
					CApi.set_operand (instruction, 1, CApi.const_null (CApi.type_of (original)));
					refused (() => artifact.verify ());
					CApi.set_operand (instruction, 1, original);
					artifact.verify ();
					changed = true;
				}
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void fallible_buffers() {
	try {
		var program = fallible_buffer_ssa ();
		bool changed = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int p = 0; p < block.instructions.length; p++) {
					var restore = block.instructions[p] as SsaFallibleBufferRestore;
					if (restore == null) {
						continue;
					}
					var call = restore.call;
					int index = -1;
					for (int i = 0; i < call.buffer_restores.length; i++) {
						if (call.buffer_restores[i] == restore) {
							index = i;
						}
					}
					assert (index >= 0);
					call.buffer_restores.remove_index (index);
					refused (() => SsaVerifier.verify (program));
					call.buffer_restores.insert (index, restore);
					SsaVerifier.verify (program);
					var write = block.instructions[p + 1];
					block.instructions.remove_index (p + 1);
					refused (() => SsaVerifier.verify (program));
					block.instructions.insert (p + 1, write);
					SsaVerifier.verify (program);
					changed = true;
				}
			}
		}
		assert (changed);
		SsaProgram? source = fallible_buffer_ssa ();
		var upstream = WeakRef (source.functions[0]);
		var native = NativeAbiBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		changed = false;
		foreach (var function in native.functions) {
			foreach (var site in function.allocation_sites) {
				if (site.buffers.length == 0) {
					continue;
				}
				var input = site.buffers[0];
				site.buffers.remove_index (0);
				refused (() => NativeAbiVerifier.verify (native));
				site.buffers.insert (0, input);
				NativeAbiVerifier.verify (native);
				int ordinal = input.first_leaf;
				input.first_leaf++;
				refused (() => NativeAbiVerifier.verify (native));
				input.first_leaf = ordinal;
				NativeAbiVerifier.verify (native);
				changed = true;
			}
		}
		assert (changed);
		SsaProgram? llvm_source = fallible_buffer_ssa ();
		var llvm_upstream = WeakRef (llvm_source.functions[0]);
		NativeAbiProgram? llvm_native = NativeAbiBuilder.build (llvm_source);
		CAbiProgram? foreign = CAbiBuilder.build (llvm_source, llvm_native);
		var artifact = LlvmLowering.lower (llvm_source, llvm_native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		llvm_source = null;
		llvm_native = null;
		foreign = null;
		assert (llvm_upstream.get () == null);
		artifact.verify ();
		changed = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					if (CApi.opcode (instruction) != CApi.Opcode.SELECT || !(CApi.value_name (instruction, out length).has_prefix ("allocation.buffer.base") || CApi.value_name (instruction, out length).has_prefix ("allocation.buffer.length"))) {
						continue;
					}
					var original = CApi.operand (instruction, 1);
					CApi.set_operand (instruction, 1, CApi.const_null (CApi.type_of (original)));
					refused (() => artifact.verify ());
					CApi.set_operand (instruction, 1, original);
					artifact.verify ();
					changed = true;
				}
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private SsaProgram frame_ssa() throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (frame_core ()));
}

private const string RECORD_FRAME_PROGRAM = "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
    + "enum Status{Completed,Cancelled}async runtime Exec throws Fault returns Status provider \"virtual-composed\";"
    + "class Leaf{int value;init(int value){this.value=value;}}struct Packet{owned Leaf item;owned Context state;owned u8[] bytes;}"
    + "async void child(Packet packet)throws Fault{await delay_ticks(1);}async void root()throws Fault{var item=new Leaf(17);var state=context_open();var bytes=new u8[9];Packet packet={item=move item,state=move state,bytes=move bytes};var task=child(move packet);await move task;}"
    + "int main(){try{var executor=Exec.open(4);var status=executor.run(root());}catch(Fault error){return 1;}return 0;}";
private CfgProgram record_frame_cfg() throws GLib.Error {
	return CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (RECORD_FRAME_PROGRAM))));
}

private SsaProgram record_frame_ssa() throws GLib.Error {
	return SsaBuilder.build (record_frame_cfg ());
}

private SsaProgram checked_record_frame_ssa() throws GLib.Error {
	string text = RECORD_FRAME_PROGRAM.replace ("var task=child(move packet);", "var context=context_open();var task=checked_task_in(context,child(move packet));");
	CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text))));
	var reference = WeakRef (cfg.functions[0]);
	var result = SsaBuilder.build (cfg);
	cfg = null;
	assert (reference.get () == null);
	SsaVerifier.verify (result);
	return result;
}

private void checked_record_frames() {
	try {
		var program = checked_record_frame_ssa ();
		bool changed = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int p = 0; p < block.instructions.length; p++) {
					var restore = block.instructions[p] as SsaFrameRecordRestore;
					if (restore == null) {
						continue;
					}
					var creation = restore.creation;
					creation.record_restores.remove_index (0);
					refused (() => SsaVerifier.verify (program));
					creation.record_restores.add (restore);
					SsaVerifier.verify (program);
					var acquire = restore.acquisition;
					acquire.admission_restore = null;
					refused (() => SsaVerifier.verify (program));
					acquire.admission_restore = restore;
					SsaVerifier.verify (program);
					var consume = block.instructions[p + 1];
					block.instructions.remove_index (p + 1);
					refused (() => SsaVerifier.verify (program));
					block.instructions.insert (p + 1, consume);
					SsaVerifier.verify (program);
					changed = true;
				}
			}
		}
		assert (changed);
		SsaProgram? source = checked_record_frame_ssa ();
		var upstream = WeakRef (source.functions[0]);
		var native = NativeAbiBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		changed = false;
		foreach (var function in native.functions) {
			foreach (var site in function.frame_admissions) {
				if (site.records.length == 0) {
					continue;
				}
				var input = site.records[0];
				site.records.remove_index (0);
				refused (() => NativeAbiVerifier.verify (native));
				site.records.add (input);
				NativeAbiVerifier.verify (native);
				int ordinal = input.source_ordinal;
				input.source_ordinal = ordinal + 1;
				refused (() => NativeAbiVerifier.verify (native));
				input.source_ordinal = ordinal;
				NativeAbiVerifier.verify (native);
				changed = true;
			}
		}
		assert (changed);
		SsaProgram? llvm_source = checked_record_frame_ssa ();
		var llvm_upstream = WeakRef (llvm_source.functions[0]);
		NativeAbiProgram? llvm_native = NativeAbiBuilder.build (llvm_source);
		CAbiProgram? foreign = CAbiBuilder.build (llvm_source, llvm_native);
		var artifact = LlvmLowering.lower (llvm_source, llvm_native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		llvm_source = null;
		llvm_native = null;
		foreign = null;
		assert (llvm_upstream.get () == null);
		artifact.verify ();
		changed = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					if (CApi.opcode (instruction) != CApi.Opcode.SELECT || !CApi.value_name (instruction, out length).has_prefix ("frame.record.leaf")) {
						continue;
					}
					var original = CApi.operand (instruction, 1);
					CApi.set_operand (instruction, 1, CApi.const_null (CApi.type_of (original)));
					refused (() => artifact.verify ());
					CApi.set_operand (instruction, 1, original);
					artifact.verify ();
					changed = true;
				}
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private SsaProgram record_result_ssa() throws GLib.Error {
	string text = RECORD_FRAME_PROGRAM.substring (0, RECORD_FRAME_PROGRAM.index_of ("async void child"))
	    + "async Packet produced()throws Fault{var item=new Leaf(17);var state=context_open();var bytes=new u8[9];Packet packet={item=move item,state=move state,bytes=move bytes};await delay_ticks(1);return move packet;}"
	    + "async void root()throws Fault{Packet packet=await produced();}int main(){try{var executor=Exec.open(4);var status=executor.run(root());}catch(Fault error){return 1;}return 0;}";
	CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text))));
	var upstream = WeakRef (cfg.functions[0]);
	var result = SsaBuilder.build (cfg);
	cfg = null;
	assert (upstream.get () == null);
	return result;
}

private void owning_record_task_results() {
	try {
		var program = record_result_ssa ();
		bool changed = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (uint i = 0; i < block.instructions.length; i++) {
					var consume = block.instructions[i] as SsaStructResultConsume;
					if (consume == null || consume.results.shape.mode != StructValueMode.MOVE_VALUE) {
						continue;
					}
					block.instructions.remove_index (i);
					refused (() => SsaVerifier.verify (program));
					block.instructions.insert ((int) i, consume);
					SsaVerifier.verify (program);
					changed = true;
				}
			}
		}
		assert (changed);
		SsaProgram? source = record_result_ssa ();
		var reference = WeakRef (source.functions[0]);
		var native = NativeAbiBuilder.build (source);
		source = null;
		assert (reference.get () == null);
		changed = false;
		foreach (var frame in native.async_frames) {
			if (frame.record_result == null || frame.record_result.ownership.length == 0) {
				continue;
			}
			var owner = frame.record_result.ownership[0];
			frame.record_result.ownership.remove_index (0);
			refused (() => NativeAbiVerifier.verify (native));
			frame.record_result.ownership.insert (0, owner);
			NativeAbiVerifier.verify (native);
			changed = true;
		}
		assert (changed);
		SsaProgram? llvm_source = record_result_ssa ();
		var llvm_reference = WeakRef (llvm_source.functions[0]);
		NativeAbiProgram? llvm_native = NativeAbiBuilder.build (llvm_source);
		CAbiProgram? foreign = CAbiBuilder.build (llvm_source, llvm_native);
		var artifact = LlvmLowering.lower (llvm_source, llvm_native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		llvm_source = null;
		llvm_native = null;
		foreign = null;
		assert (llvm_reference.get () == null);
		artifact.verify ();
		changed = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				var branch = CApi.block_terminator (block);
				if (CApi.opcode (branch) != CApi.Opcode.BR || CApi.successor_count (branch) != 2) {
					continue;
				}
				var condition = CApi.operand (branch, 0);
				size_t length;
				if (!CApi.value_name (condition, out length).has_prefix ("discard.initialized.record")) {
					continue;
				}
				CApi.set_operand (branch, 0, CApi.const_null (CApi.type_of (condition)));
				refused (() => artifact.verify ());
				CApi.set_operand (branch, 0, condition);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void owning_record_frames() {
	try {
		var cfg = record_frame_cfg ();
		bool changed = false;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var creation = instruction as CfgTaskCreate;
					if (creation == null || creation.record_moves.length == 0) {
						continue;
					}
					var move = creation.record_moves[0];
					creation.record_moves.remove_index (0);
					refused (() => CfgVerifier.verify (cfg));
					creation.record_moves.add (move);
					CfgVerifier.verify (cfg);
					changed = true;
				}
			}
		}
		assert (changed);
		CfgProgram? upstream = record_frame_cfg ();
		var reference = WeakRef (upstream.functions[0]);
		var program = SsaBuilder.build (upstream);
		upstream = null;
		assert (reference.get () == null);
		changed = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var creation = instruction as SsaTaskCreate;
					if (creation == null || creation.record_moves.length == 0) {
						continue;
					}
					var move = creation.record_moves[0];
					creation.record_moves.remove_index (0);
					refused (() => SsaVerifier.verify (program));
					creation.record_moves.add (move);
					SsaVerifier.verify (program);
					changed = true;
				}
			}
		}
		assert (changed);
		SsaProgram? native_source = record_frame_ssa ();
		var native_reference = WeakRef (native_source.functions[0]);
		var native = NativeAbiBuilder.build (native_source);
		native_source = null;
		assert (native_reference.get () == null);
		changed = false;
		foreach (var function in native.functions) {
			if (function.async_callable == null) {
				continue;
			}
			foreach (var group in function.signature.struct_parameters) {
				if (group.value_plan.ownership.length == 0) {
					continue;
				}
				var owner = group.value_plan.ownership[0];
				group.value_plan.ownership.remove_index (0);
				refused (() => NativeAbiVerifier.verify (native));
				group.value_plan.ownership.insert (0, owner);
				NativeAbiVerifier.verify (native);
				changed = true;
			}
		}
		assert (changed);
		SsaProgram? llvm_source = record_frame_ssa ();
		var llvm_reference = WeakRef (llvm_source.functions[0]);
		NativeAbiProgram? llvm_native = NativeAbiBuilder.build (llvm_source);
		CAbiProgram? foreign = CAbiBuilder.build (llvm_source, llvm_native);
		var artifact = LlvmLowering.lower (llvm_source, llvm_native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		llvm_source = null;
		llvm_native = null;
		foreign = null;
		assert (llvm_reference.get () == null);
		artifact.verify ();
		changed = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			if (!CApi.value_name (function, out length).has_prefix ("astra.task.create.")) {
				continue;
			}
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.STORE) {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					if ((void*) CApi.type_of (original) != (void*) CApi.int1_type_in_context (artifact.context) || (void*) CApi.is_instruction (original) == null || CApi.opcode (original) != CApi.Opcode.ICMP) {
						continue;
					}
					CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (original)));
					refused (() => artifact.verify ());
					CApi.set_operand (instruction, 0, original);
					artifact.verify ();
					changed = true;
				}
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private SsaProgram buffer_frame_ssa() throws GLib.Error {
	string source = FRAME_PROGRAM.replace ("owned Context resource)", "owned Context resource,owned u8[] plain,owned ContextBytes<Context> bytes)")
	    .replace ("var resource=context_open();", "var resource=context_open();var plain=new u8[7];var bytes=new(context)u8[9];")
	    .replace ("move input,move resource)", "move input,move resource,move plain,move bytes)")
	    .replace ("input==null||resource==null", "input==null||resource==null||len(plain)!=7||len(bytes)!=9");
	CheckedProgram? checked = check (source);
	CoreProgram? core = CoreGenericMonomorphizer.build (CoreBuilder.build (checked));
	checked = null;
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	var upstream = WeakRef (cfg.functions[0]);
	var result = SsaBuilder.build (cfg);
	cfg = null;
	assert (upstream.get () == null);
	return result;
}

private void checked_frame_buffers() {
	try {
		var program = buffer_frame_ssa ();
		bool changed = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (uint i = 0; i < block.instructions.length; i++) {
					var restore = block.instructions[i] as SsaFrameBufferRestore;
					if (restore == null) {
						continue;
					}
					var creation = restore.creation;
					uint index = 0;
					while (creation.buffer_restores[index] != restore) {
						index++;
					}
					creation.buffer_restores.remove_index (index);
					refused (() => SsaVerifier.verify (program));
					creation.buffer_restores.insert ((int) index, restore);
					SsaVerifier.verify (program);
					var write = (SsaBufferWriteInstruction) block.instructions[i + 1];
					block.instructions[i + 1] = new SsaBufferWriteInstruction (write.span, write.place, new SsaBufferPair.empty (write.span, write.pair.shape));
					refused (() => SsaVerifier.verify (program));
					block.instructions[i + 1] = write;
					SsaVerifier.verify (program);
					changed = true;
				}
			}
		}
		assert (changed);
		SsaProgram? upstream = buffer_frame_ssa ();
		var reference = WeakRef (upstream.functions[0]);
		var native = NativeAbiBuilder.build (upstream);
		upstream = null;
		assert (reference.get () == null);
		changed = false;
		foreach (var function in native.functions) {
			foreach (var site in function.frame_admissions) {
				if (site.buffers.length == 0) {
					continue;
				}
				var input = site.buffers[0];
				site.buffers.remove_index (0);
				refused (() => NativeAbiVerifier.verify (native));
				site.buffers.insert (0, input);
				NativeAbiVerifier.verify (native);
				int original = input.first_leaf;
				input.first_leaf++;
				refused (() => NativeAbiVerifier.verify (native));
				input.first_leaf = original;
				NativeAbiVerifier.verify (native);
				changed = true;
			}
		}
		assert (changed);
		SsaProgram? llvm_source = buffer_frame_ssa ();
		var llvm_reference = WeakRef (llvm_source.functions[0]);
		NativeAbiProgram? llvm_native = NativeAbiBuilder.build (llvm_source);
		CAbiProgram? foreign = CAbiBuilder.build (llvm_source, llvm_native);
		var artifact = LlvmLowering.lower (llvm_source, llvm_native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		llvm_source = null;
		llvm_native = null;
		foreign = null;
		assert (llvm_reference.get () == null);
		artifact.verify ();
		int channels = 0;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					string name = CApi.value_name (instruction, out length);
					if (CApi.opcode (instruction) != CApi.Opcode.SELECT || !name.has_prefix ("frame.buffer.base") && !name.has_prefix ("frame.buffer.length")) {
						continue;
					}
					var original = CApi.operand (instruction, 1);
					CApi.set_operand (instruction, 1, CApi.const_null (CApi.type_of (original)));
					refused (() => artifact.verify ());
					CApi.set_operand (instruction, 1, original);
					artifact.verify ();
					channels |= name.has_prefix ("frame.buffer.base") ? 1 : 2;
				}
			}
		}
		assert (channels == 3);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void checked_frame_stages() {
	try {
		var core = frame_core ();
		bool changed = false;
		foreach (var function in core.functions) {
			foreach (var local in function.locals) {
				if (local.name == "input") {
					local.mark_nonnull ();
					refused (() => CoreVerifier.verify (core));
					changed = true;
				}
			}
		}
		assert (changed);
		var cfg = CfgBuilder.build (frame_core ());
		changed = false;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var creation = instruction as CfgTaskCreate;
					if (creation == null) {
						continue;
					}
					var exception = creation.exception_result;
					creation.exception_result = null;
					refused (() => CfgVerifier.verify (cfg));
					creation.exception_result = exception;
					CfgVerifier.verify (cfg);
					changed = true;
				}
			}
		}
		assert (changed);
		CfgProgram? upstream = CfgBuilder.build (frame_core ());
		var upstream_identity = WeakRef (upstream.functions[0]);
		var program = SsaBuilder.build (upstream);
		upstream = null;
		assert (upstream_identity.get () == null);
		changed = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (uint i = 0; i < block.instructions.length; i++) {
					var restore = block.instructions[i] as SsaFrameInputRestore;
					if (restore == null) {
						continue;
					}
					var creation = restore.creation;
					uint index = 0;
					while (creation.input_restores[index] != restore) {
						index++;
					}
					creation.input_restores.remove_index (index);
					refused (() => SsaVerifier.verify (program));
					creation.input_restores.insert ((int) index, restore);
					SsaVerifier.verify (program);
					var acquired = block.instructions[i + 1];
					block.instructions.remove_index (i + 1);
					refused (() => SsaVerifier.verify (program));
					block.instructions.insert ((int) i + 1, acquired);
					SsaVerifier.verify (program);
					changed = true;
				}
			}
		}
		assert (changed);
		SsaProgram? native_upstream = frame_ssa ();
		var native_identity = WeakRef (native_upstream.functions[0]);
		var native = NativeAbiBuilder.build (native_upstream);
		native_upstream = null;
		assert (native_identity.get () == null);
		changed = false;
		foreach (var function in native.functions) {
			if (function.frame_admissions.length == 0) {
				continue;
			}
			var site = function.frame_admissions[0];
			function.frame_admissions.remove_index (0);
			refused (() => NativeAbiVerifier.verify (native));
			function.frame_admissions.add (site);
			NativeAbiVerifier.verify (native);
			var input = site.inputs[0];
			int source = input.source_ordinal;
			input.source_ordinal++;
			refused (() => NativeAbiVerifier.verify (native));
			input.source_ordinal = source;
			NativeAbiVerifier.verify (native);
			changed = true;
		}
		assert (changed);
		SsaProgram? llvm_upstream = frame_ssa ();
		var llvm_identity = WeakRef (llvm_upstream.functions[0]);
		NativeAbiProgram? llvm_native = NativeAbiBuilder.build (llvm_upstream);
		CAbiProgram? llvm_foreign = CAbiBuilder.build (llvm_upstream, llvm_native);
		var artifact = LlvmLowering.lower (llvm_upstream, llvm_native, llvm_foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		llvm_upstream = null;
		llvm_native = null;
		llvm_foreign = null;
		assert (llvm_identity.get () == null);
		artifact.verify ();
		changed = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					string name = CApi.value_name (instruction, out length);
					if ((CApi.opcode (instruction) != CApi.Opcode.SELECT || !name.has_prefix ("frame.input.owner")) && (CApi.opcode (instruction) != CApi.Opcode.PHI || !name.has_prefix ("frame.admission.exception"))) {
						continue;
					}
					var original = CApi.operand (instruction, 1);
					CApi.set_operand (instruction, 1, CApi.const_null (CApi.type_of (original)));
					refused (() => artifact.verify ());
					CApi.set_operand (instruction, 1, original);
					artifact.verify ();
					changed = true;
				}
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void fallible_input_stages() {
	try {
		var core = concrete ();
		bool core_changed = false;
		foreach (var function in core.functions) {
			if (function.name != "fallible_input") {
				continue;
			}
			foreach (var local in function.locals) {
				if (local.name == "input") {
					local.mark_nonnull ();
					refused (() => CoreVerifier.verify (core));
					core_changed = true;
					break;
				}
			}
		}
		assert (core_changed);
		var cfg = CfgBuilder.build (concrete ());
		bool cfg_changed = false;
		foreach (var function in cfg.functions) {
			if (function.name != "fallible_input") {
				continue;
			}
			foreach (var local in function.locals) {
				if (local.name == "input") {
					local.mark_nonnull ();
					refused (() => CfgVerifier.verify (cfg));
					cfg_changed = true;
					break;
				}
			}
		}
		assert (cfg_changed);
		CfgProgram? upstream = CfgBuilder.build (concrete ());
		var upstream_identity = WeakRef (upstream.functions[0]);
		var program = SsaBuilder.build (upstream);
		upstream = null;
		assert (upstream_identity.get () == null);
		bool changed = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (uint i = 0; i < block.instructions.length; i++) {
					var restore = block.instructions[i] as SsaFallibleInputRestore;
					if (restore == null) {
						continue;
					}
					var call = restore.call;
					assert (call.input_restores.length == 1);
					call.input_restores.remove_index (0);
					refused (() => SsaVerifier.verify (program));
					call.input_restores.add (restore);
					SsaVerifier.verify (program);
					var acquired = block.instructions[i + 1];
					block.instructions.remove_index (i + 1);
					refused (() => SsaVerifier.verify (program));
					block.instructions.insert ((int) i + 1, acquired);
					SsaVerifier.verify (program);
					changed = true;
				}
			}
		}
		assert (changed);
		SsaProgram? native_upstream = ssa ();
		var native_identity = WeakRef (native_upstream.classes[0]);
		var native = NativeAbiBuilder.build (native_upstream);
		native_upstream = null;
		assert (native_identity.get () == null);
		bool native_changed = false;
		foreach (var function in native.functions) {
			foreach (var site in function.allocation_sites) {
				if (site.inputs.length == 0) {
					continue;
				}
				var input = site.inputs[0];
				site.inputs.remove_index (0);
				refused (() => NativeAbiVerifier.verify (native));
				site.inputs.add (input);
				NativeAbiVerifier.verify (native);
				int ordinal = input.source_ordinal;
				input.source_ordinal = ordinal + 1;
				refused (() => NativeAbiVerifier.verify (native));
				input.source_ordinal = ordinal;
				NativeAbiVerifier.verify (native);
				native_changed = true;
			}
		}
		assert (native_changed);
		var lowered = artifact ();
		bool llvm_changed = false;
		for (var function = CApi.first_function (lowered.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					if (CApi.opcode (instruction) != CApi.Opcode.SELECT || !CApi.value_name (instruction, out length).has_prefix ("allocation.input.owner")) {
						continue;
					}
					var original = CApi.operand (instruction, 1);
					CApi.set_operand (instruction, 1, CApi.const_null (CApi.type_of (original)));
					refused (() => lowered.verify ());
					CApi.set_operand (instruction, 1, original);
					lowered.verify ();
					llvm_changed = true;
				}
			}
		}
		assert (llvm_changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_unwind() {
	try {
		SsaProgram? source = ssa ();
		var upstream = WeakRef (source.classes[0]);
		var program = NativeAbiBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		bool changed = false;
		foreach (var function in program.functions) {
			var plan = function.constructor_unwind;
			if (plan == null || plan.field_count != 1) {
				continue;
			}
			function.constructor_unwind = null;
			refused (() => NativeAbiVerifier.verify (program));
			function.constructor_unwind = plan;
			NativeAbiVerifier.verify (program);
			changed = true;
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private LlvmModuleArtifact artifact() throws GLib.Error {
	SsaProgram? source = ssa ();
	var upstream = WeakRef (source.classes[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (source);
	CAbiProgram? cabi = CAbiBuilder.build (source, native);
	var result = LlvmLowering.lower (source, native, cabi);
	new LlvmTargetMachineArtifact (0).configure (result);
	source = null;
	native = null;
	cabi = null;
	assert (upstream.get () == null);
	result.verify ();
	return result;
}

private void llvm_origin() {
	try {
		var program = artifact ();
		var target = CApi.named_function (program.module, "astra_context17_allocate_mode");
		bool changed = false;
		for (var function = CApi.first_function (program.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || (void*) CApi.called_value (instruction) != (void*) target) {
						continue;
					}
					foreach (uint operand in new uint[] { 0, 2, 3, 4, 5 }) {
						var original = CApi.operand (instruction, operand);
						CApi.set_operand (instruction, operand, CApi.const_null (CApi.type_of (original)));
						char* message;
						assert (CApi.verify_module (program.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
						if (message != null) {
							CApi.dispose_message (message);
						}
						refused (() => program.verify ());
						CApi.set_operand (instruction, operand, original);
						program.verify ();
						changed = true;
					}
				}
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_refusal_join() {
	try {
		var program = artifact ();
		bool changed = false;
		for (var function = CApi.first_function (program.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					if (CApi.opcode (instruction) != CApi.Opcode.PHI || !CApi.value_name (instruction, out length).has_prefix ("allocation.checked.exception")) {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					var one = CApi.const_int (CApi.int_type_in_context (program.context, 64), 1, 0);
					CApi.set_operand (instruction, 0, CApi.const_int_to_ptr (one, CApi.type_of (original)));
					char* message;
					assert (CApi.verify_module (program.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
					if (message != null) {
						CApi.dispose_message (message);
					}
					refused (() => program.verify ());
					CApi.set_operand (instruction, 0, original);
					program.verify ();
					changed = true;
				}
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void ssa_task_pointer_join() {
	try {
		string text = "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
		    + "enum Status{Completed,Cancelled}async runtime Exec throws Fault returns Status provider \"virtual-composed\";"
		    + "async int leaf()throws Fault{return 17;}"
		    + "async void root(bool flag)throws Fault{var task=leaf();if(flag){await cancel_and_join(move task);}else{int value=await move task;}}"
		    + "async void mixed(bool flag)throws Fault{var task=leaf();if(flag){await cancel_and_join(move task);}}"
		    + "int main(){try{var executor=Exec.open(4);var status=executor.run(root(true));}catch(Fault error){return 1;}return 0;}";
		CfgProgram? upstream = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, ""))));
		var reference = WeakRef (upstream.functions[0]);
		var program = SsaBuilder.build (upstream);
		upstream = null;
		assert (reference.get () == null);
		SsaVerifier.verify (program);
		bool changed = false;
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var end = block.instructions[i] as SsaTaskEnd;
					if (end == null || !(end.source is SsaBlockParameter)) {
						continue;
					}
					SsaTaskAcquire? acquisition = null;
					foreach (var candidate in function.blocks) {
						foreach (var instruction in candidate.instructions) {
							var acquire = instruction as SsaTaskAcquire;
							if (acquire != null && acquire.owner_ordinal == end.owner_ordinal) {
								acquisition = acquire;
							}
						}
					}
					assert (acquisition != null);
					block.instructions[i] = new SsaTaskEnd (end.span, acquisition.source, end.owner_ordinal);
					bool rejected = false;
					try {
						SsaVerifier.verify (program);
					} catch (SsaError failure) {
						assert (failure.message.contains ("current exact live/absent pointer"));
						rejected = true;
					}
					assert (rejected);
					block.instructions[i] = end;
					SsaVerifier.verify (program);
					changed = true;
					bool edge_changed = false;
					foreach (var predecessor in function.blocks) {
						if (edge_changed) {
							break;
						}
						foreach (var edge in SsaHeapOwnerFlow.pointer_edges (predecessor)) {
							for (int p = 0; p < edge.target.parameters.length; p++) {
								if (edge.target.parameters[p] != end.source || !(edge.arguments[p] is SsaTaskAbsent)) {
									continue;
								}
								var original = edge.arguments[p];
								edge.arguments[p] = acquisition.source;
								rejected = false;
								try {
									SsaVerifier.verify (program);
								} catch (SsaError failure) {
									assert (failure.message.contains ("current exact live/absent pointer"));
									rejected = true;
								}
								assert (rejected);
								edge.arguments[p] = original;
								SsaVerifier.verify (program);
								edge_changed = true;
								break;
							}
							if (edge_changed) {
								break;
							}
						}
					}
					assert (edge_changed);
				}
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void owning_record_stages() {
	try {
		string text = "class Payload{init(){}}struct Record<T>where T:Ownable{owned T payload;int marker;}"
		    + "int main(){var item=new Payload();Record<Payload> value={payload=move item,marker=17};Record<Context> backing={payload=context_open(),marker=23};return value.marker+backing.marker-40;}";
		CheckedProgram? checked = check (text);
		var checked_reference = WeakRef (checked.structs[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (checked_reference.get () == null);
		var field = core.structs[0].fields[1];
		core.structs[0].fields.remove_index (1);
		refused (() => CoreVerifier.verify (core));
		core.structs[0].fields.add (field);
		CoreVerifier.verify (core);
		field = null;
		var argument = core.structs[0].owning_arguments[0];
		core.structs[0].owning_arguments[0] = core.structs[1].owning_arguments[0];
		refused (() => CoreVerifier.verify (core));
		core.structs[0].owning_arguments[0] = argument;
		CoreVerifier.verify (core);
		argument = null;
		core = CoreGenericMonomorphizer.build (core);
		var core_reference = WeakRef (core.structs[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_reference.get () == null);
		var cfg_field = cfg.structs[0].fields[1];
		cfg.structs[0].fields.remove_index (1);
		refused (() => CfgVerifier.verify (cfg));
		cfg.structs[0].fields.add (cfg_field);
		CfgVerifier.verify (cfg);
		cfg_field = null;
		var cfg_argument = cfg.structs[0].owning_arguments[0];
		cfg.structs[0].owning_arguments[0] = cfg.structs[1].owning_arguments[0];
		refused (() => CfgVerifier.verify (cfg));
		cfg.structs[0].owning_arguments[0] = cfg_argument;
		CfgVerifier.verify (cfg);
		cfg_argument = null;
		var cfg_reference = WeakRef (cfg.structs[0]);
		SsaProgram? program = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_reference.get () == null);
		var ssa_field = program.structs[0].fields[1];
		program.structs[0].fields.remove_index (1);
		refused (() => SsaVerifier.verify (program));
		program.structs[0].fields.add (ssa_field);
		SsaVerifier.verify (program);
		ssa_field = null;
		var ssa_argument = program.structs[0].owning_arguments[0];
		program.structs[0].owning_arguments[0] = program.structs[1].owning_arguments[0];
		refused (() => SsaVerifier.verify (program));
		program.structs[0].owning_arguments[0] = ssa_argument;
		SsaVerifier.verify (program);
		ssa_argument = null;
		var ssa_reference = WeakRef (program.structs[0]);
		var native = NativeAbiBuilder.build (program);
		program = null;
		assert (ssa_reference.get () == null);
		bool context_mutated = false;
		foreach (var application in native.record_applications) {
			assert (application.owned_declaration != null);
			var record = application.record;
			var scalar = record.leaves[1];
			record.leaves[1] = new NativeStructLeafChannel (scalar.field_path, new NativeScalarAbiType (NativeScalarType.F64), scalar.storage_path, scalar.buffer_component);
			refused (() => NativeAbiVerifier.verify (native));
			record.leaves[1] = scalar;
			NativeAbiVerifier.verify (native);
			var original = record.leaves[0];
			var context = original.abi_type as NativeContextHandleType;
			if (context == null) {
				continue;
			}
			record.leaves[0] = new NativeStructLeafChannel (original.field_path, new NativeContextHandleType (context.name, "owned-affine", context.cleanup), original.storage_path, original.buffer_component);
			refused (() => NativeAbiVerifier.verify (native));
			record.leaves[0] = original;
			NativeAbiVerifier.verify (native);
			context_mutated = true;
			var release = record.declaration.fields[0];
			record.declaration.fields[0] = new NativeRecordResource.projected (new int[] {0}, release.type_name, "wrong_context_release");
			refused (() => NativeAbiVerifier.verify (native));
			record.declaration.fields[0] = release;
			NativeAbiVerifier.verify (native);
		}
		assert (context_mutated);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void owning_record_mixed_stages() {
	try {
		string text = "struct Copied<A>{A number;}struct Mixed<T,K>where T:Ownable{owned T payload;K copied;owned int[] samples;}"
		    + "int main(){var samples=new int[3];Mixed<Context,Copied<int>> value={payload=context_open(),copied={number=17},samples=move samples};return value.copied.number-17;}";
		CheckedProgram? checked = check (text);
		var checked_reference = WeakRef (checked.generic_structs[0].definition);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (checked_reference.get () == null);
		CoreVerifier.verify (core);
		var original_argument = core.structs[0].owning_arguments[1];
		core.structs[0].owning_arguments[1] = core.structs[0].owning_arguments[0];
		refused (() => CoreVerifier.verify (core));
		core.structs[0].owning_arguments[1] = original_argument;
		original_argument = null;
		core = CoreGenericMonomorphizer.build (core);
		var core_reference = WeakRef (core.structs[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_reference.get () == null);
		CfgVerifier.verify (cfg);
		var cfg_reference = WeakRef (cfg.structs[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_reference.get () == null);
		SsaVerifier.verify (ssa);
		var ssa_reference = WeakRef (ssa.structs[0]);
		var native = NativeAbiBuilder.build (ssa);
		ssa = null;
		assert (ssa_reference.get () == null);
		NativeAbiVerifier.verify (native);
		bool mutated = false;
		foreach (var application in native.record_applications) {
			if (application.owned_declaration == null) {
				continue;
			}
			for (int position = 0; position < application.record.leaves.length; position++) {
				var leaf = application.record.leaves[position];
				if (leaf.buffer_component != 1) {
					continue;
				}
				application.record.leaves[position] = new NativeStructLeafChannel (leaf.field_path, new NativeScalarAbiType (NativeScalarType.I64), leaf.storage_path, leaf.buffer_component);
				refused (() => NativeAbiVerifier.verify (native));
				application.record.leaves[position] = leaf;
				NativeAbiVerifier.verify (native);
				mutated = true;
				break;
			}
		}
		assert (mutated);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void context_byte_stages() {
	try {
		CheckedProgram? checked = check ("owned ContextBytes<Context> produce(){var context=context_open();var bytes=new(context)u8[7];return move bytes;}int main(){var bytes=produce();return len(bytes)-7;}");
		var checked_reference = WeakRef (checked.functions[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (checked_reference.get () == null);
		CoreVerifier.verify (core);
		core = CoreGenericMonomorphizer.build (core);
		var core_reference = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_reference.get () == null);
		CfgVerifier.verify (cfg);
		var cfg_reference = WeakRef (cfg.functions[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_reference.get () == null);
		SsaVerifier.verify (ssa);
		bool read_changed = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int p = 1; p < block.instructions.length; p++) {
					var allocation = block.instructions[p] as SsaBufferAllocateInstruction;
					if (allocation == null || allocation.context_owner == null) {
						continue;
					}
					var read = block.instructions[p - 1] as SsaHeapOwnerEvent;
					assert (read != null);
					block.instructions[p - 1] = new SsaHeapOwnerEvent (read.span, read.owner, SsaHeapOwnerAction.READ, new SsaNullPointerConstant (read.span, read.value.semantic_type), allocation);
					refused (() => SsaVerifier.verify (ssa));
					block.instructions[p - 1] = read;
					SsaVerifier.verify (ssa);
					read_changed = true;
				}
			}
		}
		assert (read_changed);
		var native = NativeAbiBuilder.build (ssa);
		bool erased = false;
		foreach (var function in native.functions) {
			var plan = function.signature.buffer_result;
			if (plan == null || plan.context_origin == null) {
				continue;
			}
			function.signature.buffer_result = new NativeBufferValuePlan (new NativeScalarAbiType (NativeScalarType.U8));
			refused (() => NativeAbiVerifier.verify (native));
			function.signature.buffer_result = plan;
			NativeAbiVerifier.verify (native);
			erased = true;
		}
		assert (erased);
		var cabi = CAbiBuilder.build (ssa, native);
		var upstream = WeakRef (ssa.functions[0]);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		ssa = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		artifact.verify ();
		var target = CApi.named_function (artifact.module, "astra_context17_allocate_mode");
		bool changed = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || (void*) CApi.called_value (instruction) != (void*) target) {
						continue;
					}
					foreach (uint operand in new uint[] { 0, 2, 4, 5 }) {
						var original = CApi.operand (instruction, operand);
						CApi.set_operand (instruction, operand, CApi.const_null (CApi.type_of (original)));
						refused (() => artifact.verify ());
						CApi.set_operand (instruction, operand, original);
						artifact.verify ();
						changed = true;
					}
				}
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void worker_byte_group() {
	try {
		var checked = check ("[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}enum Status{Completed,Cancelled}async runtime Executor throws Fault returns Status provider \"posix-threaded\";async owned ContextBytes<Context> work(owned ContextBytes<Context> bytes)throws Fault{await delay_ticks(1);return move bytes;}int main(){return 0;}");
		var core = CoreGenericMonomorphizer.build (CoreBuilder.build (checked));
		var cfg = CfgBuilder.build (core);
		var ssa = SsaBuilder.build (cfg);
		SsaVerifier.verify (ssa);
		bool mutated = false;
		foreach (var function in ssa.functions) {
			if (function.async_body == null || !function.async_body.runtime.threaded || function.buffer_parameters.length != 1) {
				continue;
			}
			var group = function.buffer_parameters[0];
			function.buffer_parameters.remove_index (0);
			refused (() => SsaVerifier.verify (ssa));
			function.buffer_parameters.add (group);
			SsaVerifier.verify (ssa);
			mutated = true;
		}
		assert (mutated);
		var native = NativeAbiBuilder.build (ssa);
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void throwing_byte_failure() {
	try {
		CheckedProgram? checked = check ("[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}void reject(owned ContextBytes<Context> bytes)throws Fault{throw new Fault(\"exhausted\");}int run(borrowed Context context){var previous=new(context)u8[7];try{var bytes=new(context)u8[9]else reject(move previous);return 1;}catch(Fault error){return 0;}}int main(){var context=context_open();return run(context);}");
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		core = CoreGenericMonomorphizer.build (core);
		var core_reference = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_reference.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		bool changed = false;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				var request = block.terminator as CfgBufferAllocationBranch;
				if (request == null) {
					continue;
				}
				var call = request.allocation.failure.action as CfgCallInstruction;
				assert (call != null && call.exception_result != null);
				var exception = call.exception_result;
				call.exception_result = null;
				refused (() => CfgVerifier.verify (cfg));
				call.exception_result = exception;
				CfgVerifier.verify (cfg);
				changed = true;
			}
		}
		assert (changed);
		var cfg_reference = WeakRef (cfg.functions[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_reference.get () == null);
		SsaVerifier.verify (ssa);
		changed = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				var request = block.terminator as SsaBufferAllocationBranch;
				if (request == null) {
					continue;
				}
				var call = request.allocation.failure.action as SsaCallInstruction;
				assert (call != null && call.exception_result != null);
				var exception = call.exception_result;
				call.exception_result = null;
				refused (() => SsaVerifier.verify (ssa));
				call.exception_result = exception;
				SsaVerifier.verify (ssa);
				changed = true;
			}
		}
		assert (changed);
		var native = NativeAbiBuilder.build (ssa);
		var foreign = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, foreign);
		ssa = null;
		native = null;
		foreign = null;
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void context_byte_view() {
	try {
		CheckedProgram? checked = check ("int inspect(u8[] bytes){return len(bytes);}int main(){var context=context_open();var bytes=new(context)u8[7];return inspect(bytes)-7;}");
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		core = CoreGenericMonomorphizer.build (core);
		var core_reference = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_reference.get () == null);
		CfgVerifier.verify (cfg);
		var cfg_reference = WeakRef (cfg.functions[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_reference.get () == null);
		SsaVerifier.verify (ssa);
		bool changed = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int p = 0; p < block.instructions.length; p++) {
					var borrow = block.instructions[p] as SsaBufferBorrowInstruction;
					if (borrow == null || borrow.result.semantic_type == borrow.pair.shape.slice_type) {
						continue;
					}
					assert (borrow.pair.shape.slice_type is ContextBytesType && !(borrow.result.semantic_type is ContextBytesType));
					SsaCallInstruction? consumer = null;
					int argument = -1;
					foreach (var site in function.blocks) {
						foreach (var operation in site.instructions) {
							var call = operation as SsaCallInstruction;
							if (call == null) {
								continue;
							}
							for (int a = 0; a < call.arguments.length; a++) {
								if (call.arguments[a] == borrow.result) {
									assert (consumer == null);
									consumer = call;
									argument = a;
								}
							}
						}
					}
					assert (consumer != null && argument >= 0);
					var shape = new BufferValueShape (new SliceType (borrow.pair.shape.length_type), borrow.pair.shape.base_type, borrow.pair.shape.length_type);
					var pair = new SsaBufferPair (borrow.span, shape, borrow.pair.base_value, borrow.pair.length_value);
					var forged = new SsaBufferBorrowInstruction (borrow.span, pair, borrow.result.ordinal, (SliceType) borrow.result.semantic_type);
					block.instructions[p] = forged;
					consumer.arguments[argument] = forged.result;
					refused (() => SsaVerifier.verify (ssa));
					consumer.arguments[argument] = borrow.result;
					block.instructions[p] = borrow;
					SsaVerifier.verify (ssa);
					changed = true;
				}
			}
		}
		assert (changed);
		var native = NativeAbiBuilder.build (ssa);
		var foreign = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, foreign);
		ssa = null;
		native = null;
		foreign = null;
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_lifetime_summary() {
	try {
		string text = "class Child{int code;init(int code){this.code=code;}}class Holder{private owned Child child;init(owned Child child){this.child=move child;}}owned Holder wrap(owned Child child){var result=new Holder(move child);return move result;}int main(){return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text)))));
		SsaFunction? wrapping = null;
		foreach (var function in source.functions) {
			if (function.name == "wrap") {
				wrapping = function;
			}
		}
		assert (wrapping != null);
		var weak = WeakRef (wrapping);
		var native = NativeAbiBuilder.build (source);
		int ordinal = wrapping.ordinal;
		wrapping = null;
		source = null;
		assert (weak.get () == null);
		NativeAbiVerifier.verify (native);
		var target = native.functions[ordinal];
		var summary = RuntimeLifetimeSummary.decode (target.runtime_lifetimes);
		assert (summary.complete && summary.equations.requirements (summary.result, "f0").length == 1);
		string original = target.runtime_lifetimes;
		target.runtime_lifetimes = "runtime-lifetime-summary/1:incomplete";
		refusal_text (() => NativeAbiVerifier.verify (native), "native summary differs");
		target.runtime_lifetimes = original;
		NativeAbiVerifier.verify (native);
		refusal_text (() => target.bind_runtime_lifetimes (original), "binds once");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_controller_uses() {
	try {
		for (int mode = 0; mode < 5; mode++) {
			SsaProgram? source = scoped_ssa ();
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			artifact.verify ();
			var opening = CApi.named_function (artifact.module, "astra_context17_open_scoped");
			var destruction = CApi.named_function (artifact.module, "astra_context17_destroy");
			var query = CApi.named_function (artifact.module, "astra_context17_query_scoped");
			CApi.ValueRef factory = (CApi.ValueRef) null;
			CApi.ValueRef cleanup = (CApi.ValueRef) null;
			for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
				for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
					for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
						if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
							continue;
						}
						if ((void*) CApi.called_value (instruction) == (void*) opening) {
							factory = instruction;
						}
						if ((void*) cleanup == null && (void*) CApi.called_value (instruction) == (void*) destruction) {
							cleanup = instruction;
						}
					}
				}
			}
			assert ((void*) factory != null && (void*) cleanup != null);
			var builder = CApi.create_builder_in_context (artifact.context);
			CApi.ValueRef mutation;
			CApi.ValueRef slot = (CApi.ValueRef) null;
			if (mode == 0) {
				CApi.position_builder_before (builder, CApi.next_instruction (cleanup));
				CApi.ValueRef[] arguments = {
					CApi.operand (cleanup, 0), CApi.const_int (CApi.int_type_in_context (artifact.context, 32), 7, 0)
				};
				mutation = CApi.build_call (builder, CApi.global_value_type (query), query, arguments, 2, "invalid.query");
				CApi.set_instruction_call_conv (mutation, CApi.CallConv.C);
			} else {
				CApi.position_builder_before (builder, CApi.next_instruction (factory));
				if (mode == 1) {
					slot = CApi.build_alloca (builder, CApi.type_of (factory), "invalid.context.alias");
					mutation = CApi.build_store (builder, factory, slot);
				} else if (mode == 2) {
					CApi.ValueRef[] arguments = {
						factory
					};
					mutation = CApi.build_call (builder, CApi.global_value_type (destruction), destruction, arguments, 1, "");
					CApi.set_instruction_call_conv (mutation, CApi.CallConv.C);
				} else if (mode == 3) {
					mutation = CApi.build_ptr_to_int (builder, factory, CApi.int_type_in_context (artifact.context, 64), "invalid.context.integer");
				} else {
					var signature = CApi.function_type (CApi.void_type_in_context (artifact.context), null, 0, 0);
					mutation = CApi.build_call (builder, signature, factory, null, 0, "");
					CApi.set_instruction_call_conv (mutation, CApi.CallConv.C);
				}
			}
			refusal_text (() => { foreach (var binding in artifact.scoped_backings) {
									  binding.verify ();
								  }
			}, mode == 0 ? "context use lacks" : mode == 2 ? "unregistered emitted retirement" : "controller escaped");
			refused (() => artifact.verify ());
			CApi.erase_instruction (mutation);
			if ((void*) slot != null) {
				CApi.erase_instruction (slot);
			}
			CApi.dispose_builder (builder);
			artifact.verify ();
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_allocation_artifact() {
	try {
		SsaProgram? source = scoped_ssa ();
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.artifact (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_native_borrow() {
	try {
		string observer = "class Observer{int code;init(int value){this.code=value;}int read(){return this.code;}}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (SCOPED_PROGRAM + observer, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.native_borrow (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_allocator_parameters() {
	try {
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (SCOPED_PROGRAM + "int observe(borrowed Scoped context){return 0;}", SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		var native = NativeAbiBuilder.build (source);
		HashTable<SsaFunction, NativeFunction>? map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		NativeFunction? target = null;
		for (int f = 0; f < source.functions.length; f++) {
			map.insert (source.functions[f], native.functions[f]);
			if (source.functions[f].name == "observe") {
				target = native.functions[f];
			}
		}
		assert (target != null);
		var parameter = target.signature.parameters[0];
		var context = parameter.abi_type as NativeContextHandleType;
		assert (context != null && context.mode == "scoped-affine" && context.cleanup == "astra_context17_destroy");
		NativeAbiValidator.validate_ssa_calls (source, native, map);
		var replacements = new GenericArray<NativeParameter> ();
		for (int mode = 0; mode < 3; mode++) {
			NativeAbiType type = mode == 0 ? (NativeAbiType) new NativeScalarAbiType (NativeScalarType.PTR) : new NativeContextHandleType (context.name, mode == 1 ? "owned-concurrent" : context.mode, mode == 2 ? "free" : context.cleanup);
			var replacement = new NativeParameter.typed (parameter.span, parameter.name_span, parameter.name, parameter.ordinal, type);
			replacement.bind_resource (parameter.resource, false);
			target.signature.parameters[0] = replacement;
			refusal_text (() => NativeAbiValidator.validate_ssa_calls (source, native, map), "parameter channel type does not match SSA function");
			replacements.add (replacement);
			target.signature.parameters[0] = parameter;
			NativeAbiVerifier.verify (native);
		}
		map = null;
		source = null;
		assert (weak.get () == null);
		foreach (var replacement in replacements) {
			target.signature.parameters[0] = replacement;
			refused (() => NativeAbiVerifier.verify (native));
			target.signature.parameters[0] = parameter;
			NativeAbiVerifier.verify (native);
		}
		Test.expect_message ("GLib-GObject", LogLevelFlags.LEVEL_CRITICAL, "*scalar-type*not writable*");
		context.set ("scalar-type", NativeScalarType.I64);
		Test.assert_expected_messages ();
		assert (context.valid () && context.scalar_type == NativeScalarType.PTR);
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_context_inputs() {
	try {
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (SCOPED_PROGRAM + "int observe(borrowed Scoped context){return 0;}", SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.context_inputs (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_owned_inputs() {
	try {
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}int consume(owned ScopedLeaf first,owned ScopedLeaf second){return 7;}", SCOPED_API, "consume")))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.owned_inputs (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_forwarded_owner() {
	try {
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}owned ScopedLeaf forward(int marker,owned ScopedLeaf input){return move input;}", SCOPED_API, "forward")))));
		int ordinal = -1;
		for (int f = 0; f < source.functions.length; f++) {
			if (source.functions[f].name == "forward") {
				ordinal = f;
			}
		}
		assert (ordinal >= 0);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		var target = CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal));
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.forwarded_owner (artifact, target);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_field_effects() {
	try {
		string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}class Host{int marker;private owned ScopedLeaf left;private owned ScopedLeaf right;init(int marker,owned ScopedLeaf left,owned ScopedLeaf right){this.marker=marker;this.left=move left;this.right=move right;}}int field_control(){var host=new Host(9,null,null);return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.field_effects (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_field_loans() {
	try {
		string text = SCOPED_PROGRAM.replace ("if(query(context,7)!=1){return 2;}", "var source_host=new Host(9,null,null);if(query(context,7)!=1){return 2;}") + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}class Host{int marker;private owned ScopedLeaf left;private owned ScopedLeaf right;init(int marker,owned ScopedLeaf left,owned ScopedLeaf right){this.marker=marker;this.left=move left;this.right=move right;}}int field_control(){var host=new Host(9,null,null);return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.field_loans (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_field_policy() {
	try {
		string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{int marker;private owned ScopedLeaf left;private owned ScopedLeaf right;init(int marker,owned ScopedLeaf left,owned ScopedLeaf right){this.marker=marker;this.left=move left;this.right=move right;}}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.field_loans (artifact, true);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_heap_fields() {
	try {
		string text = SCOPED_PROGRAM.replace ("if(query(context,7)!=1){return 2;}", "var source_host=new Host(9,null,null);if(query(context,7)!=1){return 2;}") + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}class Host{int marker;private owned ScopedLeaf left;private owned ScopedLeaf right;init(int marker,owned ScopedLeaf left,owned ScopedLeaf right){this.marker=marker;this.left=move left;this.right=move right;}int read(){return this.marker;}void clear(){this.left=empty();}}owned ScopedLeaf empty(){return null;}class Other{int marker;private owned ScopedLeaf left;private owned ScopedLeaf right;init(int marker,owned ScopedLeaf left,owned ScopedLeaf right){this.marker=marker;this.left=move left;this.right=move right;}int read(){return this.marker;}}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.heap_fields (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_context_heap_fields(bool factory, bool fallible = false, bool multiple = false) {
	try {
		foreach (var mode in new string[] { "owned-affine", "owned-transfer", "owned-concurrent" }) {
			string text = (factory ? SCOPED_PROGRAM.replace ("int main(){", "int main(){var parent=context_open();") : SCOPED_PROGRAM.replace ("int main()", "int exercise(borrowed Context parent)")).replace ("if(query(context,7)!=1){return 2;}", "var source_host=new(parent)Host(9,null,null);if(query(context,7)!=1){return 2;}") + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{int marker;private owned ScopedLeaf left;private owned ScopedLeaf right;init(int marker,owned ScopedLeaf left,owned ScopedLeaf right){this.marker=marker;this.left=move left;this.right=move right;}int read(){return this.marker;}void clear(){this.left=empty();}}owned ScopedLeaf empty(){return null;}class Other{int marker;private owned ScopedLeaf left;private owned ScopedLeaf right;init(int marker,owned ScopedLeaf left,owned ScopedLeaf right){this.marker=marker;this.left=move left;this.right=move right;}int read(){return this.marker;}}";
			if (multiple) {
				text = text.replace ("var parent=context_open();", "var parent=context_open();var second_parent=context_open();").replace ("var source_host=new(parent)Host(9,null,null);", "var source_host=new(parent)Host(9,null,null);var other_host=try_new(second_parent)Host(19,null,null);");
			}
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check ((fallible ? text.replace ("new(parent)Host", "try_new(parent)Host") : text).replace ("owned-concurrent", mode) + (factory ? "" : "int main(){return 0;}"), SCOPED_API + API.replace ("context_destroy", "astra_context17_destroy").replace ("owned-concurrent", mode))))));
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			if (multiple) {
				LlvmLifetimeTests.multiple_heap_fields (artifact);
			} else {
				LlvmLifetimeTests.heap_fields (artifact, true, fallible);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_context_heap_fields() {
	scoped_context_heap_fields (false);
}

private void llvm_context_factory_heap_fields() {
	scoped_context_heap_fields (true);
}

private void llvm_fallible_context_heap_fields() {
	scoped_context_heap_fields (true, true);
}

private void llvm_multiple_context_heap_fields() {
	scoped_context_heap_fields (true, true, true);
}

private void llvm_checked_heap_result() {
	try {
		foreach (int profile in new int[] { 0, 1, 2, 3 }) {
			bool shifted = profile == 1, context = profile == 2;
			string text = SCOPED_PROGRAM + "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}owned ScopedLeaf checked_heap(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(\"checked\");}return move input;}owned ScopedLeaf relay(owned ScopedLeaf input,int mode)throws Fault{return checked_heap(move input,mode);}";
			if (shifted) {
				text = text.replace ("checked_heap(owned", "checked_heap(int marker,owned").replace ("relay(owned", "relay(int marker,owned").replace ("checked_heap(move", "checked_heap(marker,move");
			}
			if (context) {
				text = text.replace ("checked_heap(owned", "checked_heap(borrowed Scoped context,owned").replace ("relay(owned", "relay(borrowed Scoped context,owned").replace ("checked_heap(move", "checked_heap(context,move");
			}
			if (profile == 3) {
				text = text.replace ("class ScopedLeaf{init(){}}", "class ScopedLeaf{init(){}int read(){return 11;}}");
				text += "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedView{init(){}deinit(){}int read(){return 7;}}";
				text += "owned ScopedLeaf owner_relay(owned ScopedLeaf input,owned ScopedView view,int mode)throws Fault{return checked_heap(move input,view,mode);}";
				text = text.replace ("checked_heap(owned ScopedLeaf input,int mode)", "checked_heap(owned ScopedLeaf input,borrowed ScopedView view,int mode)").replace ("relay(owned ScopedLeaf input,int mode)", "relay(owned ScopedLeaf input,borrowed ScopedView view,int mode)").replace ("if(mode!=0)", "if(view!=null){view.read();}if(mode!=0)").replace ("checked_heap(move input,mode)", "checked_heap(move input,view,mode)");
			}
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, profile == 3 ? "checked_heap,relay,owner_relay" : "checked_heap,relay")))));
			int ordinal = -1, relay = -1, lender = -1;
			foreach (var function in source.functions) {
				if (function.name == "checked_heap") {
					ordinal = function.ordinal;
				}
				if (function.name == "relay") {
					relay = function.ordinal;
				}
				if (function.name == "owner_relay") {
					lender = function.ordinal;
				}
			}
			assert (ordinal >= 0 && relay >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			int view = -1;
			if (profile == 3) {
				foreach (var owner in native.classes) {
					if (owner.name == "ScopedView") {
						view = owner.ordinal;
					}
				}
				assert (view >= 0);
			}
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			if (context) {
				assert (artifact.has_scoped_context_inputs (CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal))) && artifact.has_scoped_context_inputs (CApi.named_function (artifact.module, "astra.fn.%d".printf (relay))));
			}
			LlvmLifetimeTests.checked_heap_result (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal)), shifted || context ? 2 : 1);
			LlvmLifetimeTests.checked_heap_caller (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (relay)), CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal)), shifted || context ? 2 : 1);
			if (profile == 3) {
				LlvmLifetimeTests.class_loan (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal)), CApi.named_function (artifact.module, "astra.fn.%d".printf (relay)), CApi.named_function (artifact.module, "astra.fn.%d".printf (lender)), view);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_error_payload() {
	try {
		for (int profile = 0; profile < 4; profile++) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}void raise(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(move input);}}";
			if (profile == 1) {
				text = text.replace ("raise(owned", "raise(int marker,owned");
			}
			if (profile == 2) {
				text = text.replace ("void raise", "int raise").replace ("throw new Fault(move input);}}", "throw new Fault(move input);}return 17;}");
			}
			if (profile == 3) {
				text = text.replace ("class Fault{", "class Fault{int code;").replace ("init(owned ScopedLeaf child){", "init(int code,owned ScopedLeaf child){this.code=code;").replace ("new Fault(move input)", "new Fault(17,move input)");
			}
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "raise")))));
			int raised = -1;
			foreach (var function in source.functions) {
				if (function.name == "raise") {
					raised = function.ordinal;
				}
			}
			assert (raised >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			assert (artifact.has_scoped_owned_inputs (CApi.named_function (artifact.module, "astra.fn.%d".printf (raised))));
			LlvmLifetimeTests.exception_payload (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (raised)), profile == 1 || profile == 2 ? 1 : 0);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_exception_field_layout() {
	try {
		string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}[ExceptionRoot]class Fault{int code;private owned ScopedLeaf child;init(int code,owned ScopedLeaf child){this.code=code;this.child=move child;}virtual property string message{get{return \"owned\";}}}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		int owner = -1;
		foreach (var plan in native.classes) {
			if (plan.name == "Fault") {
				owner = plan.ordinal;
			}
		}
		assert (owner >= 0);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		var constructor = CApi.named_function (artifact.module, "astra.ctor.%d".printf (owner));
		var destructor = CApi.named_function (artifact.module, "astra.dtor.%d".printf (owner));
		assert (artifact.has_scoped_owned_inputs (constructor) && artifact.has_scoped_owned_inputs (destructor));
		LlvmLifetimeTests.exception_fields (artifact, constructor, destructor);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_exception_caller_transport() {
	try {
		for (int profile = 0; profile < 6; profile++) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}void raise(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(move input);}}void relay(owned ScopedLeaf input,int mode)throws Fault{raise(move input,mode);}";
			if (profile == 1) {
				text = text.replace ("raise(owned", "raise(int marker,owned").replace ("relay(owned", "relay(int marker,owned").replace ("raise(move", "raise(marker,move");
			}
			if (profile == 2) {
				text = text.replace ("void raise", "int raise").replace ("void relay", "int relay").replace ("throw new Fault(move input);}}", "throw new Fault(move input);}return 17;}").replace ("{raise(move", "{return raise(move");
			}
			if (profile == 3) {
				text = text.replace ("class Fault{", "class Fault{int code;").replace ("init(owned ScopedLeaf child){", "init(int code,owned ScopedLeaf child){this.code=code;").replace ("new Fault(move input)", "new Fault(17,move input)");
			}
			if (profile >= 4) {
				text = text.replace ("class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}", "class Fault{private owned ScopedLeaf child;private owned ScopedLeaf second;init(owned ScopedLeaf child,owned ScopedLeaf second){this.child=move child;this.second=move second;}").replace ("owned ScopedLeaf input,int mode", "owned ScopedLeaf input,owned ScopedLeaf other,int mode").replace ("new Fault(move input)", "new Fault(move input,move other)").replace ("raise(move input,mode)", "raise(move input,move other,mode)");
			}
			if (profile == 5) {
				text = text.replace ("raise(move input,move other,mode)", "raise(move input,null,mode)");
			}
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "raise,relay")))));
			int raised = -1, relayed = -1;
			foreach (var function in source.functions) {
				if (function.name == "raise") {
					raised = function.ordinal;
				}
				if (function.name == "relay") {
					relayed = function.ordinal;
				}
			}
			assert (raised >= 0 && relayed >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			int fault = -1;
			foreach (var plan in native.classes) {
				if (plan.name == "Fault") {
					fault = plan.ordinal;
				}
			}
			assert (fault >= 0);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.exception_caller (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (relayed)), CApi.named_function (artifact.module, "astra.fn.%d".printf (raised)), profile == 1 || profile == 2 ? 1 : 0, CApi.named_function (artifact.module, "astra.ctor.%d".printf (fault)), profile >= 4);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_missing_formal_authority() {
	try {
		foreach (bool context in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}owned ScopedLeaf checked_heap(" + (context ? "borrowed Scoped context," : "") + "owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(\"checked\");}return move input;}";
			if (context) {
				text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}void checked_heap(borrowed Scoped context,owned ScopedLeaf input,int mode)throws Fault{throw new Fault(move input);}";
			}
			if (!context) {
				text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}void checked_heap(owned ScopedLeaf input,int mode)throws Fault{throw new Fault(move input);}";
			}
			text = text.replace ("[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child)", "class Box{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}[ExceptionRoot]class Fault{private owned Box child;init(owned Box child)").replace ("throw new Fault(move input);", "var payload=new Box(move input);throw new Fault(move payload);");
			var source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "checked_heap")))));
			var native = NativeAbiBuilder.build (source);
			var foreign = CAbiBuilder.build (source, native);
			refusal_text (() => { LlvmLowering.lower (source, native, foreign);
			}, "scoped formal requires its complete emitted ABI authority");
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_exception_catch_retirement() {
	try {
		for (int profile = 0; profile < 4; profile++) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(){this.number=7;}deinit(){}}[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}void raise(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(move input);}}void handled(owned ScopedLeaf input,int mode){try{raise(move input,mode);}catch(Fault error){}}";
			if (profile == 1) {
				text = text.replace ("void raise", "int raise").replace ("throw new Fault(move input);}}", "throw new Fault(move input);}return 17;}");
			}
			if (profile >= 2) {
				text = text.replace ("class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}", "class Fault{private owned ScopedLeaf child;private owned ScopedLeaf second;init(owned ScopedLeaf child,owned ScopedLeaf second){this.child=move child;this.second=move second;}").replace ("owned ScopedLeaf input,int mode", "owned ScopedLeaf input,owned ScopedLeaf other,int mode").replace ("new Fault(move input)", "new Fault(move input,move other)").replace ("raise(move input,mode)", "raise(move input,move other,mode)");
			}
			if (profile == 3) {
				text = text.replace ("raise(move input,move other,mode)", "raise(move input,null,mode)");
			}
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "raise,handled")))));
			int raised = -1, handled = -1;
			foreach (var function in source.functions) {
				if (function.name == "raise") {
					raised = function.ordinal;
				}
				if (function.name == "handled") {
					handled = function.ordinal;
				}
			}
			assert (raised >= 0 && handled >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.exception_catch (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (handled)), CApi.named_function (artifact.module, "astra.fn.%d".printf (raised)), profile == 0);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_checked_context_input() {
	try {
		foreach (bool owned in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}int checked_context(borrowed Scoped context," + (owned ? "owned ScopedLeaf input," : "") + "int mode)throws Fault{query(context,7);if(mode!=0){throw new Fault(\"checked\");}return mode;}int relay(borrowed Scoped context," + (owned ? "owned ScopedLeaf input," : "") + "int mode)throws Fault{return checked_context(context," + (owned ? "move input," : "") + "mode);}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, owned ? "checked_context,relay" : null)))));
			int ordinal = -1, relay = -1;
			foreach (var function in source.functions) {
				if (function.name == "checked_context") {
					ordinal = function.ordinal;
				}
				if (function.name == "relay") {
					relay = function.ordinal;
				}
			}
			assert (ordinal >= 0 && relay >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			var target = CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal));
			LlvmLifetimeTests.checked_context (artifact, target, CApi.named_function (artifact.module, "astra.fn.%d".printf (relay)), owned);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_exception_composition() {
	try {
		for (int profile = 0; profile < 3; profile++) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(){this.number=7;}deinit(){}}[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}void raise(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(move input);}}void exercise(owned ScopedLeaf input,int mode){try{raise(move input,mode);}catch(Fault error){}}";
			if (profile == 0 || profile == 2) {
				text = text.replace ("try{raise(move input,mode);}", "try{if(mode!=0){throw new Fault(move input);}}");
			}
			if (profile != 0) {
				text = text.replace ("void exercise(owned ScopedLeaf input,int mode){", "void exercise(owned ScopedLeaf input,int mode)throws Fault{").replace ("catch(Fault error){}", "catch(Fault error){throw;}");
			}
			Test.message ("exception composition profile %d", profile);
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "raise,exercise")))));
			int exercise = -1, raised = -1;
			foreach (var function in source.functions) {
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
				if (function.name == "raise") {
					raised = function.ordinal;
				}
			}
			assert (exercise >= 0 && raised >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			int fault = -1;
			foreach (var plan in native.classes) {
				if (plan.name == "Fault") {
					fault = plan.ordinal;
				}
			}
			assert (fault >= 0);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			artifact.verify ();
			if (profile == 0) {
				LlvmLifetimeTests.exception_catch (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)), CApi.named_function (artifact.module, "astra.fn.%d".printf (raised)), false, CApi.named_function (artifact.module, "astra.ctor.%d".printf (fault)));
			}
			if (profile != 0) {
				LlvmLifetimeTests.exception_forward (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)));
			}
			if (profile == 0) {
				LlvmLifetimeTests.exception_null_handles (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)));
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_exception_context_companion() {
	try {
		for (int profile = 0; profile < 3; profile++) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(){this.number=7;}deinit(){}}[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}void raise(borrowed Scoped context,owned ScopedLeaf input,int mode)throws Fault{query(context,7);if(mode!=0){throw new Fault(move input);}}void handled(borrowed Scoped context,owned ScopedLeaf input,int mode){try{raise(context,move input,mode);}catch(Fault error){}}";
			if (profile == 1) {
				text = text.replace ("void raise", "int raise").replace ("throw new Fault(move input);}}", "throw new Fault(move input);}return 17;}");
			}
			if (profile == 2) {
				text = text.replace ("int mode){try{", "int mode)throws Fault{try{").replace ("catch(Fault error){}", "catch(Fault error){throw;}");
			}
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "raise,handled")))));
			int raised = -1, handled = -1;
			foreach (var function in source.functions) {
				if (function.name == "raise") {
					raised = function.ordinal;
				}
				if (function.name == "handled") {
					handled = function.ordinal;
				}
			}
			assert (raised >= 0 && handled >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			var target = CApi.named_function (artifact.module, "astra.fn.%d".printf (raised));
			var relay = CApi.named_function (artifact.module, "astra.fn.%d".printf (handled));
			exception_context_roles (target, native.functions[raised], native.classes);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.checked_context (artifact, target, relay, true, profile == 1 ? 1 : 0, true);
			if (profile == 2) {
				LlvmLifetimeTests.exception_forward (artifact, relay, 1);
			} else {
				LlvmLifetimeTests.exception_catch (artifact, relay, target, false);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void exception_context_roles(CApi.ValueRef target, NativeFunction original, GenericArray<NativeClassPlan> classes) throws GLib.Error {
	for (int mode = 0; mode < 9; mode++) {
		var graph = new RuntimeLifetimeEquations ();
		int exceptional = graph.absent ();
		if (mode == 1 || mode == 2) {
			var roots = new GenericArray<RuntimeScopeOrigin> ();
			roots.add (mode == 1 ? new RuntimeScopeOrigin.context_input (0) : new RuntimeScopeOrigin.local (0, 0));
			exceptional = graph.product (roots, new HashTable<string, int> (str_hash, str_equal));
		} else {
			exceptional = graph.input (mode == 3 ? 0 : mode == 4 ? -1 : mode == 5 ? 77 : mode == 8 ? 2 : 1);
			if (mode == 6) {
				exceptional = graph.project (exceptional, "f0");
			}
			if (mode == 7) {
				exceptional = graph.replace (exceptional, "f0", graph.absent ());
			}
		} graph.seal ();
		var effect = new RuntimeLifetimeSummary (graph, graph.absent (), new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "", exceptional);
		if (mode == 2) {
			refusal_text (() => { effect.encode ();
			}, "cannot export a callee-local scope root");
			continue;
		}
		var candidate = new NativeFunction (original.span, original.name_span, original.name, original.ordinal, original.signature, original.linkage);
		candidate.bind_runtime_lifetimes (effect.encode ());
		var role = LlvmScopedContextInputs.from_native (target, CApi.global_value_type (target), candidate, classes);
		assert ((role != null) == (mode == 0));
		if (mode != 0) {
			Test.message ("exception context root role %d refused", mode);
		}
	}
}

private void llvm_exception_success_output() {
	try {
		for (int profile = 0; profile < 4; profile++) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(){this.number=7;}deinit(){}}[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}owned ScopedLeaf choose(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(move input);}return move input;}owned ScopedLeaf relay(owned ScopedLeaf input,int mode)throws Fault{return choose(move input,mode);}owned ScopedLeaf handled(owned ScopedLeaf input,int mode){try{return choose(move input,mode);}catch(Fault error){return null;}}";
			if (profile == 1) {
				text = text.replace ("owned ScopedLeaf input,int mode", "owned ScopedLeaf input,owned ScopedLeaf payload,int mode").replace ("new Fault(move input)", "new Fault(move payload)").replace ("choose(move input,mode)", "choose(move input,move payload,mode)");
			}
			if (profile >= 2) {
				text = text.replace ("owned ScopedLeaf input,int mode", "borrowed Scoped context,owned ScopedLeaf input,int mode").replace ("choose(move input,mode)", "choose(context,move input,mode)");
			}
			if (profile == 3) {
				text = text.replace ("if(mode!=0)", "query(context,7);if(mode!=0)");
			}
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "choose,relay,handled")))));
			int choose = -1, relay = -1, handled = -1;
			foreach (var function in source.functions) {
				if (function.name == "choose") {
					choose = function.ordinal;
				}
				if (function.name == "relay") {
					relay = function.ordinal;
				}
				if (function.name == "handled") {
					handled = function.ordinal;
				}
			}
			assert (choose >= 0 && relay >= 0 && handled >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			if (profile == 3) {
				artifact.verify ();
				Test.message ("dual context query positive");
				continue;
			}
			var target = CApi.named_function (artifact.module, "astra.fn.%d".printf (choose));
			var forward = CApi.named_function (artifact.module, "astra.fn.%d".printf (relay));
			LlvmLifetimeTests.exception_success (artifact, target, profile == 2 ? 2 : 1);
			LlvmLifetimeTests.checked_heap_caller (artifact, forward, target, profile == 2 ? 2 : 1, true);
			LlvmLifetimeTests.exception_catch (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (handled)), target, false, (CApi.ValueRef) null, false);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_exception_null_payload() {
	try {
		for (int profile = 0; profile < 4; profile++) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(){this.number=7;}deinit(){}}[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}void raise(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(move input);}}void exercise(owned ScopedLeaf retained,int mode){try{raise(null,mode);}catch(Fault error){}}";
			if (profile == 1) {
				text = text.replace ("raise(owned ScopedLeaf input,int mode)", "raise(owned ScopedLeaf input,owned ScopedLeaf consumed,int mode)").replace ("raise(null,mode)", "raise(null,move retained,mode)");
			}
			if (profile == 2) {
				text = text.replace ("void raise(owned ScopedLeaf input,int mode)", "owned ScopedLeaf raise(owned ScopedLeaf result,owned ScopedLeaf input,int mode)").replace ("throw new Fault(move input);}}", "throw new Fault(move input);}return move result;}").replace ("void exercise", "owned ScopedLeaf exercise").replace ("try{raise(null,mode);}", "try{return raise(move retained,null,mode);}").replace ("catch(Fault error){}", "catch(Fault error){return null;}");
			}
			if (profile == 3) {
				text = text.replace ("raise(owned", "raise(borrowed Scoped context,owned").replace ("exercise(owned", "exercise(borrowed Scoped context,owned").replace ("raise(null,mode)", "raise(context,null,mode)");
			}
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "raise,exercise")))));
			int raised = -1, exercise = -1;
			foreach (var function in source.functions) {
				if (function.name == "raise") {
					raised = function.ordinal;
				}
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
			}
			assert (raised >= 0 && exercise >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.exception_empty (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)), CApi.named_function (artifact.module, "astra.fn.%d".printf (raised)), profile == 3 ? 1 : 0, profile == 2 ? 2 : profile == 3 ? 1 : 0, profile == 1 || profile == 2, profile == 2);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_exception_repeated_retirement() {
	try {
		string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(){this.number=7;}deinit(){}}[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}void raise(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(move input);}}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "raise")))));
		int raised = -1;
		foreach (var function in source.functions) {
			if (function.name == "raise") {
				raised = function.ordinal;
			}
		}
		assert (raised >= 0);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		int fault = -1;
		foreach (var plan in native.classes) {
			if (plan.name == "Fault") {
				fault = plan.ordinal;
			}
		}
		assert (fault >= 0);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.exception_repeat (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (raised)), CApi.named_function (artifact.module, "astra.dtor.%d".printf (fault)), new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object"));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_borrowed_scalar_fields() {
	try {
		foreach (bool child in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedView{int number;i64 wide;init(int number){this.number=number;this.wide=7;}deinit(){}}int inspect(borrowed ScopedView view,int mode){if(view==null){return 0;}return view.number;}";
			if (child) {
				text = text.replace ("i64 wide;init(int number)", "i64 wide;private owned Plain child;init(int number,owned Plain child)").replace ("this.wide=7;", "this.wide=7;this.child=move child;") + "class Plain{init(){}}";
			} else {
				text += "int caller(owned ScopedView view){return inspect(view,0);}";
			}
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, child ? null : "caller")))));
			int inspect = -1;
			int caller = -1;
			foreach (var function in source.functions) {
				if (function.name == "inspect") {
					inspect = function.ordinal;
				}
				if (function.name == "caller") {
					caller = function.ordinal;
				}
			}
			assert (inspect >= 0 && (child || caller >= 0));
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.scalar_field_loan (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (inspect)), child ? (CApi.ValueRef) null : CApi.named_function (artifact.module, "astra.fn.%d".printf (caller)), child);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_checked_scoped_input() {
	try {
		foreach (string result in new string[] { "void", "int", "i64", "bool" }) {
			string body = result == "void" ? "" : "return " + (result == "bool" ? "mode==0" : "17") + ";";
			string prefix = result == "void" ? "" : "int marker,";
			string text = SCOPED_PROGRAM + "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}" + result + " checked(" + prefix + "owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(\"checked\");}" + body + "}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "checked")))));
			int ordinal = -1;
			foreach (var function in source.functions) {
				if (function.name == "checked") {
					ordinal = function.ordinal;
				}
			}
			assert (ordinal >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			var target = CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal));
			LlvmLifetimeTests.checked_input (artifact, target, result == "void" ? 0 : 2);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_fallible_scoped_input() {
	try {
		foreach (string mode in new string[] { "owned-affine", "owned-transfer", "owned-concurrent" }) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}owned ScopedLeaf refuse(borrowed Context parent,owned ScopedLeaf input){var host=try_new(parent)Host(move input);if(host==null){return move input;}return null;}";
			text = text.replace ("owned-concurrent", mode);
			var api = SCOPED_API + API.replace ("context_destroy", "astra_context17_destroy").replace ("owned-concurrent", mode);
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, api, "refuse")))));
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.fallible_input (artifact);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_mixed_scoped_input() {
	try {
		foreach (string mode in new string[] { "owned-affine", "owned-transfer", "owned-concurrent" }) {
			for (int shape = 0; shape < 4; shape++) {
				Test.message ("mixed context %s shape %d", mode, shape);
				string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}class Plain{int number;init(int number){this.number=number;}}[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{int marker;private owned Plain ordinary;private owned ScopedLeaf child;init(int marker,owned Plain ordinary,owned ScopedLeaf child){this.marker=marker;this.ordinary=move ordinary;this.child=move child;}}owned ScopedLeaf refuse(borrowed Context parent,owned ScopedLeaf input){var plain=new Plain(17);var host=try_new(parent)Host(9,move plain,move input);if(host==null){return move input;}return null;}";
				if (shape == 1) {
					text = text.replace ("class Host{", "class Host<T>{").replace ("owned ScopedLeaf child", "owned T child").replace ("Host(9,", "Host<ScopedLeaf>(9,");
				}
				if (shape == 2) {
					text = text.replace ("class Plain{int number;init(int number){this.number=number;}}", "class Deeper{int value;init(int value){this.value=value;}}class Plain{private owned Deeper nested;init(int number){var nested=new Deeper(number);this.nested=move nested;}}");
				}
				if (shape == 3) {
					text = text.replace ("borrowed Context parent,owned ScopedLeaf input", "borrowed Context parent,owned Plain plain,owned ScopedLeaf input").replace ("var plain=new Plain(17);", "");
				}
				text = text.replace ("owned-concurrent", mode);
				var api = SCOPED_API + API.replace ("context_destroy", "astra_context17_destroy").replace ("owned-concurrent", mode);
				SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, api, "refuse")))));
				var weak = WeakRef (source.functions[0]);
				NativeAbiProgram? native = NativeAbiBuilder.build (source);
				CAbiProgram? foreign = CAbiBuilder.build (source, native);
				int host = -1;
				foreach (var owner in native.classes) {
					if (owner.name.has_prefix ("Host")) {
						host = owner.ordinal;
					}
				}
				assert (host >= 0);
				string constructor = "astra.ctor.%d".printf (host);
				var artifact = LlvmLowering.lower (source, native, foreign);
				new LlvmTargetMachineArtifact (0).configure (artifact);
				source = null;
				native = null;
				foreign = null;
				assert (weak.get () == null);
				assert (artifact.has_scoped_owned_inputs (CApi.named_function (artifact.module, constructor)));
				LlvmLifetimeTests.fallible_input (artifact, constructor, 3, shape == 3 ? 2 : 1);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_graph_inventory() {
	try {
		string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}class Plain{int number;init(int number){this.number=number;}}class Middle{private owned Plain child;init(owned Plain child){this.child=move child;}}class Hidden{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}class Outer{private owned Hidden child;init(owned Hidden child){this.child=move child;}}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		var native = NativeAbiBuilder.build (source);
		source = null;
		assert (weak.get () == null);
		assert (native.classes.length == 5);
		for (int owner = 0; owner < 5; owner++) {
			assert (LlvmScopedClassGraph.scope_free (native.classes[owner], native.classes) == (owner == 1 || owner == 2));
			assert (LlvmScopedClassGraph.contains_scope (native.classes[owner], native) == (owner != 1 && owner != 2));
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_nested_formal_authority() {
	try {
		foreach (bool scoped in new bool[] { false, true }) {
			for (int depth = 1; depth <= 5; depth++) {
				string text = SCOPED_PROGRAM + (scoped ? "[Allocator(kind=\"context\",context=\"scoped-affine\")]" : "") + "class Leaf{init(){}}";
				string child = "Leaf";
				if (depth == 4) {
					text += "class GenericLayer<T>{private owned T child;init(owned T child){this.child=move child;}}";
					child = "GenericLayer<Leaf>";
				} else if (depth == 5) {
					text += "class Base{private owned Leaf child;init(owned Leaf child){this.child=move child;}}class Derived:Base{init(owned Leaf child):base(move child){}}";
					child = "Derived";
				} else {
					for (int level = 0; level < depth; level++) {
						string owner = "Layer%d".printf (level);
						text += "class %s{private owned %s child;init(owned %s child){this.child=move child;}}".printf (owner, child, child);
						child = owner;
					}
				}
				text += "int consume(owned %s input){return 0;}".printf (child);
				SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "consume")))));
				NativeAbiProgram? native = NativeAbiBuilder.build (source);
				CAbiProgram? foreign = CAbiBuilder.build (source, native);
				NativeFunction? target = null;
				foreach (var function in native.functions) {
					if (function.name == "consume") {
						target = function;
					}
				}
				assert (target != null && LlvmScopedOwnedInputs.required (target.signature, native) == scoped);
				if (scoped) {
					var policy = native.classes[0].allocation_policy;
					native.classes[0].allocation_policy = null;
					refusal_text (() => { LlvmScopedOwnedInputs.required (target.signature, native);
					}, "scoped Class graph lost its exact allocator policy");
					native.classes[0].allocation_policy = policy;
					if (depth == 5) {
						refusal_text (() => { LlvmLowering.lower (source, native, foreign);
						}, "scoped formal requires its complete emitted ABI authority");
					} else {
						var weak = WeakRef (source.functions[0]);
						int ordinal = target.ordinal;
						var artifact = LlvmLowering.lower (source, native, foreign);
						new LlvmTargetMachineArtifact (0).configure (artifact);
						source = null;
						native = null;
						foreign = null;
						assert (weak.get () == null);
						assert (artifact.has_scoped_owned_inputs (CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal))));
						artifact.verify ();
					}
				} else {
					var weak = WeakRef (source.functions[0]);
					var artifact = LlvmLowering.lower (source, native, foreign);
					new LlvmTargetMachineArtifact (0).configure (artifact);
					source = null;
					native = null;
					foreign = null;
					assert (weak.get () == null);
					artifact.verify ();
				}
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cfg_record_inputs() {
	try {
		foreach (bool scoped in new bool[] { false, true }) {
			foreach (bool wrapped in new bool[] { false, true }) {
				string text = SCOPED_PROGRAM + (scoped ? "[Allocator(kind=\"context\",context=\"scoped-affine\")]" : "") + "class Leaf{init(){}}struct Packet{owned Leaf left;owned Leaf right;int marker;}";
				text += wrapped ? "class Envelope{owned Packet packet;init(Packet packet){this.packet=move packet;}}int consume(owned Envelope input){return 0;}" : "int consume(Packet input){return 0;}";
				text += "int observe(borrowed Packet input){return input.marker;}";
				CoreProgram? original = CoreBuilder.build (check (text, SCOPED_API, "consume"));
				CoreProgram? source = CoreGenericMonomorphizer.build (original);
				original = null;
				var weak = WeakRef (source.functions[0]);
				var cfg = CfgBuilder.build (source);
				source = null;
				assert (weak.get () == null);
				CfgVerifier.verify (cfg);
				var summaries = CfgRuntimeLifetimes.analyze (cfg);
				foreach (var function in cfg.functions) {
					if (function.name == "consume" || function.name == "observe") {
						assert (summaries.lookup (function).complete && summaries.lookup (function).equations.requirements (summaries.lookup (function).result).length == 0);
					}
					if (function is CfgConstructor && function.struct_parameters.length != 0) {
						var summary = summaries.lookup (function);
						var updates = summary.updated_inputs ();
						assert (summary.complete && updates.length == 1 && updates[0] == -1);
						for (int field = 0; field < 2; field++) {
							var roots = summary.equations.requirements (summary.update (-1), "f0.f%d".printf (field));
							assert (roots.length == 1 && roots[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && roots[0].ordinal == field && roots[0].path == "");
						}
						assert (summary.equations.requirements (summary.update (-1), "f0.f2").length == 0);
					}
				}
				if (scoped) {
					cfg_record_input_controls (cfg);
				}
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cfg_record_input_controls(CfgProgram cfg) throws GLib.Error {
	foreach (var function in cfg.functions) {
		foreach (var group in function.struct_parameters) {
			CfgInstruction? binding = null;
			GenericArray<CfgValue>? leaves = null;
			CfgLocalPlace? destination = null;
			int position = -1;
			for (int i = 0; i < function.entry.instructions.length; i++) {
				var instruction = function.entry.instructions[i];
				var acquired = instruction as CfgStructBoundaryAcquire;
				var borrowed = instruction as CfgStructParameterBorrow;
				if (acquired != null && acquired.parameter == group) {
					binding = instruction;
					leaves = acquired.leaves;
					destination = acquired.destination;
					position = i;
				}
				if (borrowed != null && borrowed.parameter == group) {
					binding = instruction;
					leaves = borrowed.leaves;
					destination = borrowed.destination;
					position = i;
				}
			}
			assert (binding != null && leaves != null && leaves.length == 3 && position >= 0);
			var first = leaves[0];
			var second = leaves[1];
			leaves[0] = second;
			leaves[1] = first;
			refusal_text (() => CfgRuntimeLifetimes.verify (cfg), "original parameter leaf");
			leaves[0] = first;
			leaves[1] = second;
			leaves[0] = second;
			refusal_text (() => CfgRuntimeLifetimes.verify (cfg), "original parameter leaf");
			leaves[0] = first;
			var last = leaves[2];
			leaves.remove_index (2);
			refusal_text (() => CfgRuntimeLifetimes.verify (cfg), "complete entry acquisition or borrow");
			leaves.add (last);
			function.entry.instructions.remove_index ((uint) position);
			refusal_text (() => CfgRuntimeLifetimes.verify (cfg), "one original entry binding");
			function.entry.instructions.insert (position, binding);
			function.entry.instructions.insert (position, binding);
			refusal_text (() => CfgRuntimeLifetimes.verify (cfg), "one original entry binding");
			function.entry.instructions.remove_index ((uint) position);
			var path = group.shape.leaves[0];
			group.shape.leaves[0] = group.shape.leaves[1];
			refusal_text (() => CfgRuntimeLifetimes.verify (cfg), "record lifetime shape");
			group.shape.leaves[0] = path;
			var early = new CfgValidatePlace (binding.span, destination);
			function.entry.instructions.insert (0, early);
			refusal_text (() => CfgRuntimeLifetimes.verify (cfg), "entry binding must precede body operations");
			function.entry.instructions.remove_index (0);
		}
	}
	CfgVerifier.verify (cfg);
}

private void ssa_record_inputs() {
	try {
		foreach (bool scoped in new bool[] { true, false }) {
			foreach (bool wrapped in new bool[] { false, true }) {
				string text = SCOPED_PROGRAM + (scoped ? "[Allocator(kind=\"context\",context=\"scoped-affine\")]" : "") + "class Leaf{init(){}}struct Packet{owned Leaf left;owned Leaf right;int marker;}";
				text += wrapped ? "class Envelope{owned Packet packet;init(Packet packet){this.packet=move packet;}}int consume(owned Envelope input){return 0;}" : "int consume(Packet input){return 0;}";
				text += "int observe(borrowed Packet input){return input.marker;}";
				CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "consume"))));
				var weak = WeakRef (cfg.functions[0]);
				SsaProgram? source = SsaBuilder.build (cfg);
				cfg = null;
				assert (weak.get () == null);
				HashTable<SsaFunction, RuntimeLifetimeSummary>? summaries = SsaRuntimeLifetimes.analyze (source);
				foreach (var function in source.functions) {
					if (function.name == "consume" || function.name == "observe") {
						assert (summaries.lookup (function).complete && summaries.lookup (function).equations.requirements (summaries.lookup (function).result).length == 0);
					}
					if (function is SsaConstructor && function.struct_parameters.length != 0) {
						var summary = summaries.lookup (function);
						var updates = summary.updated_inputs ();
						assert (summary.complete && updates.length == 1 && updates[0] == -1);
						for (int field = 0; field < 2; field++) {
							var roots = summary.equations.requirements (summary.update (-1), "f0.f%d".printf (field));
							assert (roots.length == 1 && roots[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && roots[0].ordinal == field && roots[0].path == "");
						}
						assert (summary.equations.requirements (summary.update (-1), "f0.f2").length == 0);
					}
				}
				if (scoped) {
					ssa_record_input_controls (source);
				}
				NativeAbiProgram? native = NativeAbiBuilder.build (source);
				NativeFunction? target = null;
				foreach (var function in native.functions) {
					if (function.name == "consume") {
						target = function;
					}
				}
				assert (target != null && LlvmScopedOwnedInputs.required (target.signature, native) == scoped);
				CAbiProgram? foreign = CAbiBuilder.build (source, native);
				native_record_scope_inventory (native, target, scoped);
				if (scoped) {
					var policy = native.classes[0].allocation_policy;
					native.classes[0].allocation_policy = null;
					refusal_text (() => { LlvmScopedOwnedInputs.required (target.signature, native);
					}, "scoped Class graph lost its exact allocator policy");
					native.classes[0].allocation_policy = policy;
				}
				{
					var artifact = LlvmLowering.lower (source, native, foreign);
					new LlvmTargetMachineArtifact (0).configure (artifact);
					var detached = WeakRef (source.functions[0]);
					summaries = null;
					source = null;
					native = null;
					foreign = null;
					target = null;
					assert (detached.get () == null);
					artifact.verify ();
				}
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void ssa_record_input_controls(SsaProgram source) throws GLib.Error {
	foreach (var function in source.functions) {
		foreach (var group in function.struct_parameters) {
			SsaInstruction? binding = null;
			GenericArray<SsaValue>? leaves = null;
			SsaStructBoundaryAcquire? acquisition = null;
			int position = -1;
			for (int i = 0; i < function.entry.instructions.length; i++) {
				var instruction = function.entry.instructions[i];
				var acquired = instruction as SsaStructBoundaryAcquire;
				var borrowed = instruction as SsaStructParameterBorrow;
				if (acquired != null && acquired.parameter == group) {
					binding = instruction;
					acquisition = acquired;
					leaves = acquired.leaves;
					position = i;
				}
				if (borrowed != null && borrowed.parameter == group) {
					binding = instruction;
					leaves = borrowed.leaves;
					position = i;
				}
			}
			assert (binding != null && leaves != null && leaves.length == 3 && position >= 0);
			var first = leaves[0];
			var second = leaves[1];
			leaves[0] = second;
			leaves[1] = first;
			refusal_text (() => SsaRuntimeLifetimes.verify (source), "original parameter leaf");
			leaves[0] = first;
			leaves[1] = second;
			leaves[0] = second;
			refusal_text (() => SsaRuntimeLifetimes.verify (source), "original parameter leaf");
			leaves[0] = first;
			var last = leaves[2];
			leaves.remove_index (2);
			refusal_text (() => SsaRuntimeLifetimes.verify (source), "complete entry acquisition or borrow");
			leaves.add (last);
			function.entry.instructions.remove_index ((uint) position);
			refusal_text (() => SsaRuntimeLifetimes.verify (source), "one original entry binding");
			function.entry.instructions.insert (position, binding);
			function.entry.instructions.insert (position, binding);
			refusal_text (() => SsaRuntimeLifetimes.verify (source), "one original entry binding");
			function.entry.instructions.remove_index ((uint) position);
			var path = group.shape.leaves[0];
			group.shape.leaves[0] = group.shape.leaves[1];
			refusal_text (() => SsaRuntimeLifetimes.verify (source), "record lifetime shape");
			group.shape.leaves[0] = path;
			var early = new SsaNonNullUse (binding.span, first, 0, function.entry, 0);
			function.entry.instructions.insert (0, early);
			refusal_text (() => SsaRuntimeLifetimes.verify (source), "entry binding must precede body operations");
			function.entry.instructions.remove_index (0);
			if (acquisition != null) {
				assert (acquisition.owners.length == 2);
				var owner = acquisition.owners[0];
				var extent = owner.text_extent;
				owner.text_extent = null;
				refusal_text (() => SsaRuntimeLifetimes.verify (source), "extent");
				owner.text_extent = extent;
				int rank = owner.record_rank;
				owner.record_rank++;
				refusal_text (() => SsaRuntimeLifetimes.verify (source), "record");
				owner.record_rank = rank;
				var field = owner.record_field;
				owner.record_field = acquisition.owners[1].record_field;
				refusal_text (() => SsaRuntimeLifetimes.verify (source), "record");
				owner.record_field = field;
				var acquired_event = function.entry.instructions[position + 1];
				function.entry.instructions.remove_index ((uint) position + 1);
				function.entry.instructions.insert (position, acquired_event);
				refusal_text (() => SsaRuntimeLifetimes.verify (source), "immediate exact owner event");
				function.entry.instructions.remove_index ((uint) position);
				function.entry.instructions.insert (position + 1, acquired_event);
			}
		}
	}
	SsaVerifier.verify (source);
}

private void native_record_scope_inventory(NativeAbiProgram program, NativeFunction target, bool scoped) throws GLib.Error {
	// Discovery controls inspect copied type graphs; they do not admit these
	// detached signatures as executable native units or ownership contracts.
	var leaf = program.classes[0];
	assert (program.struct_values.length > 0);
	var record = program.struct_values[0];
	var callable = new NativeFunctionPointerType (NativeScalarType.I32, new GenericArray<NativeAbiType> ());
	NativeAbiType[] types = {
		new NativeSharedHandleType (leaf.name, false), new NativeSharedHandleType (leaf.name, true), new NativeClosureHandleType (leaf.name, callable), new NativeOwnerSlotsType (leaf.ordinal, leaf.name, leaf.destructor_ordinal), new NativeOwnerSlotsType (-1, record.struct_name, -1, NativeScalarType.PTR, NativeScalarType.I32, NativeScalarType.I32, null, record)
	};
	foreach (var type in types) {
		var parameters = new GenericArray<NativeParameter> ();
		parameters.add (new NativeParameter.typed (target.span, target.name_span, "value", 0, type));
		var signature = new NativeSignature (NativeAbiVersion.OWNER_SLOTS_V15, parameters, null);
		assert (LlvmScopedOwnedInputs.required (signature, program) == scoped);
	}
	foreach (bool missing_name in new bool[] { false, true }) {
		var parameters = new GenericArray<NativeParameter> ();
		parameters.add (new NativeParameter.typed (target.span, target.name_span, "invalid", 0, missing_name ? (NativeAbiType) new NativeSharedHandleType ("MissingRetainedDeclaration", false) : new NativeOwnerSlotsType (program.classes.length, "MissingSlotDeclaration", -1)));
		var signature = new NativeSignature (NativeAbiVersion.OWNER_SLOTS_V15, parameters, null);
		refusal_text (() => { LlvmScopedOwnedInputs.required (signature, program);
		}, missing_name ? "retained Class declaration" : "native Class origin");
	}
	if (scoped && target.signature.struct_parameters.length == 0) {
		var originals = new GenericArray<NativeStructValuePlan> ();
		foreach (var plan in program.struct_values) {
			originals.add (plan);
		}
		while (program.struct_values.length != 0) {
			program.struct_values.remove_index (0);
		}
		refusal_text (() => { LlvmScopedOwnedInputs.required (target.signature, program);
		}, "owning record declaration");
		foreach (var plan in originals) {
			program.struct_values.add (plan);
		}
		assert (LlvmScopedOwnedInputs.required (target.signature, program));
	}
}

private void llvm_record_owned_inputs() {
	try {
		for (int shape = 0; shape < 3; shape++) {
			string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}int consume(Packet input){return input.marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf left;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}int consume(Packet input){return 0;}" : "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}int consume(Packet<ScopedLeaf> input){return input.marker;}";
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}" + definition;
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int consume = -1;
			foreach (var function in source.functions) {
				if (function.name == "consume") {
					consume = function.ordinal;
				}
			}
			assert (consume >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.record_inputs (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (consume)), shape == 1 ? 2U : 1U);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_record_borrowed_inputs() {
	try {
		for (int shape = 0; shape < 3; shape++) {
			string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf leaf;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}" : "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}";
			string left = shape == 1 ? "input.first.leaf" : "input.left";
			string marker = shape == 1 ? "input.first.marker" : "input.marker";
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int value;init(int value){this.value=value;}int read(){return this.value;}}class Other{int value;init(int value){this.value=value;}int read(){return this.value;}}" + definition + "int observe(borrowed " + (shape == 2 ? "Packet<ScopedLeaf>" : "Packet") + " input){if(" + left + "==null||input.right==null){return 0;}return " + left + ".read()+input.right.read()+" + marker + ";}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int observe = -1;
			foreach (var function in source.functions) {
				if (function.name == "observe") {
					observe = function.ordinal;
				}
			}
			assert (observe >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.record_borrows (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (observe)), shape == 1 ? 2U : 1U);
		}
		llvm_record_borrow_coverage ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_record_borrow_coverage() throws GLib.Error {
	string prefix = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}";
	string copied = prefix + "struct Copied{i64 count;int offset;}int observe(borrowed Packet input,Copied copied){return input.marker+copied.offset;}";
	SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (copied, SCOPED_API)))));
	var weak = WeakRef (source.functions[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (source);
	CAbiProgram? foreign = CAbiBuilder.build (source, native);
	var artifact = LlvmLowering.lower (source, native, foreign);
	new LlvmTargetMachineArtifact (0).configure (artifact);
	source = null;
	native = null;
	foreign = null;
	assert (weak.get () == null);
	artifact.verify ();
	foreach (int kind in new int[] { 0, 2 }) {
		string parameter = kind == 0 ? "owned Wrapper owner" : "void* raw";
		string text = prefix + "class Wrapper{owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}int mixed(" + parameter + ",borrowed Packet input){return input.marker;}";
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, kind == 0 ? "mixed" : null)))));
		var plan = NativeAbiBuilder.build (ssa);
		var abi = CAbiBuilder.build (ssa, plan);
		refusal_text (() => { LlvmLowering.lower (ssa, plan, abi);
		}, "complete emitted ABI authority");
	}
}

private void llvm_record_context_inputs() {
	try {
		foreach (bool borrowed in new bool[] { false, true }) {
			for (int shape = 0; shape < 3; shape++) {
				string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf leaf;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}" : "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}";
				string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
				string marker = shape == 1 ? "input.first.marker" : "input.marker";
				string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}" + definition + "int consume(" + (borrowed ? "borrowed " : "") + record + " input,borrowed Scoped context){if(query(context,7)==0){return 0;}return " + marker + ";}";
				SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
				int consume = -1;
				foreach (var function in source.functions) {
					if (function.name == "consume") {
						consume = function.ordinal;
					}
				}
				assert (consume >= 0);
				var weak = WeakRef (source.functions[0]);
				NativeAbiProgram? native = NativeAbiBuilder.build (source);
				CAbiProgram? foreign = CAbiBuilder.build (source, native);
				var artifact = LlvmLowering.lower (source, native, foreign);
				new LlvmTargetMachineArtifact (0).configure (artifact);
				source = null;
				native = null;
				foreign = null;
				assert (weak.get () == null);
				LlvmLifetimeTests.record_context (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (consume)), shape == 1 ? 2U : 1U, borrowed);
			}
		}
		llvm_record_context_coverage ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_record_context_coverage() throws GLib.Error {
	string prefix = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}";
	foreach (bool borrowed in new bool[] { false, true }) {
		string record = (borrowed ? "borrowed " : "") + "Packet input";
		string text = prefix + "struct Copied{int marker;}int consume(borrowed Scoped first," + record + ",borrowed Scoped second,Copied copied){if(query(first,7)==query(second,7)){return input.marker+copied.marker;}return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		artifact.verify ();
		string invalid = prefix + "int mixed(borrowed Scoped context," + record + ",void* unknown){return input.marker;}";
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (invalid, SCOPED_API)))));
		var plan = NativeAbiBuilder.build (ssa);
		var abi = CAbiBuilder.build (ssa, plan);
		refusal_text (() => { LlvmLowering.lower (ssa, plan, abi);
		}, "complete emitted");
	}
}

private void llvm_mixed_record_inputs() {
	try {
		foreach (bool context in new bool[] { false, true }) {
			foreach (bool reversed in new bool[] { false, true }) {
				for (int shape = 0; shape < 3; shape++) {
					string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf leaf;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}" : "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}";
					string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
					string left = shape == 1 ? "observed.first.leaf" : "observed.left";
					string marker = shape == 1 ? "input.first.marker" : "input.marker";
					string parameters = reversed ? "borrowed " + record + " observed," + record + " input" : record + " input,borrowed " + record + " observed";
					string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int value;init(int value){this.value=value;}int read(){return this.value;}}" + definition + "int consume(" + parameters + (context ? ",borrowed Scoped context" : "") + "){if(" + left + "==null||observed.right==null){return " + marker + ";}return " + marker + "+" + left + ".read()+observed.right.read();}";
					SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
					int consume = -1;
					foreach (var function in source.functions) {
						if (function.name == "consume") {
							consume = function.ordinal;
						}
					}
					assert (consume >= 0);
					var weak = WeakRef (source.functions[0]);
					NativeAbiProgram? native = NativeAbiBuilder.build (source);
					CAbiProgram? foreign = CAbiBuilder.build (source, native);
					var artifact = LlvmLowering.lower (source, native, foreign);
					new LlvmTargetMachineArtifact (0).configure (artifact);
					source = null;
					native = null;
					foreign = null;
					assert (weak.get () == null);
					LlvmLifetimeTests.mixed_records (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (consume)), shape == 1 ? 2U : 1U, reversed, context);
				}
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void ssa_record_creation() {
	try {
		foreach (bool factory in new bool[] { false, true }) {
			for (int shape = 0; shape < 3; shape++) {
				Test.message ("record creation shape %d factory %d", shape, factory ? 1 : 0);
				string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf left;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}" : "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}";
				string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
				string marker = shape == 1 ? "input.first.marker" : "input.marker";
				string initialized = shape == 1 ? "first={left=move left,marker=17},right=move right" : "left=move left,right=move right,marker=17";
				if (factory) {
					initialized = initialized.replace ("move left", "identity(move left)").replace ("move right", "identity(move right)");
				}
				string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}owned ScopedLeaf identity(owned ScopedLeaf value){return move value;}" + definition + "int consume(" + record + " input,borrowed Scoped context){return " + marker + ";}int collect(owned ScopedLeaf left,owned ScopedLeaf right,borrowed Scoped context){" + record + " input={" + initialized + "};return consume(move input,context);}";
				CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API))));
				var detached = WeakRef (cfg.functions[0]);
				SsaProgram? source = SsaBuilder.build (cfg);
				cfg = null;
				assert (detached.get () == null);
				var summaries = SsaRuntimeLifetimes.analyze (source);
				foreach (var summary in summaries.get_values ()) {
					assert (summary.complete);
				}
				summaries = null;
				ssa_record_creation_controls (source, factory);
				var weak = WeakRef (source.functions[0]);
				NativeAbiProgram? native = NativeAbiBuilder.build (source);
				CAbiProgram? foreign = CAbiBuilder.build (source, native);
				var artifact = LlvmLowering.lower (source, native, foreign);
				new LlvmTargetMachineArtifact (0).configure (artifact);
				source = null;
				native = null;
				foreign = null;
				assert (weak.get () == null);
				artifact.verify ();
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void ssa_record_creation_controls(SsaProgram program, bool factory) throws GLib.Error {
	int count = 0;
	foreach (var function in program.functions) {
		foreach (var block in function.blocks) {
			for (int position = 0; position < block.instructions.length; position++) {
				var acquired = block.instructions[position] as SsaRecordAcquire;
				if (acquired == null) {
					continue;
				}
				count++;
				var owner = acquired.owner;
				var event = block.instructions[position + 1];
				var initialization = block.instructions[position + 2];
				var extent = owner.text_extent;
				owner.text_extent = null;
				refused (() => SsaRuntimeLifetimes.verify (program));
				owner.text_extent = extent;
				var forged = new SsaAddressableLocal (owner.record_type.span, owner.record_type.span, "forged.record.storage", owner.record_type.semantic_type, function.storage.length, owner.source_ordinal, owner.record_type);
				function.storage.add (forged);
				refused (() => SsaRuntimeLifetimes.verify (program));
				function.storage.remove_index (function.storage.length - 1);
				int rank = owner.record_rank;
				owner.record_rank = rank + 1;
				refused (() => SsaRuntimeLifetimes.verify (program));
				owner.record_rank = rank;
				var path = owner.record_path;
				owner.record_path = null;
				refused (() => SsaRuntimeLifetimes.verify (program));
				owner.record_path = path;
				var field = owner.record_field;
				owner.record_field = null;
				refused (() => SsaRuntimeLifetimes.verify (program));
				owner.record_field = field;
				acquired.fields.remove_index (0);
				refused (() => SsaRuntimeLifetimes.verify (program));
				acquired.fields.add (acquired.pointer);
				block.instructions[position + 1] = initialization;
				block.instructions[position + 2] = event;
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions[position + 1] = event;
				block.instructions[position + 2] = initialization;
				block.instructions.remove_index (position);
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions.insert (position, acquired);
				var actual = (SsaHeapOwnerEvent) event;
				foreach (int mode in new int[] { 0, 1, 2 }) {
					block.instructions[position + 1] = new SsaHeapOwnerEvent (actual.span, mode == 0 ? (factory ? function.heap_owners[0] : acquired.source_owner) : actual.owner, mode == 1 ? SsaHeapOwnerAction.READ : actual.action, actual.value, mode == 2 ? null : actual.effect);
					refused (() => SsaRuntimeLifetimes.verify (program));
					block.instructions[position + 1] = event;
				}
				SsaRuntimeLifetimes.verify (program);
			}
		}
	}
	assert (count == 2);
}

private void ssa_record_local_moves() {
	try {
		foreach (bool chained in new bool[] { false, true }) {
			for (int shape = 0; shape < 3; shape++) {
				Test.message ("record local move shape %d chain %d", shape, chained ? 1 : 0);
				string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf left;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}" : "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}";
				string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
				string marker = shape == 1 ? "input.first.marker" : "input.marker";
				string initialized = shape == 1 ? "first={left=move left,marker=17},right=move right" : "left=move left,right=move right,marker=17";
				string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}" + definition + "int consume(" + record + " input,borrowed Scoped context){return " + marker + ";}int collect(owned ScopedLeaf left,owned ScopedLeaf right,borrowed Scoped context){" + record + " input={" + initialized + "};" + record + " moved=move input;" + (chained ? record + " final=move moved;return consume(move final,context);}" : "return consume(move moved,context);}");
				CfgProgram? cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API))));
				var detached = WeakRef (cfg.functions[0]);
				SsaProgram? source = SsaBuilder.build (cfg);
				cfg = null;
				assert (detached.get () == null);
				var summaries = SsaRuntimeLifetimes.analyze (source);
				foreach (var summary in summaries.get_values ()) {
					assert (summary.complete);
				}
				summaries = null;
				ssa_record_move_controls (source, chained ? 4 : 2);
				var weak = WeakRef (source.functions[0]);
				NativeAbiProgram? native = NativeAbiBuilder.build (source);
				CAbiProgram? foreign = CAbiBuilder.build (source, native);
				var artifact = LlvmLowering.lower (source, native, foreign);
				new LlvmTargetMachineArtifact (0).configure (artifact);
				source = null;
				native = null;
				foreign = null;
				assert (weak.get () == null);
				artifact.verify ();
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void ssa_record_move_controls(SsaProgram program, int expected) throws GLib.Error {
	int count = 0;
	foreach (var function in program.functions) {
		foreach (var block in function.blocks) {
			for (int position = 0; position < block.instructions.length; position++) {
				var moved = block.instructions[position] as SsaRecordMove;
				if (moved == null) {
					continue;
				}
				count++;
				var owner = moved.destination;
				var released = block.instructions[position + 1];
				var acquired = block.instructions[position + 2];
				var extent = owner.text_extent;
				owner.text_extent = null;
				refused (() => SsaRuntimeLifetimes.verify (program));
				owner.text_extent = extent;
				var path = owner.record_path;
				owner.record_path = null;
				refused (() => SsaRuntimeLifetimes.verify (program));
				owner.record_path = path;
				var field = owner.record_field;
				owner.record_field = null;
				refused (() => SsaRuntimeLifetimes.verify (program));
				owner.record_field = field;
				int rank = owner.record_rank;
				owner.record_rank = rank + 1;
				refused (() => SsaRuntimeLifetimes.verify (program));
				owner.record_rank = rank;
				moved.fields.remove_index (0);
				refused (() => SsaRuntimeLifetimes.verify (program));
				moved.fields.add (moved.pointer);
				block.instructions[position + 1] = acquired;
				block.instructions[position + 2] = released;
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions[position + 1] = released;
				block.instructions[position + 2] = acquired;
				block.instructions.remove_index (position);
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions.insert (position, moved);
				for (int i = 0; i < 3; i++) {
					block.instructions.remove_index (position);
				}
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions.insert (position, moved);
				block.instructions.insert (position + 1, released);
				block.instructions.insert (position + 2, acquired);
				var actual = (SsaHeapOwnerEvent) released;
				block.instructions[position + 1] = new SsaHeapOwnerEvent (actual.span, actual.owner, SsaHeapOwnerAction.ACQUIRE, actual.value, actual.effect);
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions[position + 1] = released;
				actual = (SsaHeapOwnerEvent) acquired;
				block.instructions[position + 2] = new SsaHeapOwnerEvent (actual.span, moved.source, actual.action, actual.value, actual.effect);
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions[position + 2] = acquired;
				var values = new GenericArray<SsaValue> ();
				var zero = new SsaNullPointerConstant (moved.span, moved.pointer.semantic_type);
				values.add (zero);
				var dropped = new SsaRecordMove (moved.span, moved.source, moved.destination, zero, values);
				block.instructions[position] = dropped;
				block.instructions[position + 1] = new SsaHeapOwnerEvent (released.span, moved.source, SsaHeapOwnerAction.MOVE, zero, dropped);
				block.instructions[position + 2] = new SsaHeapOwnerEvent (acquired.span, moved.destination, SsaHeapOwnerAction.ACQUIRE, zero);
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions[position] = moved;
				block.instructions[position + 1] = released;
				block.instructions[position + 2] = acquired;
				SsaRuntimeLifetimes.verify (program);
			}
		}
	}
	assert (count == expected);
}

private void cfg_record_results() {
	try {
		for (int shape = 0; shape < 3; shape++) {
			string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf left;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}" : "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}";
			string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
			string initialized = shape == 1 ? "first={left=move left,marker=17},right=move right" : "left=move left,right=move right,marker=17";
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}" + definition + record + " create(owned ScopedLeaf left,owned ScopedLeaf right){" + record + " input={" + initialized + "};return move input;}";
			CoreProgram? original = CoreBuilder.build (check (text, SCOPED_API));
			CoreProgram? core = CoreGenericMonomorphizer.build (original);
			original = null;
			var detached = WeakRef (core.functions[0]);
			var cfg = CfgBuilder.build (core);
			core = null;
			assert (detached.get () == null);
			var summaries = CfgRuntimeLifetimes.analyze (cfg);
			foreach (var function in cfg.functions) {
				if (function.name != "create") {
					continue;
				}
				var summary = summaries.lookup (function);
				assert (summary.complete && summary.store_count == 0 && summary.updated_inputs ().length == 0);
				string left = shape == 1 ? "f0.f0" : "f0";
				string right = "f1";
				var first = summary.equations.requirements (summary.result, left);
				var second = summary.equations.requirements (summary.result, right);
				assert (first.length == 1 && first[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && first[0].ordinal == 0 && first[0].path == "");
				assert (second.length == 1 && second[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && second[0].ordinal == 1 && second[0].path == "");
			}
			summaries = null;
			cfg_record_result_controls (cfg);
			SsaBuilder.build (cfg);
		}
		string copied = SCOPED_PROGRAM + "struct Plain{i64 wide;int marker;}Plain create_copy(){Plain result={wide=17,marker=23};return result;}";
		CoreProgram? original = CoreBuilder.build (check (copied, SCOPED_API));
		CoreProgram? core = CoreGenericMonomorphizer.build (original);
		original = null;
		var weak = WeakRef (core.functions[0]);
		var cfg = CfgBuilder.build (core);
		core = null;
		assert (weak.get () == null);
		var summaries = CfgRuntimeLifetimes.analyze (cfg);
		foreach (var function in cfg.functions) {
			if (function.name == "create_copy") {
				var summary = summaries.lookup (function);
				assert (summary.complete && summary.equations.requirements (summary.result).length == 0);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cfg_record_result_controls(CfgProgram program) throws GLib.Error {
	int count = 0;
	foreach (var function in program.functions) {
		foreach (var block in function.blocks) {
			var returned = block.terminator as CfgStructReturn;
			if (returned == null) {
				continue;
			}
			count++;
			var moved = returned.record_move;
			assert (moved != null);
			int position = 0;
			while (block.instructions[position] != moved) {
				position++;
			}
			returned.record_move = null;
			refused (() => CfgRuntimeLifetimes.verify (program));
			returned.record_move = moved;
			moved.consumer = null;
			refused (() => CfgRuntimeLifetimes.verify (program));
			moved.consumer = returned;
			var first = returned.leaves[0];
			var last = returned.leaves[1];
			returned.leaves[0] = last;
			returned.leaves[1] = first;
			refused (() => CfgRuntimeLifetimes.verify (program));
			returned.leaves[0] = first;
			returned.leaves[1] = last;
			returned.leaves[1] = first;
			refused (() => CfgRuntimeLifetimes.verify (program));
			returned.leaves[1] = last;
			var omitted = returned.leaves[returned.leaves.length - 1];
			returned.leaves.remove_index (returned.leaves.length - 1);
			refused (() => CfgRuntimeLifetimes.verify (program));
			returned.leaves.add (omitted);
			block.instructions.remove_index (position);
			refused (() => CfgRuntimeLifetimes.verify (program));
			block.instructions.insert (position, moved);
			block.instructions.insert (position, moved);
			refused (() => CfgRuntimeLifetimes.verify (program));
			block.instructions.remove_index (position);
			var capture = (CfgEvaluateInstruction) block.instructions[position - returned.leaves.length];
			assert (capture.result == first);
			var field = ((CfgLoadValue) capture.value).source;
			var changed = new CfgStore (moved.span, field, new CfgNullPointerValue (moved.span, field.semantic_type));
			block.instructions.insert (position, changed);
			refusal_text (() => CfgRuntimeLifetimes.verify (program), "unchanged exact captured field storage");
			block.instructions.remove_index (position);
			var wrong = new CfgStructBoundaryMove (moved.span, moved.source, moved.shape, moved.leaves, StructResultUseKind.ARGUMENT);
			wrong.consumer = returned;
			returned.record_move = wrong;
			block.instructions[position] = wrong;
			refused (() => CfgRuntimeLifetimes.verify (program));
			block.instructions[position] = moved;
			returned.record_move = moved;
			CfgRuntimeLifetimes.verify (program);
		}
	}
	assert (count == 1);
}

private void ssa_record_results() {
	try {
		for (int shape = 0; shape < 3; shape++) {
			string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf left;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}" : "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}";
			string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
			string initialized = shape == 1 ? "first={left=move left,marker=17},right=move right" : "left=move left,right=move right,marker=17";
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}" + definition + record + " create(owned ScopedLeaf left,owned ScopedLeaf right){" + record + " input={" + initialized + "};return move input;}";
			CfgProgram? original = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API))));
			var weak = WeakRef (original.functions[0]);
			var ssa = SsaBuilder.build (original);
			original = null;
			assert (weak.get () == null);
			var summaries = SsaRuntimeLifetimes.analyze (ssa);
			foreach (var function in ssa.functions) {
				if (function.name != "create") {
					continue;
				}
				var summary = summaries.lookup (function);
				assert (summary.complete && summary.store_count == 0 && summary.updated_inputs ().length == 0);
				var first = summary.equations.requirements (summary.result, shape == 1 ? "f0.f0" : "f0");
				var second = summary.equations.requirements (summary.result, "f1");
				assert (first.length == 1 && first[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && first[0].ordinal == 0 && first[0].path == "");
				assert (second.length == 1 && second[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && second[0].ordinal == 1 && second[0].path == "");
			}
			summaries = null;
			ssa_record_result_controls (ssa);
			var native = NativeAbiBuilder.build (ssa);
			var abi = CAbiBuilder.build (ssa, native);
			var artifact = LlvmLowering.lower (ssa, native, abi);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			artifact.verify ();
		}
		string copied = SCOPED_PROGRAM + "struct Plain{i64 wide;int marker;}Plain create_copy(){Plain result={wide=17,marker=23};return result;}";
		var scalar = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (copied, SCOPED_API)))));
		var effects = SsaRuntimeLifetimes.analyze (scalar);
		foreach (var function in scalar.functions) {
			if (function.name == "create_copy") {
				var effect = effects.lookup (function);
				assert (effect.complete && effect.equations.requirements (effect.result).length == 0);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void ssa_record_result_controls(SsaProgram program) throws GLib.Error {
	int count = 0;
	foreach (var function in program.functions) {
		foreach (var block in function.blocks) {
			var returned = block.terminator as SsaStructReturn;
			if (returned == null) {
				continue;
			}
			count++;
			var moved = returned.record_move;
			assert (moved != null);
			int position = 0;
			while (block.instructions[position] != moved) {
				position++;
			}
			returned.record_move = null;
			refused (() => SsaRuntimeLifetimes.verify (program));
			returned.record_move = moved;
			moved.consumer = null;
			refused (() => SsaRuntimeLifetimes.verify (program));
			moved.consumer = returned;
			var first = returned.leaves[0];
			var last = returned.leaves[1];
			returned.leaves[0] = last;
			returned.leaves[1] = first;
			refused (() => SsaRuntimeLifetimes.verify (program));
			returned.leaves[0] = first;
			returned.leaves[1] = last;
			returned.leaves[1] = first;
			refused (() => SsaRuntimeLifetimes.verify (program));
			returned.leaves[1] = last;
			var omitted = returned.leaves[returned.leaves.length - 1];
			returned.leaves.remove_index (returned.leaves.length - 1);
			refused (() => SsaRuntimeLifetimes.verify (program));
			returned.leaves.add (omitted);
			returned.leaves[0] = new SsaNullPointerConstant (returned.span, first.semantic_type);
			refused (() => SsaRuntimeLifetimes.verify (program));
			returned.leaves[0] = first;
			block.instructions.remove_index (position);
			refused (() => SsaRuntimeLifetimes.verify (program));
			block.instructions.insert (position, moved);
			block.instructions.insert (position, moved);
			refused (() => SsaRuntimeLifetimes.verify (program));
			block.instructions.remove_index (position);
			var owner = moved.owners[0];
			var extent = owner.text_extent;
			owner.text_extent = null;
			refused (() => SsaRuntimeLifetimes.verify (program));
			owner.text_extent = extent;
			var actual = (SsaHeapOwnerEvent) block.instructions[position + 1];
			block.instructions[position + 1] = new SsaHeapOwnerEvent (actual.span, actual.owner, SsaHeapOwnerAction.READ, actual.value, actual.effect);
			refused (() => SsaRuntimeLifetimes.verify (program));
			block.instructions[position + 1] = actual;
			SsaRuntimeLifetimes.verify (program);
		}
	}
	assert (count == 1);
}

private void cfg_record_producers() {
	try {
		for (int shape = 0; shape < 3; shape++) {
			string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf left;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}" : "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}";
			string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
			string initialized = shape == 1 ? "first={left=move left,marker=17},right=move right" : "left=move left,right=move right,marker=17";
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}" + definition + record + " create(owned ScopedLeaf left,owned ScopedLeaf right){" + record + " result={" + initialized + "};return move result;}" + record + " relay(owned ScopedLeaf left,owned ScopedLeaf right,borrowed Scoped context){" + record + " result=create(move left,move right);return move result;}";
			CoreProgram? original = CoreBuilder.build (check (text, SCOPED_API));
			CoreProgram? core = CoreGenericMonomorphizer.build (original);
			original = null;
			var weak = WeakRef (core.functions[0]);
			var cfg = CfgBuilder.build (core);
			core = null;
			assert (weak.get () == null);
			var effects = CfgRuntimeLifetimes.analyze (cfg);
			foreach (var function in cfg.functions) {
				if (function.name == "relay") {
					var effect = effects.lookup (function);
					assert (effect.complete);
					var first = effect.equations.requirements (effect.result, shape == 1 ? "f0.f0" : "f0");
					var second = effect.equations.requirements (effect.result, "f1");
					assert (first.length == 1 && first[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && first[0].ordinal == 0 && first[0].path == "");
					assert (second.length == 1 && second[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && second[0].ordinal == 1 && second[0].path == "");
				}
			}
			effects = null;
			cfg_record_producer_controls (cfg);
			SsaBuilder.build (cfg);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cfg_checked_record_producers() {
	checked_record_producers_profile (false);
}

private void ssa_checked_record_producers() {
	checked_record_producers_profile (true);
}

private void llvm_checked_record_error_payload() {
	for (int payload = 1; payload <= 2; payload++) {
		checked_record_producers_profile (true, payload);
	}
}

private void checked_record_error_roots(RuntimeLifetimeSummary summary, int shape, int payload) throws GLib.Error {
	if (payload == 0) {
		return;
	}
	var first = summary.equations.requirements (summary.exception, "f0");
	assert (first.length == 1 && first[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && first[0].ordinal == (payload == 1 && shape != 3 ? 2 : 1) && first[0].path == "" && first[0].descendants && first[0].exclusion_count == 0);
	if (payload == 2) {
		var second = summary.equations.requirements (summary.exception, "f1");
		if (shape == 3) {
			assert (second.length == 0);
		} else {
			assert (second.length == 1 && second[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && second[0].ordinal == 2 && second[0].path == "" && second[0].descendants && second[0].exclusion_count == 0);
		}
	}
}

private void checked_record_producers_profile(bool ssa_profile, int error_payload = 0) {
	try {
		for (int shape = 0; shape < 4; shape++) {
			for (int companion = 0; companion < 2; companion++) {
				string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf left;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}" : shape == 2 ? "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}" : "struct Packet{owned ScopedLeaf left;}";
				string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
				string initialized = shape == 1 ? "first={left=move left,marker=17},right=move right" : shape == 3 ? "left=move left" : "left=move left,right=move right,marker=17";
				string parameters = "int mode,owned ScopedLeaf left" + (shape == 3 ? "" : ",owned ScopedLeaf right") + (companion == 0 ? "" : ",borrowed Scoped context");
				string arguments = "mode,move left" + (shape == 3 ? "" : ",move right") + (companion == 0 ? "" : ",context");
				string fault = error_payload == 0 ? "[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}" : error_payload == 1 ? "[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"failed\";}}}" : "[ExceptionRoot]class Fault{private owned ScopedLeaf first;private owned ScopedLeaf second;init(owned ScopedLeaf first,owned ScopedLeaf second){this.first=move first;this.second=move second;}virtual property string message{get{return \"failed\";}}}";
				string fault_arguments = error_payload == 0 ? "" : error_payload == 1 ? (shape == 3 ? "move left" : "move right") : (shape == 3 ? "move left,null" : "move left,move right");
				string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}" + fault + definition + record + " create(" + parameters + ")throws Fault{if(mode!=0){throw new Fault(" + fault_arguments + ");}" + record + " result={" + initialized + "};return move result;}" + record + " relay(" + parameters + ")throws Fault{" + record + " result=create(" + arguments + ");" + (ssa_profile ? "if(mode==17){return move result;}" : "") + "return move result;}";
				CoreProgram? original = CoreBuilder.build (check (text, SCOPED_API));
				CoreProgram? core = CoreGenericMonomorphizer.build (original);
				original = null;
				var weak = WeakRef (core.functions[0]);
				var cfg = CfgBuilder.build (core);
				core = null;
				assert (weak.get () == null);
				var effects = CfgRuntimeLifetimes.analyze (cfg);
				foreach (var function in cfg.functions) {
					if (function.name != "relay") {
						continue;
					}
					var effect = effects.lookup (function);
					assert (effect.complete && effect.has_exception && effect.equations.requirements (effect.exception).length == (error_payload == 0 ? 0 : error_payload == 1 || shape == 3 ? 1 : 2));
					checked_record_error_roots (effect, shape, error_payload);
					var first = effect.equations.requirements (effect.result, shape == 1 ? "f0.f0" : "f0");
					assert (first.length == 1 && first[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && first[0].ordinal == 1 && first[0].path == "");
					if (shape != 3) {
						var second = effect.equations.requirements (effect.result, "f1");
						assert (second.length == 1 && second[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && second[0].ordinal == 2 && second[0].path == "");
					}
				}
				effects = null;
				if (!ssa_profile) {
					cfg_checked_record_controls (cfg);
					SsaBuilder.build (cfg);
				} else {
					ssa_checked_record_profile (cfg, shape, error_payload);
				}
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cfg_checked_record_controls(CfgProgram program) throws GLib.Error {
	int sites = 0;
	foreach (var function in program.functions) {
		if (function.name != "relay") {
			continue;
		}
		foreach (var producer in function.blocks) {
			for (int p = 0; p < producer.instructions.length; p++) {
				var call = producer.instructions[p] as CfgCallInstruction;
				if (call == null || call.struct_result == null) {
					continue;
				}
				sites++;
				var branch = (CfgConditionalBranch) producer.terminator;
				var success = branch.true_target;
				var marker = (CfgGroupCallSuccess) success.instructions[0];
				var consumed = (CfgStructResultConsume) success.instructions[1];
				var acquired = (CfgStructBoundaryAcquire) success.instructions[2];
				success.instructions.remove_index (0);
				refused (() => CfgRuntimeLifetimes.verify (program));
				success.instructions.insert (0, marker);
				success.instructions.insert (0, marker);
				refused (() => CfgRuntimeLifetimes.verify (program));
				success.instructions.remove_index (0);
				success.instructions.remove_index (0);
				success.instructions.insert (1, marker);
				refused (() => CfgRuntimeLifetimes.verify (program));
				success.instructions.remove_index (1);
				success.instructions.insert (0, marker);
				var unrelated = new CfgCallInstruction (call.span, call.target, call.arguments, call.result, call.receiver);
				success.instructions[0] = new CfgGroupCallSuccess (marker.span, unrelated);
				refused (() => CfgRuntimeLifetimes.verify (program));
				success.instructions[0] = marker;
				var exception = call.exception_result;
				call.exception_result = null;
				refused (() => CfgRuntimeLifetimes.verify (program));
				call.exception_result = new CfgEvaluatedValue (exception.span, exception.semantic_type);
				refused (() => CfgRuntimeLifetimes.verify (program));
				call.exception_result = exception;
				producer.instructions.add (marker);
				refused (() => CfgRuntimeLifetimes.verify (program));
				producer.instructions.remove_index (producer.instructions.length - 1);
				var leaf = call.struct_result.leaves[0];
				var early = new CfgEvaluateInstruction (leaf.span, leaf, new CfgEvaluatedValue (leaf.span, leaf.semantic_type));
				producer.instructions.insert (p, early);
				refusal_text (() => CfgRuntimeLifetimes.verify (program), "leaf escaped its exact success publication block");
				producer.instructions.remove_index (p);
				success.instructions.remove_index (1);
				producer.instructions.insert (p, consumed);
				refused (() => CfgRuntimeLifetimes.verify (program));
				producer.instructions.remove_index (p);
				success.instructions.insert (1, consumed);
				success.instructions.insert (1, consumed);
				refused (() => CfgRuntimeLifetimes.verify (program));
				success.instructions.remove_index (1);
				success.instructions.remove_index (2);
				refused (() => CfgRuntimeLifetimes.verify (program));
				success.instructions.insert (2, acquired);
				acquired.leaves[0] = new CfgCallResultValue (leaf.span, leaf.semantic_type);
				refused (() => CfgRuntimeLifetimes.verify (program));
				acquired.leaves[0] = leaf;
				CfgRuntimeLifetimes.verify (program);
			}
		}
	}
	assert (sites == 1);
}

private void ssa_checked_record_profile(CfgProgram cfg, int shape, int error_payload) throws GLib.Error {
	SsaProgram? source = SsaBuilder.build (cfg);
	var effects = SsaRuntimeLifetimes.analyze (source);
	int create = -1, relay = -1;
	foreach (var function in source.functions) {
		if (function.name == "create") {
			create = function.ordinal;
		}
		if (function.name != "relay") {
			continue;
		}
		relay = function.ordinal;
		var effect = effects.lookup (function);
		assert (effect.complete && effect.has_exception && effect.equations.requirements (effect.exception).length == (error_payload == 0 ? 0 : error_payload == 1 || shape == 3 ? 1 : 2));
		checked_record_error_roots (effect, shape, error_payload);
		var first = effect.equations.requirements (effect.result, shape == 1 ? "f0.f0" : "f0");
		assert (first.length == 1 && first[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && first[0].ordinal == 1 && first[0].path == "");
		if (shape != 3) {
			var second = effect.equations.requirements (effect.result, "f1");
			assert (second.length == 1 && second[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && second[0].ordinal == 2 && second[0].path == "");
		}
	}
	effects = null;
	assert (create >= 0 && relay >= 0);
	ssa_checked_record_controls (source);
	var weak = WeakRef (source.functions[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (source);
	int fault = -1;
	foreach (var owner in native.classes) {
		if (owner.name == "Fault") {
			fault = owner.ordinal;
		}
	}
	assert (fault >= 0);
	CAbiProgram? foreign = CAbiBuilder.build (source, native);
	var artifact = LlvmLowering.lower (source, native, foreign);
	new LlvmTargetMachineArtifact (0).configure (artifact);
	source = null;
	native = null;
	foreign = null;
	assert (weak.get () == null);
	artifact.verify ();
	var caller = CApi.named_function (artifact.module, "astra.fn.%d".printf (relay));
	if (shape != 3) {
		LlvmLifetimeTests.checked_record_result (artifact, caller, CApi.named_function (artifact.module, "astra.fn.%d".printf (create)), error_payload == 0 ? (CApi.ValueRef) null : CApi.named_function (artifact.module, "astra.dtor.%d".printf (fault)));
	} else if (!artifact.has_scoped_context_inputs (caller)) {
		LlvmLifetimeTests.checked_heap_caller (artifact, caller, CApi.named_function (artifact.module, "astra.fn.%d".printf (create)), 2, error_payload != 0);
	}
}

private void ssa_checked_record_controls(SsaProgram program) throws GLib.Error {
	int sites = 0;
	foreach (var function in program.functions) {
		if (function.name != "relay") {
			continue;
		}
		foreach (var producer in function.blocks) {
			for (int p = 0; p < producer.instructions.length; p++) {
				var call = producer.instructions[p] as SsaCallInstruction;
				if (call == null || call.struct_result == null) {
					continue;
				}
				sites++;
				var branch = (SsaConditionalBranch) producer.terminator;
				var success = branch.true_edge.target;
				var marker = (SsaGroupCallSuccess) success.instructions[0];
				var consumed = (SsaStructResultConsume) success.instructions[1];
				var acquired = (SsaStructBoundaryAcquire) success.instructions[2];
				success.instructions.remove_index (0);
				refused (() => SsaRuntimeLifetimes.verify (program));
				success.instructions.insert (0, marker);
				success.instructions.insert (0, marker);
				refused (() => SsaRuntimeLifetimes.verify (program));
				success.instructions.remove_index (0);
				success.instructions.remove_index (0);
				success.instructions.insert (1, marker);
				refused (() => SsaRuntimeLifetimes.verify (program));
				success.instructions.remove_index (1);
				success.instructions.insert (0, marker);
				var unrelated = new SsaCallInstruction (call.span, call.result == null ? null : call.result.semantic_type, call.result == null ? -1 : call.result.ordinal, call.target, call.arguments, call.receiver);
				success.instructions[0] = new SsaGroupCallSuccess (marker.span, unrelated);
				refused (() => SsaRuntimeLifetimes.verify (program));
				success.instructions[0] = marker;
				var exception = call.exception_result;
				call.exception_result = null;
				refused (() => SsaRuntimeLifetimes.verify (program));
				call.exception_result = new SsaInstructionResult (exception.span, exception.semantic_type, exception.ordinal);
				refused (() => SsaRuntimeLifetimes.verify (program));
				call.exception_result = exception;
				producer.instructions.add (marker);
				refused (() => SsaRuntimeLifetimes.verify (program));
				producer.instructions.remove_index (producer.instructions.length - 1);
				var leaf = call.struct_result.leaves[0];
				var early = new SsaObjectValidateInstruction (leaf.span, leaf, leaf.semantic_type, 900);
				producer.instructions.insert (p, early);
				refused (() => SsaRuntimeLifetimes.verify (program));
				producer.instructions.remove_index (p);
				success.instructions.remove_index (1);
				producer.instructions.insert (p, consumed);
				refused (() => SsaRuntimeLifetimes.verify (program));
				producer.instructions.remove_index (p);
				success.instructions.insert (1, consumed);
				success.instructions.insert (1, consumed);
				refused (() => SsaRuntimeLifetimes.verify (program));
				success.instructions.remove_index (1);
				success.instructions.remove_index (2);
				refused (() => SsaRuntimeLifetimes.verify (program));
				success.instructions.insert (2, acquired);
				acquired.leaves[0] = new SsaNullPointerConstant (leaf.span, leaf.semantic_type);
				refused (() => SsaRuntimeLifetimes.verify (program));
				acquired.leaves[0] = leaf;
				SsaRuntimeLifetimes.verify (program);
			}
		}
	}
	assert (sites == 1);
}

private void cfg_record_producer_controls(CfgProgram program) throws GLib.Error {
	int count = 0;
	foreach (var function in program.functions) {
		foreach (var block in function.blocks) {
			for (int position = 0; position < block.instructions.length; position++) {
				var acquired = block.instructions[position] as CfgStructBoundaryAcquire;
				if (acquired == null || acquired.results == null) {
					continue;
				}
				count++;
				var consumed = (CfgStructResultConsume) block.instructions[position - 1];
				var results = acquired.results;
				CfgCallInstruction? call = null;
				int call_at = -1;
				for (int i = 0; i < position; i++) {
					var candidate = block.instructions[i] as CfgCallInstruction;
					if (candidate != null && candidate.struct_result == results) {
						call = candidate;
						call_at = i;
					}
				}
				assert (call != null);
				block.instructions.remove_index (position - 1);
				refused (() => CfgRuntimeLifetimes.verify (program));
				block.instructions.insert (position - 1, consumed);
				block.instructions.insert (position - 1, consumed);
				refused (() => CfgRuntimeLifetimes.verify (program));
				block.instructions.remove_index (position - 1);
				block.instructions[position - 1] = new CfgStructResultConsume (consumed.span, results, StructResultUseKind.OBSERVE, consumed.destination);
				refused (() => CfgRuntimeLifetimes.verify (program));
				block.instructions[position - 1] = consumed;
				block.instructions.remove_index (position - 1);
				block.instructions.insert (call_at, consumed);
				refused (() => CfgRuntimeLifetimes.verify (program));
				block.instructions.remove_index (call_at);
				block.instructions.insert (position - 1, consumed);
				var leaf = acquired.leaves[0];
				acquired.leaves[0] = acquired.leaves[1];
				refused (() => CfgRuntimeLifetimes.verify (program));
				acquired.leaves[0] = leaf;
				var omitted = acquired.leaves[acquired.leaves.length - 1];
				acquired.leaves.remove_index (acquired.leaves.length - 1);
				refused (() => CfgRuntimeLifetimes.verify (program));
				acquired.leaves.add (omitted);
				call.struct_result = null;
				refused (() => CfgRuntimeLifetimes.verify (program));
				call.struct_result = results;
				leaf = results.leaves[0];
				results.leaves[0] = results.leaves[1];
				refused (() => CfgRuntimeLifetimes.verify (program));
				results.leaves[0] = (CfgCallResultValue) leaf;
				block.instructions.insert (call_at, call);
				refused (() => CfgRuntimeLifetimes.verify (program));
				block.instructions.remove_index (call_at);
				var invalid = new CfgStructBoundaryAcquire (acquired.span, acquired.destination, acquired.shape, acquired.leaves);
				block.instructions[position] = invalid;
				refused (() => CfgRuntimeLifetimes.verify (program));
				block.instructions[position] = acquired;
				CfgRuntimeLifetimes.verify (program);
			}
		}
	}
	assert (count == 1);
}

private void ssa_record_producers() {
	try {
		for (int shape = 0; shape < 3; shape++) {
			string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf left;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}" : "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}";
			string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
			string initialized = shape == 1 ? "first={left=move left,marker=17},right=move right" : "left=move left,right=move right,marker=17";
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}" + definition + record + " create(owned ScopedLeaf left,owned ScopedLeaf right){" + record + " result={" + initialized + "};return move result;}" + record + " relay(owned ScopedLeaf left,owned ScopedLeaf right,borrowed Scoped context){" + record + " result=create(move left,move right);return move result;}";
			CfgProgram? original = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API))));
			var weak = WeakRef (original.functions[0]);
			var ssa = SsaBuilder.build (original);
			original = null;
			assert (weak.get () == null);
			var effects = SsaRuntimeLifetimes.analyze (ssa);
			foreach (var function in ssa.functions) {
				if (function.name == "relay") {
					var effect = effects.lookup (function);
					assert (effect.complete);
					var first = effect.equations.requirements (effect.result, shape == 1 ? "f0.f0" : "f0");
					var second = effect.equations.requirements (effect.result, "f1");
					assert (first.length == 1 && first[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && first[0].ordinal == 0 && first[0].path == "");
					assert (second.length == 1 && second[0].kind == RuntimeScopeOriginKind.OWNER_PARAMETER && second[0].ordinal == 1 && second[0].path == "");
				}
			}
			effects = null;
			ssa_record_producer_controls (ssa);
			var native = NativeAbiBuilder.build (ssa);
			var abi = CAbiBuilder.build (ssa, native);
			var artifact = LlvmLowering.lower (ssa, native, abi);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			artifact.verify ();
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void ssa_record_producer_controls(SsaProgram program) throws GLib.Error {
	int count = 0;
	foreach (var function in program.functions) {
		foreach (var block in function.blocks) {
			for (int position = 0; position < block.instructions.length; position++) {
				var acquired = block.instructions[position] as SsaStructBoundaryAcquire;
				if (acquired == null || acquired.results == null) {
					continue;
				}
				count++;
				var consumed = (SsaStructResultConsume) block.instructions[position - 1];
				var results = acquired.results;
				SsaCallInstruction? call = null;
				int call_at = -1;
				for (int i = 0; i < position; i++) {
					var candidate = block.instructions[i] as SsaCallInstruction;
					if (candidate != null && candidate.struct_result == results) {
						call = candidate;
						call_at = i;
					}
				}
				assert (call != null);
				block.instructions.remove_index (position - 1);
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions.insert (position - 1, consumed);
				block.instructions.insert (position - 1, consumed);
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions.remove_index (position - 1);
				block.instructions[position - 1] = new SsaStructResultConsume (consumed.span, results, StructResultUseKind.OBSERVE);
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions[position - 1] = consumed;
				block.instructions.remove_index (position - 1);
				block.instructions.insert (call_at, consumed);
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions.remove_index (call_at);
				block.instructions.insert (position - 1, consumed);
				var leaf = acquired.leaves[0];
				acquired.leaves[0] = acquired.leaves[1];
				refused (() => SsaRuntimeLifetimes.verify (program));
				acquired.leaves[0] = leaf;
				var omitted = acquired.leaves[acquired.leaves.length - 1];
				acquired.leaves.remove_index (acquired.leaves.length - 1);
				refused (() => SsaRuntimeLifetimes.verify (program));
				acquired.leaves.add (omitted);
				call.struct_result = null;
				refused (() => SsaRuntimeLifetimes.verify (program));
				call.struct_result = results;
				var original = results.leaves[0];
				results.leaves[0] = results.leaves[1];
				refused (() => SsaRuntimeLifetimes.verify (program));
				results.leaves[0] = original;
				block.instructions.insert (call_at, call);
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions.remove_index (call_at);
				var owner = acquired.owners[0];
				var extent = owner.text_extent;
				owner.text_extent = null;
				refused (() => SsaRuntimeLifetimes.verify (program));
				owner.text_extent = extent;
				var actual = (SsaHeapOwnerEvent) block.instructions[position + 1];
				block.instructions[position + 1] = new SsaHeapOwnerEvent (actual.span, actual.owner, SsaHeapOwnerAction.READ, actual.value, actual.effect);
				refused (() => SsaRuntimeLifetimes.verify (program));
				block.instructions[position + 1] = actual;
				SsaRuntimeLifetimes.verify (program);
			}
		}
	}
	assert (count == 1);
}

private void llvm_output_scope_inventory() {
	try {
		foreach (bool scoped in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + (scoped ? "[Allocator(kind=\"context\",context=\"scoped-affine\")]" : "") + "class Leaf{init(){}}class Envelope{owned Leaf child;init(owned Leaf child){this.child=move child;}}struct Packet{owned Leaf left;owned Leaf right;int marker;}Packet create(owned Leaf left,owned Leaf right){Packet result={left=move left,right=move right,marker=17};return move result;}";
			var ssa = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			var program = NativeAbiBuilder.build (ssa);
			NativeFunction? target = null;
			foreach (var function in program.functions) {
				if (function.name == "create") {
					target = function;
				}
			}
			assert (target != null);
			var leaf = program.classes[0];
			var record = target.signature.struct_result;
			assert (record != null);
			var callable = new NativeFunctionPointerType (NativeScalarType.I32, new GenericArray<NativeAbiType> ());
			// Presence-only output controls. These detached signatures do not grant
			// ownership authority or represent admitted native library producers.
			NativeAbiType[] types = {
				new NativeSharedHandleType (leaf.name, false), new NativeSharedHandleType (leaf.name, true), new NativeClosureHandleType (leaf.name, callable), new NativeOwnerSlotsType (leaf.ordinal, leaf.name, leaf.destructor_ordinal), new NativeOwnerSlotsType (-1, record.struct_name, -1, NativeScalarType.PTR, NativeScalarType.I32, NativeScalarType.I32, null, record)
			};
			foreach (var type in types) {
				var signature = new NativeSignature (NativeAbiVersion.OWNER_SLOTS_V15, new GenericArray<NativeParameter> (), new NativeResult.typed (type));
				assert (LlvmScopedOwnedInputs.required (signature, program) == scoped);
				var buffer = new NativeSignature (NativeAbiVersion.OWNER_SLOTS_V15, new GenericArray<NativeParameter> (), null);
				buffer.buffer_result = new NativeBufferValuePlan (type);
				assert (LlvmScopedOwnedInputs.required (buffer, program) == scoped);
			}
			var records = new NativeSignature (NativeAbiVersion.OWNER_SLOTS_V15, new GenericArray<NativeParameter> (), null);
			records.struct_result = record;
			assert (LlvmScopedOwnedInputs.required (records, program) == scoped);
			var element = new NativeRecordElement (record.struct_ordinal, record.struct_name, new GenericArray<NativeRecordField> (), true, true, false);
			var buffered = new NativeSignature (NativeAbiVersion.OWNER_SLOTS_V15, new GenericArray<NativeParameter> (), null);
			buffered.buffer_result = new NativeBufferValuePlan.for_record (element);
			assert (LlvmScopedOwnedInputs.required (buffered, program) == scoped);
			var heap = new NativeSignature (NativeAbiVersion.OWNER_SLOTS_V15, new GenericArray<NativeParameter> (), new NativeResult (NativeScalarType.PTR));
			heap.heap_result = new NativeObjectOriginPlan (leaf.ordinal, leaf.name, true);
			assert (LlvmScopedOwnedInputs.required (heap, program) == scoped);
			var placed = new NativeSignature (NativeAbiVersion.OWNER_SLOTS_V15, new GenericArray<NativeParameter> (), null, null, new NativeOwnedObjectResultPlan.typed (new NativeObjectOriginPlan (leaf.ordinal, leaf.name, false)));
			assert (!LlvmScopedOwnedInputs.required (placed, program));
			NativeClassPlan? envelope = null;
			foreach (var owner in program.classes) {
				if (owner.name == "Envelope") {
					envelope = owner;
				}
			}
			assert (envelope != null);
			var nested = new NativeSignature (NativeAbiVersion.OWNER_SLOTS_V15, new GenericArray<NativeParameter> (), null, null, new NativeOwnedObjectResultPlan.typed (new NativeObjectOriginPlan (envelope.ordinal, envelope.name, false)));
			assert (LlvmScopedOwnedInputs.required (nested, program) == scoped);
			foreach (bool name in new bool[] { false, true }) {
				var bad = new NativeSignature (NativeAbiVersion.OWNER_SLOTS_V15, new GenericArray<NativeParameter> (), new NativeResult.typed (name ? (NativeAbiType) new NativeSharedHandleType ("MissingOutputClass", false) : new NativeOwnerSlotsType (program.classes.length, "MissingOutputClass", -1)));
				refusal_text (() => { LlvmScopedOwnedInputs.required (bad, program);
				}, name ? "retained Class declaration" : "native Class origin");
				heap.heap_result = new NativeObjectOriginPlan (name ? leaf.ordinal : program.classes.length, "MissingOutputClass", true);
				refusal_text (() => { LlvmScopedOwnedInputs.required (heap, program);
				}, "result lost its exact native Class origin");
			}
		}
		llvm_null_output_contracts ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_null_output_contracts() throws GLib.Error {
	string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}class Plain{init(){}}owned ScopedLeaf empty(){return null;}owned ScopedLeaf conditional(int mode){if(mode==0){return null;}return null;}owned Plain live(){var value=new Plain();return move value;}class Host{private owned ScopedLeaf left;private owned ScopedLeaf right;init(owned ScopedLeaf left,owned ScopedLeaf right){this.left=move left;this.right=move right;}void clear(int mode){this.left=empty();this.right=conditional(mode);}}";
	SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
	int empty = -1, conditional = -1;
	foreach (var function in source.functions) {
		if (function.name == "empty") {
			empty = function.ordinal;
		}
		if (function.name == "conditional") {
			conditional = function.ordinal;
		}
	}
	assert (empty >= 0 && conditional >= 0);
	var weak = WeakRef (source.functions[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (source);
	CAbiProgram? foreign = CAbiBuilder.build (source, native);
	var artifact = LlvmLowering.lower (source, native, foreign);
	new LlvmTargetMachineArtifact (0).configure (artifact);
	source = null;
	native = null;
	foreign = null;
	assert (weak.get () == null);
	LlvmLifetimeTests.null_outputs (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (empty)), CApi.named_function (artifact.module, "astra.fn.%d".printf (conditional)));
}

private void llvm_single_record_results() {
	try {
		for (int shape = 0; shape < 4; shape++) {
			string definition = (shape == 0 || shape == 3) ? "struct Packet{owned ScopedLeaf item;}" : shape == 1 ? "struct Inner{owned ScopedLeaf item;}struct Packet{Inner child;}" : "struct Packet<T>where T:Ownable{owned T item;}";
			string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
			string initialized = shape == 1 ? "child={item=move input}" : "item=move input";
			string body = shape == 3 ? record + " create(int marker," + record + " input){return move input;}" : record + " create(int marker,owned ScopedLeaf input){" + record + " result={" + initialized + "};return move result;}";
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}" + definition + body;
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int create = -1;
			foreach (var function in source.functions) {
				if (function.name == "create") {
					create = function.ordinal;
				}
			}
			assert (create >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.forwarded_owner (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (create)));
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_multi_record_results() {
	llvm_multi_record_results_profile (false);
}

private void llvm_class_loan_origins() {
	try {
		string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(int number){this.number=number;}int read(){return this.number;}}int inspect(borrowed ScopedLeaf view){return view.read();}int relay(borrowed ScopedLeaf view){return inspect(view);}int consume(owned ScopedLeaf input){return inspect(input);}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "consume")))));
		int inspect = -1;
		int consume = -1;
		foreach (var function in source.functions) {
			if (function.name == "inspect") {
				inspect = function.ordinal;
			}
			if (function.name == "consume") {
				consume = function.ordinal;
			}
		}
		assert (inspect >= 0 && consume >= 0);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.class_loan_origins (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (inspect)));
		LlvmLifetimeTests.class_loan_origins (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (consume)), true);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_receiver_origins() {
	try {
		string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(int number){this.number=number;}int read(){return this.number;}}int inspect(borrowed ScopedLeaf view){return view.read();}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.receiver_origins (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_empty_carriers() {
	try {
		string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}class Plain{private int value;init(int value){this.value=value;}int read(){return this.value;}}[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{private owned ScopedLeaf scoped;private owned Plain plain;init(owned ScopedLeaf scoped,owned Plain plain){this.scoped=move scoped;this.plain=move plain;}int read(){return this.plain.read();}}int exercise(borrowed Context parent){var plain=new Plain(7);var host=try_new(parent)Host(null,move plain);if(host==null){return plain.read();}return host.read();}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API + API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		foreach (var function in native.functions) {
			if (function.name == "read" && function.declaring_type_ordinal == 2) {
				assert (function.effect_facts != null && function.effect_facts.flags == 0);
				var lifetime = RuntimeLifetimeSummary.decode (function.runtime_lifetimes);
				assert (lifetime.complete && lifetime.equations.requirements (lifetime.result).length == 0);
			}
		}
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		assert (artifact.scoped_borrow (CApi.named_function (artifact.module, "astra.class.method.2.0")));
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_fresh_scoped_construction() {
	try {
		string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(int number){this.number=number;}int read(){return this.number;}}int local(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=new(context)ScopedLeaf(17);return leaf.read();}int borrowed_context(borrowed Scoped context){var leaf=try_new(context)ScopedLeaf(19);if(leaf==null){return 0;}return leaf.read();}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var targets = new GenericArray<int> ();
		foreach (var function in source.functions) {
			if (function.name == "local" || function.name == "borrowed_context") {
				targets.add (function.ordinal);
			}
		}
		assert (targets.length == 2);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		for (int t = 0; t < targets.length; t++) {
			LlvmLifetimeTests.fresh_construction (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (targets[t])));
		}
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_fresh_scoped_results() {
	try {
		foreach (bool checked in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(int number){this.number=number;}int read(){return this.number;}}owned ScopedLeaf produce(borrowed Scoped context,borrowed Scoped alternate,int number){var leaf=" + (checked ? "try_new" : "new") + "(context)ScopedLeaf(number);return move leaf;}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int producer = -1;
			foreach (var function in source.functions) {
				if (function.name == "produce") {
					producer = function.ordinal;
				}
			}
			assert (producer >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.fresh_results (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (producer)));
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_owning_receiver() {
	try {
		foreach (bool checked in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "class Plain{private int number;init(int number){this.number=number;}int read(){return this.number;}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private int marker;private owned Plain child;init(int marker,owned Plain child){this.marker=marker;this.child=move child;}int read(){return this.marker+this.child.read();}}int exercise(borrowed Scoped context){var child=new Plain(17);var host=" + (checked ? "try_new" : "new") + "(context)Host(7,move child);" + (checked ? "if(host==null){return child.read();}" : "") + "return host.read();}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int exercise = -1;
			foreach (var function in source.functions) {
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
			}
			assert (exercise >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.fresh_construction (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)));
			LlvmLifetimeTests.owning_receiver (artifact, CApi.named_function (artifact.module, "astra.ctor.1"), CApi.named_function (artifact.module, "astra.dtor.1"));
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_fresh_graph_results() {
	try {
		foreach (bool record in new bool[] { false, true }) {
			string fields = record ? "private Pair pair;init(Pair pair){this.pair=move pair;}int read(){return this.pair.marker;}" : "private owned Leaf left;private owned Leaf right;init(owned Leaf left,owned Leaf right){this.left=move left;this.right=move right;}int read(){return this.left.read()+this.right.read();}";
			string construction = record ? "Pair pair={left=move left,right=move right,marker=37};var host=new(parent)Host(move pair);" : "var host=new(parent)Host(move left,move right);";
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{private int number;init(int number){this.number=number;}int read(){return this.number;}}struct Pair{owned Leaf left;owned Leaf right;int marker;}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{" + fields + "}owned Host produce(borrowed Scoped parent,borrowed Scoped children){var left=new(children)Leaf(17);var right=new(children)Leaf(23);" + construction + "return move host;}int exercise(){owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];var parent=scoped_allocator<Scoped>(a,1,7);var children=scoped_allocator<Scoped>(b,2,1);var host=produce(parent,children);return host.read();}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int producer = -1, caller = -1;
			foreach (var function in source.functions) {
				if (function.name == "produce") {
					producer = function.ordinal;
				}
				if (function.name == "exercise") {
					caller = function.ordinal;
				}
			}
			assert (producer >= 0 && caller >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.fresh_graph_results (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (producer)), CApi.named_function (artifact.module, "astra.fn.%d".printf (caller)), CApi.named_function (artifact.module, "astra.dtor.1"));
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_fresh_owning_results() {
	try {
		foreach (bool checked in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "class Plain{private int number;init(int number){this.number=number;}int read(){return this.number;}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private int marker;private owned Plain child;init(int marker,owned Plain child){this.marker=marker;this.child=move child;}int read(){return this.marker+this.child.read();}}owned Host produce(borrowed Scoped context,borrowed Scoped alternate,int number){var child=new Plain(number);var host=" + (checked ? "try_new" : "new") + "(context)Host(7,move child);return move host;}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int producer = -1;
			foreach (var function in source.functions) {
				if (function.name == "produce") {
					producer = function.ordinal;
				}
			}
			assert (producer >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.fresh_results (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (producer)));
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_child_graphs() {
	try {
		foreach (bool checked in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{private int number;init(int number){this.number=number;}int read(){return this.number;}}int inspect(borrowed Leaf input){return input.read();}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private int marker;private owned Leaf left;private owned Leaf right;init(int marker,owned Leaf left,owned Leaf right){this.marker=marker;this.left=move left;this.right=move right;}int read(){return inspect(this.left)+this.right.read()+this.marker;}}int exercise(){owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];var first=scoped_allocator<Scoped>(a,1,7);var second=scoped_allocator<Scoped>(b,2,1);var left=new(first)Leaf(17);var right=new(first)Leaf(23);var host=" + (checked ? "try_new" : "new") + "(second)Host(7,move left,move right);" + (checked ? "if(host==null){return left.read()+right.read();}" : "") + "return host.read();}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int exercise = -1;
			foreach (var function in source.functions) {
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
			}
			assert (exercise >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.child_graph (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)), checked);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_graph_forwarding() {
	try {
		foreach (bool checked in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{private int number;init(int number){this.number=number;}int read(){return this.number;}}int inspect(borrowed Leaf input){return input.read();}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private int marker;private owned Leaf left;private owned Leaf right;init(int marker,owned Leaf left,owned Leaf right){this.marker=marker;this.left=move left;this.right=move right;}int read(){return inspect(this.left)+this.right.read()+this.marker;}}owned Host relay(owned Host input){return move input;}int exercise(){owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];var first=scoped_allocator<Scoped>(a,1,7);var second=scoped_allocator<Scoped>(b,2,1);var left=new(first)Leaf(17);var right=new(first)Leaf(23);var original=" + (checked ? "try_new" : "new") + "(second)Host(7,move left,move right);" + (checked ? "if(original==null){return left.read()+right.read();}" : "") + "var host=relay(move original);return host.read();}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int exercise = -1;
			int relay = -1;
			foreach (var function in source.functions) {
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
				if (function.name == "relay") {
					relay = function.ordinal;
				}
			}
			assert (exercise >= 0 && relay >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			var caller = CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise));
			LlvmLifetimeTests.graph_forwarding (artifact, caller, CApi.named_function (artifact.module, "astra.fn.%d".printf (relay)));
			LlvmLifetimeTests.child_graph (artifact, caller, checked);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_nullable_owned_arguments() {
	try {
		string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{private int number;init(int number){this.number=number;}}int consume(owned Leaf input){return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "consume")))));
		int consume = -1;
		foreach (var function in source.functions) {
			if (function.name == "consume") {
				consume = function.ordinal;
			}
		}
		assert (consume >= 0);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.nullable_owned_arguments (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (consume)));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_child_constructor_rollback() {
	try {
		for (int profile = 0; profile < 3; profile++) {
			bool checked = profile == 2;
			string text = SCOPED_PROGRAM + "[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{private int number;init(int number){this.number=number;}int read(){return this.number;}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private int marker;private owned Leaf left;private owned Leaf right;init(owned Leaf left,owned Leaf right,int mode)throws Fault{this.marker=7;if(mode==1){throw new Fault();}this.left=move left;if(mode==2){throw new Fault();}this.right=move right;if(mode==3){throw new Fault();}}int read(){return this.left.read()+this.right.read()+this.marker;}}int exercise(){owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];var first=scoped_allocator<Scoped>(a,1,7);var second=scoped_allocator<Scoped>(b,2,1);int remaining=3;while(remaining>0){var left=new(first)Leaf(17);var right=new(first)Leaf(23);try{var host=" + (checked ? "try_new" : "new") + "(second)Host(move left,move right,remaining);" + (checked ? "if(host==null){left.read();right.read();}else{host.read();}" : "host.read();") + "}catch(Fault error){}remaining=remaining-1;}return 0;}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int exercise = -1;
			foreach (var function in source.functions) {
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
			}
			assert (exercise >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			var constructor = CApi.named_function (artifact.module, "astra.ctor.2");
			var caller = CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise));
			if (profile == 0) {
				LlvmLifetimeTests.constructor_stack (artifact, caller, constructor, 2);
			} else {
				LlvmLifetimeTests.constructor_rollback (artifact, caller, constructor, true);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_deep_constructor_rollback() {
	try {
		for (int profile = 0; profile < 3; profile++) {
			bool checked = profile == 2;
			string text = SCOPED_PROGRAM + "[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{private int number;init(int number){this.number=number;}int read(){return this.number;}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Node{private owned Leaf child;init(owned Leaf child){this.child=move child;}int read(){return this.child.read();}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private int marker;private owned Node left;private owned Node right;init(owned Node left,owned Node right,int mode)throws Fault{this.marker=7;if(mode==1){throw new Fault();}this.left=move left;if(mode==2){throw new Fault();}this.right=move right;if(mode==3){throw new Fault();}}int read(){return this.left.read()+this.right.read()+this.marker;}}void touch_node(borrowed Node input){input.read();}int exercise(){owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];var first=scoped_allocator<Scoped>(a,1,7);var second=scoped_allocator<Scoped>(b,2,1);int remaining=3;while(remaining>0){var left_leaf=new(first)Leaf(17);var right_leaf=new(first)Leaf(23);var left=new(first)Node(move left_leaf);var right=new(first)Node(move right_leaf);try{var host=" + (checked ? "try_new" : "new") + "(second)Host(move left,move right,remaining);" + (checked ? "if(host==null){left.read();right.read();}else{host.read();}" : "host.read();") + "}catch(Fault error){}remaining=remaining-1;}return 0;}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int exercise = -1;
			int touch = -1;
			foreach (var function in source.functions) {
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
				if (function.name == "touch_node") {
					touch = function.ordinal;
				}
			}
			assert (exercise >= 0 && touch >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			var constructor = CApi.named_function (artifact.module, "astra.ctor.3");
			var caller = CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise));
			if (profile == 0) {
				LlvmLifetimeTests.constructor_stack (artifact, caller, constructor, 2);
				LlvmLifetimeTests.constructor_graph_cleanup (artifact, constructor, CApi.named_function (artifact.module, "astra.dtor.2"), CApi.named_function (artifact.module, "astra.fn.%d".printf (touch)));
			} else {
				LlvmLifetimeTests.constructor_rollback (artifact, caller, constructor, true);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_record_constructor_rollback() {
	try {
		foreach (bool checked in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "class Leaf{private int marker;init(int marker){this.marker=marker;}}struct Packet{owned Leaf left;owned Leaf right;int marker;}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private Packet packet;init(Packet packet,int mode)throws Fault{if(mode==1){throw new Fault();}this.packet=move packet;if(mode==2){throw new Fault();}}int read(){return this.packet.marker;}}[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}int exercise(){owned u8[] backing=new u8[8197];var context=scoped_allocator<Scoped>(backing,1,7);var left=new Leaf(17);var right=new Leaf(23);Packet input={left=move left,right=move right,marker=37};try{var host=" + (checked ? "try_new" : "new") + "(context)Host(move input,0);" + (checked ? "if(host==null){return input.marker;}" : "") + "return host.read();}catch(Fault error){return 1;}}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int exercise = -1;
			foreach (var function in source.functions) {
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
			}
			assert (exercise >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			var host = native.classes[1];
			var field = host.fields[0];
			var plan = field.record_value;
			assert (field.owns_record && plan != null && plan.ownership.length == 2);
			foreach (bool missing in new bool[] { false, true }) {
				var replacement = missing ? null : new NativeStructValuePlan (plan.struct_ordinal, plan.struct_name, plan.leaves, plan.result_carrier, plan.mode, plan.ownership);
				host.fields[0] = new NativeClassField (field.span, field.name, field.type_name, field.ordinal, field.text_snapshot, field.storage_type, field.record_ordinal, field.is_private, field.owned_class_ordinal, field.owns_buffer, field.resource_owner, field.owns_record, field.buffer_value, replacement);
				refusal_text (() => NativeAbiVerifier.verify (native), "original element declaration");
				host.fields[0] = field;
				NativeAbiVerifier.verify (native);
			}
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.record_lifecycle (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)), CApi.named_function (artifact.module, "astra.ctor.1"), CApi.named_function (artifact.module, "astra.dtor.1"));
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void check_scoped_record_child_paths(bool checked) {
	try {
		string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{private int marker;init(int marker){this.marker=marker;}}struct Packet{owned Leaf left;owned Leaf right;int marker;}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private Packet packet;init(Packet packet,int mode)throws Fault{if(mode==1){throw new Fault();}this.packet=move packet;if(mode==2){throw new Fault();}}int read(){return this.packet.marker;}}[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}int consume(Packet input){return input.marker;}owned Host relay(owned Host input){return move input;}int exercise(){owned u8[] backing=new u8[8197];owned u8[] children=new u8[12289];var context=scoped_allocator<Scoped>(backing,1,7);var child_context=scoped_allocator<Scoped>(children,2,1);var left=new(child_context)Leaf(17);var right=new(child_context)Leaf(23);Packet input={left=move left,right=move right,marker=37};try{var initial=" + (checked ? "try_new" : "new") + "(context)Host(move input,0);" + (checked ? "if(initial==null){return consume(move input);}" : "") + "var host=relay(move initial);return host.read();}catch(Fault error){return 1;}}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		int exercise = -1;
		foreach (var function in source.functions) {
			if (function.name == "exercise") {
				exercise = function.ordinal;
			}
		}
		assert (exercise >= 0);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.record_child_paths (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)), CApi.named_function (artifact.module, "astra.ctor.1"), CApi.named_function (artifact.module, "astra.dtor.1"));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_record_child_paths() {
	check_scoped_record_child_paths (false);
}

private void llvm_checked_record_child_paths() {
	check_scoped_record_child_paths (true);
}

private void llvm_scoped_buffer_graph_forwarding() {
	try {
		foreach (bool heap in new bool[] { false, true }) {
			foreach (bool checked in new bool[] { false, true }) {
				if (heap && checked) {
					continue;
				}
				string policy = heap ? "" : "[Allocator(kind=\"context\",context=\"scoped-affine\")]";
				string failure = heap ? "" : " throws Fault";
				string exceptional = heap ? "" : "if(len(this.bytes)==0){throw new Fault();}";
				string fault = heap ? "" : "[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}";
				string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{private int number;init(int number){this.number=number;}int read(){return this.number;}}" + policy + "class Host{private owned Leaf child;private owned u8[] bytes;private owned i32[] values;init(owned Leaf child,owned u8[] bytes,owned i32[] values)" + failure + "{this.child=move child;this.bytes=move bytes;this.values=move values;" + exceptional + "}int read(){return this.child.read()+len(this.bytes)+len(this.values);}}" + fault + "owned Host relay(owned Host input){return move input;}int exercise(){owned u8[] backing=new u8[8197];var context=scoped_allocator<Scoped>(backing,1,7);var child=new(context)Leaf(17);owned u8[] bytes=new u8[37];owned i32[] values=new i32[53];" + (heap ? "" : "try{") + "var initial=" + (checked ? "try_new" : "new") + (heap ? " Host" : "(context)Host") + "(move child,move bytes,move values);" + (checked ? "if(initial==null){return child.read()+len(bytes)+len(values);}" : "") + "var host=relay(move initial);return host.read();" + (heap ? "" : "}catch(Fault error){return 1;}") + "}";
				SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
				int exercise = -1, relay = -1;
				foreach (var function in source.functions) {
					if (function.name == "exercise") {
						exercise = function.ordinal;
					}
					if (function.name == "relay") {
						relay = function.ordinal;
					}
				}
				assert (exercise >= 0 && relay >= 0);
				var weak = WeakRef (source.functions[0]);
				NativeAbiProgram? native = NativeAbiBuilder.build (source);
				CAbiProgram? foreign = CAbiBuilder.build (source, native);
				var artifact = LlvmLowering.lower (source, native, foreign);
				new LlvmTargetMachineArtifact (0).configure (artifact);
				source = null;
				native = null;
				foreign = null;
				assert (weak.get () == null);
				LlvmLifetimeTests.graph_forwarding (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)), CApi.named_function (artifact.module, "astra.fn.%d".printf (relay)));
				LlvmLifetimeTests.buffer_storage (artifact, CApi.named_function (artifact.module, "astra.ctor.1"), CApi.named_function (artifact.module, "astra.dtor.1"), !heap);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_buffer_constructor_rollback() {
	try {
		foreach (bool checked in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private int marker;private owned u8[] left;private owned i32[] right;init(int marker,owned u8[] left,owned i32[] right,int mode)throws Fault{this.marker=marker;if(mode==1){throw new Fault();}this.left=move left;if(mode==2){throw new Fault();}this.right=move right;if(mode==3){throw new Fault();}}int read(){return len(this.left)+len(this.right);}}int exercise(borrowed Scoped context,int mode){owned u8[] left=new u8[37];owned i32[] right=new i32[53];try{var host=" + (checked ? "try_new" : "new") + "(context)Host(7,move left,move right,mode);" + (checked ? "if(host==null){return len(left)+len(right);}if(len(left)!=0||len(right)!=0){return 2;}" : "") + "return host.read();}catch(Fault error){return 0;}}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int exercise = -1;
			foreach (var function in source.functions) {
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
			}
			assert (exercise >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			var host = native.classes[1];
			var field = host.fields[1];
			assert (field.owns_buffer && field.buffer_value != null);
			foreach (bool missing in new bool[] { false, true }) {
				var replacement = missing ? null : new NativeBufferValuePlan (new NativeScalarAbiType (NativeScalarType.I32));
				host.fields[1] = new NativeClassField (field.span, field.name, field.type_name, field.ordinal, field.text_snapshot, field.storage_type, field.record_ordinal, field.is_private, field.owned_class_ordinal, field.owns_buffer, field.resource_owner, field.owns_record, replacement);
				refusal_text (() => NativeAbiVerifier.verify (native), "original element declaration");
				host.fields[1] = field;
				NativeAbiVerifier.verify (native);
			}
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.buffer_constructor (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)), CApi.named_function (artifact.module, "astra.ctor.1"), CApi.named_function (artifact.module, "astra.dtor.1"));
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_heap_constructor_rollback() {
	try {
		for (int profile = 0; profile < 3; profile++) {
			bool checked = profile == 2;
			string text = SCOPED_PROGRAM + "[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{private int number;init(int number){this.number=number;}int read(){return this.number;}}class Node{private owned Leaf child;init(owned Leaf child){this.child=move child;}int read(){return this.child.read();}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private int marker;private owned Node left;private owned Node right;init(owned Node left,owned Node right,int mode)throws Fault{this.marker=7;if(mode==1){throw new Fault();}this.left=move left;if(mode==2){throw new Fault();}this.right=move right;if(mode==3){throw new Fault();}}int read(){return this.left.read()+this.right.read()+this.marker;}}void touch_node(borrowed Node input){input.read();}int exercise(){owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];var first=scoped_allocator<Scoped>(a,1,7);var second=scoped_allocator<Scoped>(b,2,1);int remaining=3;while(remaining>0){var left_leaf=new(first)Leaf(17);var right_leaf=new(first)Leaf(23);var left=new Node(move left_leaf);var right=new Node(move right_leaf);try{var host=" + (checked ? "try_new" : "new") + "(second)Host(move left,move right,remaining);" + (checked ? "if(host==null){left.read();right.read();}else{host.read();}" : "host.read();") + "}catch(Fault error){}remaining=remaining-1;}return 0;}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int exercise = -1;
			int touch = -1;
			foreach (var function in source.functions) {
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
				if (function.name == "touch_node") {
					touch = function.ordinal;
				}
			}
			assert (exercise >= 0 && touch >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			var constructor = CApi.named_function (artifact.module, "astra.ctor.3");
			var caller = CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise));
			if (profile == 0) {
				LlvmLifetimeTests.constructor_stack (artifact, caller, constructor, 2, true);
				LlvmLifetimeTests.constructor_graph_cleanup (artifact, constructor, CApi.named_function (artifact.module, "astra.dtor.2"), CApi.named_function (artifact.module, "astra.fn.%d".printf (touch)), true);
			} else {
				LlvmLifetimeTests.constructor_rollback (artifact, caller, constructor, true);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_owned_constructor_rollback() {
	try {
		foreach (bool checked in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}class Leaf{private int number;init(int number){this.number=number;}int read(){return this.number;}}class Node{private owned Leaf child;init(owned Leaf child){this.child=move child;}int read(){return this.child.read();}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private int marker;private owned Leaf left;private owned Node right;init(owned Leaf left,owned Node right,int mode)throws Fault{this.marker=7;if(mode==1){throw new Fault();}this.left=move left;if(mode==2){throw new Fault();}this.right=move right;if(mode==3){throw new Fault();}}int read(){return this.left.read()+this.right.read()+this.marker;}}int exercise(){owned u8[] backing=new u8[8197];var context=scoped_allocator<Scoped>(backing,2,1);int remaining=3;while(remaining>0){var left=new Leaf(17);var leaf=new Leaf(23);var right=new Node(move leaf);try{var host=" + (checked ? "try_new" : "new") + "(context)Host(move left,move right,remaining);" + (checked ? "if(host==null){left.read();right.read();}else{host.read();}" : "host.read();") + "}catch(Fault error){}remaining=remaining-1;}return 0;}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int exercise = -1;
			foreach (var function in source.functions) {
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
			}
			assert (exercise >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			bool checked_unwind = false;
			foreach (var function in native.functions) {
				if (function.kind != NativeCallableKind.CONSTRUCTOR || function.declaring_type_ordinal != 3) {
					continue;
				}
				var plan = function.constructor_unwind;
				assert (plan != null && plan.field_count == 2);
				function.constructor_unwind = null;
				refused (() => NativeAbiVerifier.verify (native));
				function.constructor_unwind = plan;
				NativeAbiVerifier.verify (native);
				checked_unwind = true;
			}
			assert (checked_unwind);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			var constructor = CApi.named_function (artifact.module, "astra.ctor.3");
			LlvmLifetimeTests.constructor_rollback (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)), constructor);
			LlvmLifetimeTests.constructor_prefix_unwind (artifact, constructor);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_constructor_rollback() {
	try {
		foreach (bool checked in new bool[] { false, true }) {
			string text = SCOPED_PROGRAM + "[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Item{private int number;init(int number)throws Fault{this.number=number;if(number<0){throw new Fault();}}int read(){return this.number;}}int exercise(){owned u8[] backing=new u8[8197];var context=scoped_allocator<Scoped>(backing,2,1);try{var item=" + (checked ? "try_new" : "new") + "(context)Item(-1);if(item!=null){return item.read();}}catch(Fault error){}return 0;}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			int exercise = -1;
			foreach (var function in source.functions) {
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
			}
			assert (exercise >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.constructor_rollback (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)), CApi.named_function (artifact.module, "astra.ctor.1"));
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_graph_consumption() {
	try {
		for (int profile = 0; profile < 4; profile++) {
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{private int number;init(int number){this.number=number;}int read(){return this.number;}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private int marker;private owned Leaf left;private owned Leaf right;init(int marker,owned Leaf left,owned Leaf right){this.marker=marker;this.left=move left;this.right=move right;}int read(){return this.left.read()+this.right.read()+this.marker;}}void touch(borrowed Host input){}int consume(owned Host input){if(input==null){return 0;}return input.read();}";
			if (profile != 0) {
				text += "int exercise(){owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];var first=scoped_allocator<Scoped>(a,1,7);var second=scoped_allocator<Scoped>(b,2,1);var left=new(first)Leaf(17);var right=new(first)Leaf(23);var host=" + (profile >= 2 ? "try_new" : "new") + "(second)Host(7,move left,move right);" + (profile == 2 ? "if(host==null){return left.read()+right.read();}" : "") + "return consume(move host);}";
			}
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API, "consume")))));
			int consume = -1;
			int touch = -1;
			int exercise = -1;
			foreach (var function in source.functions) {
				if (function.name == "consume") {
					consume = function.ordinal;
				}
				if (function.name == "touch") {
					touch = function.ordinal;
				}
				if (function.name == "exercise") {
					exercise = function.ordinal;
				}
			}
			assert (consume >= 0 && touch >= 0);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			var target = CApi.named_function (artifact.module, "astra.fn.%d".printf (consume));
			if (profile == 0) {
				LlvmLifetimeTests.graph_consumer (artifact, target, CApi.named_function (artifact.module, "astra.fn.%d".printf (touch)));
			} else {
				assert (exercise >= 0);
				LlvmLifetimeTests.graph_consumer_caller (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (exercise)), target);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_record_result_loans() {
	try {
		for (int shape = 0; shape < 3; shape++) {
			foreach (bool checked in new bool[] { false, true }) {
				foreach (bool companion in new bool[] { false, true }) {
					string definition = shape == 0 ? "struct Packet{owned ScopedLeaf left;owned ScopedLeaf right;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf left;int marker;}struct Packet{Inner first;owned ScopedLeaf right;}" : "struct Packet<T>where T:Ownable{owned T left;owned T right;int marker;}";
					string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
					string initialized = shape == 1 ? "first={left=move left,marker=marker},right=move right" : "left=move left,right=move right,marker=marker";
					string parameters = (checked ? "int mode," : "") + "owned ScopedLeaf left,owned ScopedLeaf right,borrowed ScopedLeaf view" + (companion ? ",borrowed Scoped context" : "");
					string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(int number){this.number=number;}int read(){return this.number;}}[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}" + definition + record + " create(" + parameters + ")" + (checked ? "throws Fault" : "") + "{int marker=view.read();" + (checked ? "if(mode!=0){throw new Fault();}" : "") + record + " result={" + initialized + "};return move result;}";
					SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
					int create = -1;
					foreach (var function in source.functions) {
						if (function.name == "create") {
							create = function.ordinal;
						}
					}
					assert (create >= 0);
					var weak = WeakRef (source.functions[0]);
					NativeAbiProgram? native = NativeAbiBuilder.build (source);
					CAbiProgram? foreign = CAbiBuilder.build (source, native);
					var artifact = LlvmLowering.lower (source, native, foreign);
					new LlvmTargetMachineArtifact (0).configure (artifact);
					source = null;
					native = null;
					foreign = null;
					assert (weak.get () == null);
					LlvmLifetimeTests.record_result_loans (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (create)), checked, companion);
				}
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_borrowed_graph_discovery() {
	try {
		string prefix = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{int number;init(int number){this.number=number;}int read(){return this.number;}}struct Copied{int marker;}";
		foreach (bool by_value in new bool[] { false, true }) {
			string text = prefix + "class Wrapper{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}int read(){return this.child.read();}}Copied inspect(" + (by_value ? "Wrapper input" : "borrowed Wrapper input") + "){Copied result={marker=input.read()};return result;}";
			var source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			var native = NativeAbiBuilder.build (source);
			NativeFunction? inspected = null;
			foreach (var function in native.functions) {
				if (function.name == "inspect") {
					inspected = function;
				}
			}
			assert (inspected != null && LlvmScopedOwnedInputs.required (inspected.signature, native));
			var foreign = CAbiBuilder.build (source, native);
			assert (inspected.signature.parameters.length == 1 && inspected.signature.parameters[0].borrowed_class_ordinal >= 0);
			{
				int ordinal = inspected.ordinal;
				var artifact = LlvmLowering.lower (source, native, foreign);
				new LlvmTargetMachineArtifact (0).configure (artifact);
				assert (artifact.has_scoped_class_loans (CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal))));
				artifact.verify ();
			}
		}
		foreach (bool companion in new bool[] { false, true }) {
			foreach (bool value in new bool[] { false, true }) {
				string parameters = "borrowed ScopedLeaf view" + (value ? ",ScopedLeaf input" : "") + (companion ? ",borrowed Scoped context" : "");
				string text = prefix + "Copied inspect(" + parameters + "){int marker=view.read();Copied result={marker=marker};return result;}";
				SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
				var weak = WeakRef (source.functions[0]);
				NativeAbiProgram? native = NativeAbiBuilder.build (source);
				CAbiProgram? foreign = CAbiBuilder.build (source, native);
				var artifact = LlvmLowering.lower (source, native, foreign);
				new LlvmTargetMachineArtifact (0).configure (artifact);
				source = null;
				native = null;
				foreign = null;
				assert (weak.get () == null);
				artifact.verify ();
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_checked_single_record_results() {
	try {
		for (int shape = 0; shape < 4; shape++) {
			for (int companion = 0; companion < 2; companion++) {
				string definition = (shape == 0 || shape == 3) ? "struct Packet{owned ScopedLeaf item;}" : shape == 1 ? "struct Inner{owned ScopedLeaf item;}struct Packet{Inner child;}" : "struct Packet<T>where T:Ownable{owned T item;}";
				string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
				string initialized = shape == 1 ? "child={item=move input}" : "item=move input";
				string context = companion == 0 ? "" : ",borrowed Scoped context";
				string body = shape == 3 ? record + " create(int mode," + record + " input" + context + ")throws Fault{if(mode!=0){throw new Fault();}return move input;}" : record + " create(int mode,owned ScopedLeaf input" + context + ")throws Fault{if(mode!=0){throw new Fault();}" + record + " result={" + initialized + "};return move result;}";
				string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}" + definition + body;
				SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
				int create = -1;
				foreach (var function in source.functions) {
					if (function.name == "create") {
						create = function.ordinal;
					}
				}
				assert (create >= 0);
				var weak = WeakRef (source.functions[0]);
				NativeAbiProgram? native = NativeAbiBuilder.build (source);
				CAbiProgram? foreign = CAbiBuilder.build (source, native);
				var artifact = LlvmLowering.lower (source, native, foreign);
				new LlvmTargetMachineArtifact (0).configure (artifact);
				source = null;
				native = null;
				foreign = null;
				assert (weak.get () == null);
				var target = CApi.named_function (artifact.module, "astra.fn.%d".printf (create));
				assert (artifact.has_scoped_context_inputs (target) == (companion == 1));
				LlvmLifetimeTests.checked_heap_result (artifact, target, 2);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_multi_record_context_results() {
	llvm_multi_record_results_profile (true);
}

private void record_result_context_dependencies(LlvmModuleArtifact artifact, NativeFunction original, GenericArray<NativeClassPlan> classes) throws GLib.Error {
	var target = CApi.named_function (artifact.module, "astra.fn.%d".printf (original.ordinal));
	assert (LlvmScopedContextInputs.from_native (target, CApi.global_value_type (target), original, classes) != null);
	for (int kind = 0; kind < 3; kind++) {
		var graph = new RuntimeLifetimeEquations ();
		int result = graph.input (kind == 0 ? (int) original.signature.parameters.length - 1 : kind == 1 ? (int) original.signature.parameters.length : 0);
		if (kind == 2) {
			result = graph.project (result, "f0");
		}
		graph.seal ();
		var summary = new RuntimeLifetimeSummary (graph, result, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "");
		var changed = new NativeFunction (original.span, original.name_span, original.name, original.ordinal, original.signature, original.linkage);
		changed.bind_runtime_lifetimes (summary.encode ());
		assert (LlvmScopedContextInputs.from_native (target, CApi.global_value_type (target), changed, classes) == null);
	}
}

private void llvm_multi_record_results_profile(bool with_context) {
	try {
		for (int shape = 0; shape < 4; shape++) {
			string definition = (shape == 0 || shape == 3) ? "struct Packet{owned ScopedLeaf first;owned ScopedLeaf second;int marker;}" : shape == 1 ? "struct Inner{owned ScopedLeaf first;owned ScopedLeaf second;}struct Packet{Inner child;int marker;}" : "struct Packet<T>where T:Ownable{owned T first;owned T second;int marker;}";
			string record = shape == 2 ? "Packet<ScopedLeaf>" : "Packet";
			string initialized = shape == 1 ? "child={first=move a,second=move b},marker=17" : "first=move a,second=move b,marker=17";
			string companion = with_context ? ",borrowed Scoped context" : "";
			string observe = with_context ? "var observed=query(context,7);" : "";
			string context_argument = with_context ? ",context" : "";
			string body = shape == 3 ? record + " create(" + record + " input" + companion + "){" + observe + "return move input;}" : record + " create(owned ScopedLeaf a,owned ScopedLeaf b" + companion + "){" + observe + record + " result={" + initialized + "};return move result;}";
			string relay = shape == 3 ? record + " relay(" + record + " input" + companion + "){var result=create(move input" + context_argument + ");return move result;}" : record + " relay(owned ScopedLeaf a,owned ScopedLeaf b" + companion + "){var result=create(move a,move b" + context_argument + ");return move result;}";
			string text = SCOPED_PROGRAM + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}" + definition + body + relay;
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			var targets = new GenericArray<int> ();
			foreach (var function in source.functions) {
				if (function.name == "create" || function.name == "relay") {
					targets.add (function.ordinal);
				}
			}
			assert (targets.length == 2);
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			if (with_context) {
				foreach (var function in native.functions) {
					if (function.name == "create" || function.name == "relay") {
						record_result_context_dependencies (artifact, function, native.classes);
					}
				}
			}
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			for (int t = 0; t < targets.length; t++) {
				LlvmLifetimeTests.record_results (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (targets[t])), with_context);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_exception_summary_roles() {
	try {
		var graph = new RuntimeLifetimeEquations ();
		graph.seal ();
		var updates = new HashTable<int, int> (direct_hash, direct_equal);
		var stores = new GenericArray<RuntimeLifetimeStore> ();
		string normal = new RuntimeLifetimeSummary (graph, graph.absent (), updates, stores, "").encode ();
		string exceptional = new RuntimeLifetimeSummary (graph, graph.absent (), updates, stores, "", graph.absent ()).encode ();
		var checked = check ();
		NativeAbiProgram? native = NativeAbiBuilder.build (SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked)))));
		NativeFunction? plain = null;
		NativeFunction? throwing = null;
		foreach (var function in native.functions) {
			if (function.signature.exception_plan == null) {
				plain = function;
			} else {
				throwing = function;
			}
		}
		assert (plain != null && throwing != null);
		foreach (bool failure in new bool[] { false, true }) {
			var original = failure ? throwing : plain;
			var positive = new NativeFunction (original.span, original.name_span, original.name, original.ordinal, original.signature, original.linkage);
			positive.bind_runtime_lifetimes (failure ? exceptional : normal);
			assert (positive.runtime_lifetimes_valid ());
			var negative = new NativeFunction (original.span, original.name_span, original.name, original.ordinal, original.signature, original.linkage);
			refusal_text (() => negative.bind_runtime_lifetimes (failure ? normal : exceptional), "exception channel differs");
		}
		CheckedFunction? normal_definition = null;
		CheckedFunction? throwing_definition = null;
		foreach (var definition in checked.all_definitions ()) {
			if (definition.symbol.throws_type == null) {
				normal_definition = definition;
			} else {
				throwing_definition = definition;
			}
		}
		assert (normal_definition != null && throwing_definition != null);
		foreach (bool failure in new bool[] { false, true }) {
			var definition = failure ? throwing_definition : normal_definition;
			var good = new NativeDeclarationIdentity ("exception-lifetimes", "F:probe", "probe", "test", "", false, "", "", failure ? exceptional : normal);
			assert (NativeDeclarationRegistry.signature (good, definition.symbol).runtime_lifetime_summary () != null);
			var bad = new NativeDeclarationIdentity ("exception-lifetimes", "F:bad", "bad", "test", "", false, "", "", failure ? normal : exceptional);
			refusal_text (() => { NativeDeclarationRegistry.signature (bad, definition.symbol).runtime_lifetime_summary ();
			}, "exception channel differs");
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_cold_task_summary_roles() {
	try {
		CheckedProgram? checked = check ("[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}owned Captured empty(){return null;}[ExceptionRoot]class DeferredError{private owned Captured child;init(string message){this.child=empty();}void put(owned Captured input){this.child=move input;}virtual property string message{get{return \"deferred\";}}}enum DeferredStatus{Completed,Cancelled}async runtime DeferredTasks throws DeferredError returns DeferredStatus;async void fail(owned Captured input)throws DeferredError{var error=new DeferredError(\"deferred\");error.put(move input);throw move error;}int main(){return 0;}", SCOPED_API);
		CheckedFunction? definition = null;
		foreach (var function in checked.all_definitions ()) {
			if (function.symbol.name == "fail") {
				definition = function;
			}
		}
		assert (definition != null);
		var source_contract = definition.runtime_lifetimes;
		assert (source_contract.complete && !source_contract.has_exception);
		var valid_identity = new NativeDeclarationIdentity ("cold-task-lifetimes", "F:fail", "fail", "test", "", false, "", "", source_contract.encode ());
		assert (NativeDeclarationRegistry.signature (valid_identity, definition.symbol).runtime_lifetime_summary () != null);
		var graph = new RuntimeLifetimeEquations ();
		graph.seal ();
		string immediate = new RuntimeLifetimeSummary (graph, graph.absent (), new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "", graph.absent ()).encode ();
		var invalid_identity = new NativeDeclarationIdentity ("cold-task-lifetimes", "F:fail", "fail", "test", "", false, "", "", immediate);
		refusal_text (() => { NativeDeclarationRegistry.signature (invalid_identity, definition.symbol).runtime_lifetime_summary ();
		}, "exception channel differs");
		definition = null;
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked))));
		checked = null;
		var weak = WeakRef (source.functions[0]);
		var native = NativeAbiBuilder.build (source);
		source = null;
		assert (weak.get () == null);
		NativeAbiVerifier.verify (native);
		NativeFunction? target = null;
		foreach (var function in native.functions) {
			if (function.name == "fail") {
				target = function;
			}
		}
		assert (target != null && target.async_callable != null && target.signature.exception_plan != null);
		var summary = RuntimeLifetimeSummary.decode (target.runtime_lifetimes);
		assert (summary.complete && !summary.has_exception);
		assert (summary.equations.requirements (summary.result, "f0").length == 0);
		assert (summary.equations.requirements (summary.result, "f1").length == 1);
		assert (summary.equations.requirements (summary.result, "f2").length == 1);
		var original = target.runtime_lifetimes;
		target.runtime_lifetimes = immediate;
		refusal_text (() => NativeAbiVerifier.verify (native), "native summary differs");
		target.runtime_lifetimes = original;
		NativeAbiVerifier.verify (native);
		var candidate = new NativeFunction (target.span, target.name_span, target.name, target.ordinal, target.signature, target.linkage);
		candidate.bind_async_callable (target.async_callable);
		refusal_text (() => candidate.bind_runtime_lifetimes (immediate), "exception channel differs");
		candidate.bind_runtime_lifetimes (original);
		assert (candidate.runtime_lifetimes_valid ());
		var callable = target.async_callable;
		target.async_callable = null;
		refusal_text (() => NativeAbiVerifier.verify (native), "native summary differs", "async");
		target.async_callable = callable;
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_scoped_task_result_shapes() {
	try {
		for (int profile = 0; profile < 4; profile++) {
			string records = profile == 1 ? "struct Inner{owned Captured child;}struct Packet{Inner inner;int marker;}" : profile == 2 ? "struct Packet<T>where T:Ownable{owned T child;int marker;}" : profile == 3 ? "struct Packet{owned Captured first;owned Captured second;int marker;}" : "struct Packet{owned Captured child;int marker;}";
			string packet = profile == 2 ? "Packet<Captured>" : "Packet";
			string text = "[ExceptionRoot]class ResultError{init(string message){}virtual property string message{get{return \"result\";}}}enum Phase{Completed,Cancelled}async runtime Tasks throws ResultError returns Phase;[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}" + records + "async " + packet + " deliver(" + packet + " input){return move input;}int main(){return 0;}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			SsaFunction? function = null;
			foreach (var candidate in source.functions) {
				if (candidate.name == "deliver") {
					function = candidate;
				}
			}
			assert (function != null);
			var weak = WeakRef (function);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			NativeFunction? declared = native.functions[function.ordinal];
			var artifact = new LlvmModuleArtifact ();
			var types = new LlvmTypeMapper (artifact.context);
			LlvmStructRegistry? structs = new LlvmStructRegistry (artifact, types, source, native);
			var type = LlvmAsyncFrameBinding.factory_signature (types, declared.signature);
			var factory = CApi.add_function (artifact.module, "result.shape.factory", type);
			CApi.set_function_call_conv (factory, LlvmLowering.CALL_CONVENTION);
			var inputs = LlvmScopedOwnedInputs.from_native (artifact, factory, type, declared, native, structs, true, true);
			assert (inputs != null);
			assert (LlvmScopedOwnedInputs.from_native (artifact, factory, type, declared, native, structs, true) == null);
			var result = LlvmAsyncRecordResult.from_native (artifact, declared, native, inputs);
			assert (result != null);
			result.verify (inputs);
			assert (result.field_count == (profile == 3 ? 3 : 2) && result.owner_count == (profile == 3 ? 2 : 1) && result.capture (0) == 0 && result.capture (result.field_count - 1) == -1);
			if (profile == 3) {
				assert (result.capture (1) == 1);
			}
			if (profile == 0) {
				for (int mode = 0; mode < 7; mode++) {
					var graph = new RuntimeLifetimeEquations ();
					var future = new HashTable<string, int> (str_hash, str_equal);
					int owner = mode == 0 ? graph.absent () : mode == 1 ? graph.input (1) : mode == 2 ? graph.project (graph.input (0), "f0") : graph.input (0);
					future.insert ("f0", owner);
					future.insert ("f1", mode == 5 ? graph.input (0) : graph.absent ());
					int success = graph.product (new GenericArray<RuntimeScopeOrigin> (), future);
					var retained = new HashTable<string, int> (str_hash, str_equal);
					for (int p = 0; p < declared.signature.parameters.length; p++) {
						retained.insert ("f%d".printf (p), graph.input (p));
					}
					var channels = new HashTable<string, int> (str_hash, str_equal);
					if (mode == 6) {
						retained.remove ("f0");
					}
					channels.insert ("f0", success);
					channels.insert ("f1", mode == 4 ? graph.input (0) : graph.absent ());
					channels.insert ("f2", graph.product (new GenericArray<RuntimeScopeOrigin> (), retained));
					int task = graph.product (new GenericArray<RuntimeScopeOrigin> (), channels);
					graph.seal ();
					var summary = new RuntimeLifetimeSummary (graph, task, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "", mode == 3 ? graph.absent () : -1);
					var changed = new NativeFunction (declared.span, declared.name_span, declared.name, declared.ordinal, declared.signature, declared.linkage);
					if (mode == 3) {
						changed.runtime_lifetimes = summary.encode ();
					} else {
						changed.bind_runtime_lifetimes (summary.encode ());
					} if (mode == 0) {
						var empty = LlvmAsyncRecordResult.from_native (artifact, changed, native, inputs);
						assert (empty != null && empty.owner_count == 0 && empty.empty_count == 1 && empty.empty_field (0));
						empty.verify (inputs);
						Test.message ("empty future shape requires its independent null publication proof");
					} else {
						if (mode == 6) {
							refusal_text (() => { LlvmAsyncRecordResult.from_native (artifact, changed, native, inputs);
							}, "projection is absent");
						} else {
							assert (LlvmAsyncRecordResult.from_native (artifact, changed, native, inputs) == null);
						} Test.message ("future result shape control %d refused", mode);
					}
				}
			}
			declared = null;
			function = null;
			native = null;
			structs = null;
			source = null;
			assert (weak.get () == null);
			result.verify (inputs);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_task_result_publication() {
	try {
		string text = "[ExceptionRoot]class ResultError{init(string message){}virtual property string message{get{return \"result\";}}}enum Phase{Completed,Cancelled}async runtime Tasks throws ResultError returns Phase;[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}struct Packet{owned Captured first;owned Captured second;int marker;}async Packet deliver(Packet input){return move input;}int main(){return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.result_publication (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_task_result_callers() {
	try {
		string text = "[ExceptionRoot]class ResultError{init(string message){}virtual property string message{get{return \"result\";}}}enum Phase{Completed,Cancelled}async runtime Tasks throws ResultError returns Phase;[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}struct Packet{owned Captured first;owned Captured second;int marker;}async Packet deliver(Packet input){return move input;}async void collect(Packet input)throws ResultError{var pending=deliver(move input);var result=await move pending;await delay_ticks(1);}int main(){return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.result_callers (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_empty_task_result() {
	try {
		string text = "[ExceptionRoot]class ResultError{init(string message){}virtual property string message{get{return \"result\";}}}enum Phase{Completed,Cancelled}async runtime Tasks throws ResultError returns Phase;[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}owned Captured vacant(){return null;}struct Packet{owned Captured child;int marker;}async Packet deliver(Packet input,int mode){if(mode==0){Packet empty={child=vacant(),marker=17};return move empty;}return move input;}int main(){return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.empty_result_access (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_host_scoped_errors() {
	try {
		string text;
		FileUtils.get_contents ("tests/runtime-composition-17/host-scoped-errors.astra", out text);
		text = text.replace ("ScopedAllocator", "Scoped").replace ("scoped_allocator_query", "query");
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		int ordinal = -1;
		foreach (var function in source.functions) {
			if (function.name == "host_error_case") {
				ordinal = function.ordinal;
			}
		}
		assert (ordinal >= 0);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.host_scoped_errors (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal)));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_same_nominal_host_errors() {
	try {
		string text;
		FileUtils.get_contents ("tests/runtime-composition-17/same-nominal-errors.astra", out text);
		text = text.replace ("ScopedAllocator", "Scoped").replace ("scoped_allocator_query", "query");
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		int ordinal = -1;
		foreach (var function in source.functions) {
			if (function.name == "host_error_case") {
				ordinal = function.ordinal;
			}
		}
		assert (ordinal >= 0);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.same_nominal_errors (artifact, artifact.async_frames[0]);
		LlvmLifetimeTests.host_scoped_errors (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal)));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_mixed_error_choices() {
	try {
		string text;
		FileUtils.get_contents ("tests/runtime-composition-17/mixed-error-choices.astra", out text);
		text = text.replace ("ScopedAllocator", "Scoped").replace ("scoped_allocator_query", "query");
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		int ordinal = -1;
		foreach (var function in source.functions) {
			if (function.name == "mixed_error_case") {
				ordinal = function.ordinal;
			}
		}
		assert (ordinal >= 0);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.mixed_error_choices (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal)));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_heap_catch_choices() {
	try {
		string text;
		FileUtils.get_contents ("tests/runtime-composition-17/heap-catch-choices.astra", out text);
		text = text.replace ("ScopedAllocator", "Scoped").replace ("scoped_allocator_query", "query");
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		int ordinal = -1;
		foreach (var function in source.functions) {
			if (function.name == "heap_choice_case") {
				ordinal = function.ordinal;
			}
		}
		assert (ordinal >= 0);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.heap_catch_choices (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal)));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_mutating_scoped_fields() {
	mutating_scoped_fields_case (false);
}

private void llvm_empty_mutating_scoped_fields() {
	mutating_scoped_fields_case (true);
}

private void mutating_scoped_fields_case(bool empty) {
	try {
		string text;
		FileUtils.get_contents ("tests/runtime-composition-17/mutable-scoped-fields.astra", out text);
		text = text.replace ("ScopedAllocator", "Scoped").replace ("scoped_allocator_query", "query");
		if (empty) {
			text = text.replace ("init(owned MutableLeaf input) { this.child = move input; }", "init() { this.child = mutable_empty(); }").replace ("var envelope = new MutableEnvelope(move initial);", "var envelope = new MutableEnvelope(); envelope.replace(move initial);");
			text += "owned MutableLeaf mutable_empty(){return null;}";
		}
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		int caller = -1;
		foreach (var function in source.functions) {
			if (function.name == "mutable_case") {
				caller = function.ordinal;
			}
		}
		assert (caller >= 0);
		var weak = WeakRef (source.functions[caller]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.mutating_scoped_fields (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (caller)), empty);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_empty_deferred_scoped_errors() {
	empty_deferred_scoped_errors (false);
}

private void llvm_exported_empty_deferred_scoped_errors() {
	empty_deferred_scoped_errors (true);
}

private void empty_deferred_scoped_errors(bool exported) {
	try {
		string text = "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}[ExceptionRoot]class Fault{private owned Captured child;init(owned Captured input){this.child=move input;}virtual property string message{get{return \"deferred\";}}}class AdmissionFault:Fault{init(string message):base(null){}}enum Phase{Completed,Cancelled}async runtime Tasks throws AdmissionFault returns Phase;async void fail(owned Captured input)throws Fault{await delay_ticks(1);var error=new Fault(move input);throw move error;}int main(){return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		LlvmNativeModulePlan? plan = exported ? new LlvmNativeModulePlan () : null;
		if (plan != null) {
			foreach (var function in source.functions) {
				string key = LlvmNativeModulePlan.function_key (function);
				plan.bind (function, native.functions[function.ordinal].signature, native, "astra_mod_empty_" + Checksum.compute_for_string (ChecksumType.SHA256, key), false);
			}
			foreach (var owner in source.classes) {
				if (owner.polymorphic) {
					plan.bind_descriptor (owner, native, "astra_mod_empty_descriptor_" + Checksum.compute_for_string (ChecksumType.SHA256, owner.name), false);
				}
			}
		}
		var artifact = LlvmLowering.lower (source, native, foreign, null, null, false, false, plan);
		plan = null;
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.empty_deferred_errors (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_cold_capture_transfers() {
	try {
		string text = "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}[ExceptionRoot]class Fault{init(string message){}virtual property string message{get{return \"frame\";}}}enum Phase{Completed,Cancelled}async runtime Tasks throws Fault returns Phase;struct Packet{owned Captured child;int marker;}async Packet relay(Packet input,int mode)throws Fault{await delay_ticks(1);return move input;}void inspect(borrowed Packet input){}async void parent(owned Captured input,int mode)throws Fault{Packet packet={child=move input,marker=17};var child=relay(move packet,mode);var result=await move child;inspect(result);}int main(){return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		int ordinal = -1;
		foreach (var function in source.functions) {
			if (function.name == "parent") {
				ordinal = function.ordinal;
			}
		}
		assert (ordinal >= 0);
		var weak = WeakRef (source.functions[ordinal]);
		var native = NativeAbiBuilder.build (source);
		source = null;
		assert (weak.get () == null);
		int index = -1;
		for (int f = 0; f < native.async_frames.length; f++) {
			if (native.async_frames[f].function_ordinal == ordinal) {
				index = f;
			}
		}
		assert (index >= 0);
		var frame = native.async_frames[index];
		int captured = -1;
		int local = -1;
		for (uint o = 0; o < frame.owner_count; o++) {
			if (frame.owner (o).capture_first_leaf == 0) {
				assert (captured < 0);
				captured = (int) o;
			} else if (frame.owner (o).class_ordinal >= 0 && !frame.owner (o).catch_owner) {
				local = (int) o;
			}
		}
		assert (captured >= 0 && local >= 0);
		for (int mode = 0; mode < 3; mode++) {
			var owners = new GenericArray<NativeAsyncOwner> ();
			for (uint o = 0; o < frame.owner_count; o++) {
				var owner = frame.owner (o);
				bool changed = mode == 0 ? o == captured : o == local;
				owners.add (changed ? new NativeAsyncOwner (owner.ordinal, owner.source_ordinal, owner.class_ordinal, owner.catch_owner, owner.cleanup_symbol, mode == 0 ? -1 : mode == 1 ? 0 : 1, owner.cleanup_position, owner.closure, owner.context, owner.record_rank) : owner);
			}
			var fields = new GenericArray<NativeAsyncField> ();
			for (uint f = 0; f < frame.field_count; f++) {
				fields.add (frame.field (f));
			}
			var states = new GenericArray<NativeAsyncState> ();
			for (uint t = 0; t < frame.state_count; t++) {
				states.add (frame.state (t));
			}
			var buffers = new GenericArray<NativeAsyncBuffer> ();
			for (uint f = 0; f < frame.buffer_count; f++) {
				buffers.add (frame.buffer (f));
			}
			var storage = new GenericArray<NativeAsyncStorage> ();
			for (uint f = 0; f < frame.storage_count; f++) {
				storage.add (frame.storage_slot (f));
			}
			var waits = new GenericArray<NativeAsyncWait> ();
			for (uint w = 0; w < frame.wait_count; w++) {
				waits.add (frame.wait (w));
			}
			var mutant = new NativeAsyncFramePlan (frame.function_ordinal, frame.declaration, frame.result, fields, states, frame.object_count, frame.owner_count, buffers, owners, storage, null, frame.record_result, null, waits, frame.provider);
			native.async_frames[index] = mutant;
			refusal_text (() => NativeAbiVerifier.verify (native), mode == 0 ? "missing original incoming owner" : mode == 1 ? "one exact incoming owner parameter" : "unique complete incoming record cleanup");
			native.async_frames[index] = frame;
			NativeAbiVerifier.verify (native);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private CheckedProgram imported_scope_program(string producer, string consumer, HashTable<string, string> contracts, HashTable<string, string> symbols, bool imported) throws GLib.Error {
	var source = new SourceFile.from_text ("opaque-producer.astra", producer, imported);
	var parsed = Parser.parse (source);
	var caller = Parser.parse (new SourceFile.from_text ("opaque-consumer.astra", consumer));
	var api = VapiParser.parse (new SourceFile.from_text ("opaque-context.vapi", SCOPED_API));
	assert (parsed.diagnostic == null && caller.diagnostic == null && api.diagnostic == null);
	var units = new GenericArray<CompilationUnitSyntax> ();
	units.add (parsed.unit);
	units.add (caller.unit);
	NativeDeclarationRegistry? declarations = null;
	if (imported) {
		declarations = new NativeDeclarationRegistry ();
		foreach (string key in contracts.get_keys ()) {
			declarations.add (source, new NativeDeclarationIdentity ("opaque-scope", key, symbols.lookup (key), "pending", "", false, "", "", contracts.lookup (key)));
		}
	}
	var analyzed = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), VapiNormalizer.normalize (api.file), VapiNormalizer.normalize_handles (api.file), null, null, declarations);
	if (analyzed.diagnostic != null) {
		error ("%s", analyzed.diagnostic.format ());
	}
	return analyzed.program;
}

private void llvm_imported_scoped_tasks() {
	try {
		string producer;
		string consumer;
		FileUtils.get_contents ("tests/runtime-composition-17/opaque-scoped-task-producer.astra", out producer);
		FileUtils.get_contents ("tests/runtime-composition-17/opaque-scoped-task-consumer.astra", out consumer);
		producer = producer.replace ("ScopedAllocator", "Scoped");
		consumer = consumer.replace ("ScopedAllocator", "Scoped").replace ("scoped_allocator_query", "query");
		var contracts = new HashTable<string, string> (str_hash, str_equal);
		var symbols = new HashTable<string, string> (str_hash, str_equal);
		CheckedProgram? checked = imported_scope_program (producer, consumer, contracts, symbols, false);
		foreach (var definition in checked.all_definitions ()) {
			string key = NativeDeclarationRegistry.function_key (definition.symbol);
			if (!(key.has_prefix ("C:OpaqueScope.Leaf::") || key.has_prefix ("C:OpaqueScope.Fault::") || key == "F:OpaqueScope.make" || key == "F:OpaqueScope.read" || key == "F:OpaqueScope.relay")) {
				continue;
			}
			contracts.insert (key, "runtime-lifetime-logical/1\n" + definition.runtime_lifetimes.encode ());
			symbols.insert (key, "astra_mod_opaque_scope_" + Checksum.compute_for_string (ChecksumType.SHA256, key));
		}
		// First derive physical signatures with declaration effects, then bind
		// their exact identities before the final independent lowering.
		checked = imported_scope_program (producer, consumer, contracts, symbols, true);
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked))));
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		var shapes = new HashTable<string, string> (str_hash, str_equal);
		foreach (var function in source.functions) {
			string key = LlvmNativeModulePlan.function_key (function);
			if (contracts.contains (key)) {
				shapes.insert (key, LlvmNativeModulePlan.signature_shape (function, native.functions[function.ordinal].signature, native));
			}
		}
		source = null;
		native = null;
		foreach (var definition in checked.all_definitions ()) {
			string key = NativeDeclarationRegistry.function_key (definition.symbol);
			if (contracts.contains (key)) {
				definition.bind_native_declaration (NativeDeclarationRegistry.signature (new NativeDeclarationIdentity ("opaque-scope", key, symbols.lookup (key), shapes.lookup (key), "", false, "", "", contracts.lookup (key)), definition.symbol));
			}
		}
		source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked))));
		checked = null;
		native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		LlvmNativeModulePlan? plan = new LlvmNativeModulePlan ();
		int parent = -1;
		int host = -1;
		int imported = -1;
		foreach (var function in source.functions) {
			string key = LlvmNativeModulePlan.function_key (function);
			if (contracts.contains (key)) {
				plan.bind (function, native.functions[function.ordinal].signature, native, symbols.lookup (key), true);
			}
			if (function.name == "native_scope_parent") {
				parent = function.ordinal;
			}
			if (function.name == "native_scope_case") {
				host = function.ordinal;
			}
			if (key == "F:OpaqueScope.read") {
				imported = function.ordinal;
			}
		}
		foreach (var owner in source.classes) {
			if (owner.polymorphic) {
				plan.bind_descriptor (owner, native, "astra_mod_opaque_descriptor_" + Checksum.compute_for_string (ChecksumType.SHA256, owner.name), true);
			}
		}
		assert (parent >= 0 && host >= 0 && imported >= 0);
		var weak = WeakRef (source.functions[imported]);
		var artifact = LlvmLowering.lower (source, native, foreign, null, null, false, false, plan);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		plan = null;
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		assert (artifact.async_frames.length == 1);
		LlvmLifetimeTests.imported_scoped_tasks (artifact, artifact.async_frames[0], CApi.named_function (artifact.module, "astra.fn.%d".printf (host)), CApi.named_function (artifact.module, symbols.lookup ("F:OpaqueScope.read")), CApi.named_function (artifact.module, symbols.lookup ("F:OpaqueScope.make")), CApi.named_function (artifact.module, symbols.lookup ("C:OpaqueScope.Leaf::deinit")));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_imported_scoped_errors() {
	try {
		string producer;
		string consumer;
		FileUtils.get_contents ("tests/runtime-composition-17/opaque-scoped-error-producer.astra", out producer);
		FileUtils.get_contents ("tests/runtime-composition-17/opaque-scoped-error-consumer.astra", out consumer);
		foreach (string line in producer.split ("\n")) {
			if (line.has_prefix ("extern(C)") && !line.contains ("host_error_retired") && !line.contains ("host_error_delay_arm")) {
				producer = producer.replace (line + "\n", "");
			}
		}
		foreach (string line in consumer.split ("\n")) {
			if (line.has_prefix ("extern(C)") && (line.contains ("host_error_retired") || line.contains ("host_error_delay_arm"))) {
				consumer = consumer.replace (line + "\n", "");
			}
		}
		string parent_text = "async void native_error_parent(owned OpaqueScope.HostErrorLeaf input,int mode)throws OpaqueScope.HostErrorFault{var child=OpaqueScope.host_error_fail(move input,mode);try{await move child;}catch(OpaqueScope.HostErrorFault error){await delay_ticks(1);int actual=error.read();throw;}}";
		consumer = consumer.replace ("int host_error_forward(", parent_text + "int host_error_forward(").replace ("var task = OpaqueScope.host_error_fail(move input, mode);", "var task = native_error_parent(move input, mode);");
		producer = producer.replace ("ScopedAllocator", "Scoped");
		consumer = consumer.replace ("ScopedAllocator", "Scoped").replace ("scoped_allocator_query", "query");
		var contracts = new HashTable<string, string> (str_hash, str_equal);
		var symbols = new HashTable<string, string> (str_hash, str_equal);
		CheckedProgram? checked = imported_scope_program (producer, consumer, contracts, symbols, false);
		SsaProgram? original = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked))));
		NativeAbiProgram? original_native = NativeAbiBuilder.build (original);
		// Include automatic owning-field/base destructors from their actual
		// lowered contracts. This fixture has one physical scalar per input.
		foreach (var function in original.functions) {
			string key = LlvmNativeModulePlan.function_key (function);
			if (!(key.has_prefix ("C:OpaqueScope.HostErrorLeaf::") || key.has_prefix ("C:OpaqueScope.HostErrorFault::") || key.has_prefix ("C:OpaqueScope.HostRuntimeFault::") || key == "F:OpaqueScope.host_error_fail")) {
				continue;
			}
			contracts.insert (key, RuntimeLifetimeSummary.decode (original_native.functions[function.ordinal].runtime_lifetimes).logical_archive ().encode ());
			symbols.insert (key, "astra_mod_opaque_error_" + Checksum.compute_for_string (ChecksumType.SHA256, key));
		}
		original = null;
		original_native = null;
		// First derive physical signatures with declaration effects, then bind
		// their exact identities before the final independent lowering.
		checked = imported_scope_program (producer, consumer, contracts, symbols, true);
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked))));
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		var shapes = new HashTable<string, string> (str_hash, str_equal);
		foreach (var function in source.functions) {
			string key = LlvmNativeModulePlan.function_key (function);
			if (contracts.contains (key)) {
				shapes.insert (key, LlvmNativeModulePlan.signature_shape (function, native.functions[function.ordinal].signature, native));
			}
		}
		source = null;
		native = null;
		foreach (var definition in checked.all_definitions ()) {
			string key = NativeDeclarationRegistry.function_key (definition.symbol);
			if (contracts.contains (key)) {
				definition.bind_native_declaration (NativeDeclarationRegistry.signature (new NativeDeclarationIdentity ("opaque-scope", key, symbols.lookup (key), shapes.lookup (key), "", false, "", "", contracts.lookup (key)), definition.symbol));
			}
		}
		foreach (var owner in checked.classes) {
			string key = "C:" + owner.semantic_type.display_name () + "::deinit";
			if (owner.destructor == null && contracts.contains (key)) {
				owner.native_destructor_declaration = new NativeDeclarationIdentity ("opaque-scope", key, symbols.lookup (key), shapes.lookup (key), "", false, "", "", contracts.lookup (key));
			}
		}
		source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked))));
		checked = null;
		native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		LlvmNativeModulePlan? plan = new LlvmNativeModulePlan ();
		int parent = -1;
		int host = -1;
		int imported = -1;
		foreach (var function in source.functions) {
			string key = LlvmNativeModulePlan.function_key (function);
			if (contracts.contains (key)) {
				plan.bind (function, native.functions[function.ordinal].signature, native, symbols.lookup (key), true);
			}
			if (function.name == "native_error_parent") {
				parent = function.ordinal;
			}
			if (function.name == "host_error_case") {
				host = function.ordinal;
			}
			if (key == "F:OpaqueScope.host_error_fail") {
				imported = function.ordinal;
			}
		}
		foreach (var owner in source.classes) {
			if (owner.polymorphic) {
				plan.bind_descriptor (owner, native, "astra_mod_opaque_descriptor_" + Checksum.compute_for_string (ChecksumType.SHA256, owner.name), true);
			}
		}
		assert (parent >= 0 && host >= 0 && imported >= 0);
		var weak = WeakRef (source.functions[imported]);
		var artifact = LlvmLowering.lower (source, native, foreign, null, null, false, false, plan);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		plan = null;
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		assert (artifact.async_frames.length == 1);
		LlvmLifetimeTests.imported_scoped_errors (artifact, CApi.named_function (artifact.module, symbols.lookup ("C:OpaqueScope.HostRuntimeFault::init")), CApi.named_function (artifact.module, symbols.lookup ("C:OpaqueScope.HostRuntimeFault::deinit")));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_await_scoped_errors() {
	try {
		string text;
		FileUtils.get_contents ("tests/runtime-composition-17/host-scoped-errors.astra", out text);
		text = text.replace ("ScopedAllocator", "Scoped").replace ("scoped_allocator_query", "query");
		text += "async void observe(owned HostErrorLeaf input,int mode)throws HostErrorFault{var child=host_error_fail(move input,mode);try{await move child;}catch(HostErrorFault error){await delay_ticks(1);int value=error.read();throw;}}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		int ordinal = -1;
		foreach (var function in source.functions) {
			if (function.name == "observe") {
				ordinal = function.ordinal;
			}
		}
		assert (ordinal >= 0);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		foreach (var frame in artifact.async_frames) {
			if ((void*) frame.factory == (void*) CApi.named_function (artifact.module, "astra.task.create.%d".printf (ordinal))) {
				LlvmLifetimeTests.await_scoped_errors (artifact, frame);
				return;
			}
		}
		assert_not_reached ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_deferred_scoped_error_publication() {
	try {
		string text = "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}[ExceptionRoot]class Fault{private owned Captured child;init(owned Captured input){this.child=move input;}virtual property string message{get{return \"deferred\";}}}class AdmissionFault:Fault{init(string message):base(null){}}enum Phase{Completed,Cancelled}async runtime Tasks throws AdmissionFault returns Phase;async void fail(owned Captured input)throws Fault{var error=new Fault(move input);throw move error;}int main(){return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.deferred_error_publication (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_pure_empty_task_results() {
	try {
		for (int profile = 0; profile < 3; profile++) {
			bool captures = profile != 1;
			bool single = profile == 2;
			string record = single ? "struct Packet{owned Captured child;}" : "struct Packet{owned Captured child;int marker;}";
			string text = "[ExceptionRoot]class EmptyError{init(string message){}virtual property string message{get{return \"empty\";}}}enum Phase{Completed,Cancelled}async runtime Tasks throws EmptyError returns Phase;[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}owned Captured vacant(){return null;}" + record + "async Packet deliver(" + (captures ? "Packet input" : "") + "){Packet empty={child=vacant()" + (single ? "" : ",marker=17") + "};return move empty;}int main(){return 0;}";
			SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
			var weak = WeakRef (source.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (source);
			CAbiProgram? foreign = CAbiBuilder.build (source, native);
			var artifact = LlvmLowering.lower (source, native, foreign);
			new LlvmTargetMachineArtifact (0).configure (artifact);
			source = null;
			native = null;
			foreign = null;
			assert (weak.get () == null);
			LlvmLifetimeTests.pure_empty_result (artifact, captures, single);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_checked_scoped_captures() {
	try {
		string text = "[ExceptionRoot]class FrameFault{init(string message){}virtual property string message{get{return \"frame\";}}}enum Phase{Completed,Cancelled}async runtime Tasks throws FrameFault returns Phase;[Allocator(kind=\"context\",context=\"scoped-affine\")]class Capture{private int marker;init(){this.marker=17;}}async void child(owned Capture input){}int helper(borrowed Scoped objects){var input=new(objects)Capture();try{var executor=Tasks.open(8);var pending=checked_task_in(objects,child(move input));var status=executor.run(move pending);}catch(FrameFault error){}return 0;}int main(){owned u8[] backing=new u8[8197];var objects=scoped_allocator<Scoped>(backing,1,2);return helper(objects);}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.checked_captures (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_nested_scoped_captures() {
	try {
		string text = "[ExceptionRoot]class CaptureError{init(string message){}virtual property string message{get{return \"capture\";}}}enum Phase{Completed,Cancelled}async runtime Tasks throws CaptureError returns Phase;[Allocator(kind=\"context\",context=\"scoped-affine\")]class Capture{private int marker;init(){this.marker=17;}}async void child(owned Capture input)throws CaptureError{await delay_ticks(1);}async void parent(owned Capture input)throws CaptureError{var task=child(move input);await move task;await delay_ticks(1);}int main(){return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.nested_captures (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_emitted_scoped_captured_tasks() {
	try {
		string text = "[ExceptionRoot]class CaptureError{init(string message){}virtual property string message{get{return \"capture\";}}}enum Phase{Completed,Cancelled}async runtime Tasks throws CaptureError returns Phase;[Allocator(kind=\"context\",context=\"scoped-affine\")]class Capture{private int marker;init(){this.marker=17;}}async void child(owned Capture input){}int main(){owned u8[] backing=new u8[8197];var context=scoped_allocator<Scoped>(backing,1,1);var input=new(context)Capture();try{var executor=Tasks.open(8);var task=child(move input);var status=executor.run(move task);}catch(CaptureError error){return 1;}return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.captured_task_callers (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_scoped_coroutine_captures() {
	try {
		string text = "[ExceptionRoot]class CaptureError{init(string message){}virtual property string message{get{return \"capture\";}}}enum Phase{Completed,Cancelled}async runtime Tasks throws CaptureError returns Phase;[Allocator(kind=\"context\",context=\"scoped-affine\")]class Capture{private int marker;init(){this.marker=17;}}async void child(owned Capture input)throws CaptureError{await delay_ticks(1);}int main(){return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		assert (artifact.async_frames.length == 1 && artifact.async_frames[0].scoped_captures != null && artifact.async_frames[0].scoped_captures.count == 1);
		LlvmLifetimeTests.coroutine_captures (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void llvm_coroutine_continuations() {
	try {
		string text = "[ExceptionRoot]class ContinuationError{init(string message){}virtual property string message{get{return \"continuation\";}}}enum Phase{Completed,Cancelled}async runtime Tasks throws ContinuationError returns Phase;class Capture{private int marker;init(){this.marker=17;}}async int child(owned Capture input)throws ContinuationError{await delay_ticks(1);return 17;}async void root(owned Capture input)throws ContinuationError{var pending=child(move input);int result=await move pending;await delay_ticks(2);}int main(){return 0;}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.coroutine_continuations (artifact);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void emitted_scoped_task_frames() {
	try {
		string text = "[ExceptionRoot]class FrameError{init(string message){}virtual property string message{get{return \"frame\";}}}enum FrameStatus{Completed,Cancelled}async runtime Frames throws FrameError returns FrameStatus;async void child()throws FrameError{await delay_ticks(1);}int helper(borrowed Scoped frames){try{var executor=Frames.open(8);var task=checked_task_in(frames,child());var status=executor.run(move task);match(status){case FrameStatus.Completed():{}else:{return 2;}}}catch(FrameError error){return 1;}return 0;}int main(){owned u8[] backing=new u8[8197];var frames=scoped_allocator<Scoped>(backing,1,1);return helper(frames);}";
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (text, SCOPED_API)))));
		int helper = -1;
		foreach (var function in source.functions) {
			if (function.name == "helper") {
				helper = function.ordinal;
			}
		}
		assert (helper >= 0);
		var weak = WeakRef (source.functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var artifact = LlvmLowering.lower (source, native, foreign);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		source = null;
		native = null;
		foreign = null;
		assert (weak.get () == null);
		LlvmLifetimeTests.emitted_task_frames (artifact, CApi.named_function (artifact.module, "astra.fn.%d".printf (helper)));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/context/llvm-same-nominal-errors", llvm_same_nominal_host_errors);
	Test.add_func ("/context/llvm-empty-mutating-scoped-fields", llvm_empty_mutating_scoped_fields);
	Test.add_func ("/context/llvm-mutating-scoped-fields", llvm_mutating_scoped_fields);
	Test.add_func ("/context/llvm-imported-scoped-errors", llvm_imported_scoped_errors);
	Test.add_func ("/context/llvm-exported-empty-deferred-scoped-errors", llvm_exported_empty_deferred_scoped_errors);
	Test.add_func ("/context/native-cold-capture-transfers", native_cold_capture_transfers);
	Test.add_func ("/context/llvm-imported-scoped-tasks", llvm_imported_scoped_tasks);
	Test.add_func ("/context/llvm-host-scoped-errors", llvm_host_scoped_errors);
	Test.add_func ("/context/llvm-mixed-error-choices", llvm_mixed_error_choices);
	Test.add_func ("/context/llvm-heap-catch-choices", llvm_heap_catch_choices);
	Test.add_func ("/context/llvm-empty-deferred-scoped-errors", llvm_empty_deferred_scoped_errors);
	Test.add_func ("/context/llvm-await-scoped-errors", llvm_await_scoped_errors);
	Test.add_func ("/context/llvm-deferred-scoped-error-publication", llvm_deferred_scoped_error_publication);
	Test.add_func ("/context/llvm-pure-empty-task-results", llvm_pure_empty_task_results);
	Test.add_func ("/context/llvm-scoped-empty-task-result", llvm_scoped_empty_task_result);
	Test.add_func ("/context/llvm-scoped-task-result-callers", llvm_scoped_task_result_callers);
	Test.add_func ("/context/llvm-scoped-task-result-publication", llvm_scoped_task_result_publication);
	Test.add_func ("/context/native-scoped-task-result-shapes", native_scoped_task_result_shapes);
	Test.add_func ("/context/llvm-checked-scoped-captures", llvm_checked_scoped_captures);
	Test.add_func ("/context/llvm-nested-scoped-captures", llvm_nested_scoped_captures);
	Test.add_func ("/context/llvm-emitted-scoped-captured-tasks", llvm_emitted_scoped_captured_tasks);
	Test.add_func ("/context/llvm-scoped-coroutine-captures", llvm_scoped_coroutine_captures);
	Test.add_func ("/context/llvm-coroutine-continuations", llvm_coroutine_continuations);
	Test.add_func ("/context/llvm-emitted-scoped-task-frames", emitted_scoped_task_frames);
	Test.add_func ("/context/llvm-scoped-task-frame-lifetimes", LlvmLifetimeTests.scoped_task_frames);
	Test.add_func ("/context/native-cold-task-lifetime-roles", native_cold_task_summary_roles);
	Test.add_func ("/context/native-exception-lifetime-roles", native_exception_summary_roles);
	Test.add_func ("/context/checked-policy", checked_policy);
	Test.add_func ("/context/scoped-backing-detached-stages", scoped_backing_stages);
	Test.add_func ("/context/fallible-input-detached-stages", fallible_input_stages);
	Test.add_func ("/context/fallible-buffer-detached-stages", fallible_buffers);
	Test.add_func ("/context/fallible-record-detached-stages", fallible_records);
	Test.add_func ("/context/checked-frame-detached-stages", checked_frame_stages);
	Test.add_func ("/context/checked-frame-buffer-detached-stages", checked_frame_buffers);
	Test.add_func ("/context/checked-frame-record-detached-stages", checked_record_frames);
	Test.add_func ("/context/owning-record-frame-detached-stages", owning_record_frames);
	Test.add_func ("/context/owning-record-task-result-detached-stages", owning_record_task_results);
	Test.add_func ("/context/core-detached-policy-unwind", core_policy_and_unwind);
	Test.add_func ("/context/cfg-detached-unwind", cfg_unwind);
	Test.add_func ("/context/ssa-detached-unwind", ssa_unwind);
	Test.add_func ("/context/native-detached-unwind", native_unwind);
	Test.add_func ("/context/llvm-detached-origin", llvm_origin);
	Test.add_func ("/context/llvm-detached-refusal-join", llvm_refusal_join);
	Test.add_func ("/context/ssa-detached-task-pointer-join", ssa_task_pointer_join);
	Test.add_func ("/context/owning-record-detached-stages", owning_record_stages);
	Test.add_func ("/context/owning-record-mixed-detached-stages", owning_record_mixed_stages);
	Test.add_func ("/context/byte-buffer-detached-stages", context_byte_stages);
	Test.add_func ("/context/worker-byte-parameter-group", worker_byte_group);
	Test.add_func ("/context/throwing-byte-failure-channel", throwing_byte_failure);
	Test.add_func ("/context/byte-view-keeps-owning-origin", context_byte_view);
	Test.add_func ("/context/native-detached-runtime-lifetime-summary", native_lifetime_summary);
	Test.add_func ("/context/llvm-detached-scoped-controller-uses", llvm_scoped_controller_uses);
	Test.add_func ("/context/llvm-detached-scoped-allocation-lifetimes", LlvmLifetimeTests.local_allocations);
	Test.add_func ("/context/llvm-detached-scoped-owner-storage", LlvmLifetimeTests.owner_storage);
	Test.add_func ("/context/llvm-short-circuit-owners", LlvmLifetimeTests.short_circuit_owners);
	Test.add_func ("/context/llvm-detached-scoped-field-effects", llvm_scoped_field_effects);
	Test.add_func ("/context/llvm-detached-scoped-field-loans", llvm_scoped_field_loans);
	Test.add_func ("/context/llvm-detached-scoped-field-backing-policy", llvm_scoped_field_policy);
	Test.add_func ("/context/llvm-detached-scoped-heap-fields", llvm_scoped_heap_fields);
	Test.add_func ("/context/llvm-detached-scoped-context-heap-fields", llvm_scoped_context_heap_fields);
	Test.add_func ("/context/llvm-detached-context-factory-carriers", llvm_context_factory_heap_fields);
	Test.add_func ("/context/llvm-detached-fallible-context-carriers", llvm_fallible_context_heap_fields);
	Test.add_func ("/context/llvm-detached-multiple-context-carriers", llvm_multiple_context_heap_fields);
	Test.add_func ("/context/llvm-detached-checked-heap-result", llvm_checked_heap_result);
	Test.add_func ("/context/llvm-scoped-error-payload", llvm_scoped_error_payload);
	Test.add_func ("/context/llvm-exception-caller-transport", llvm_exception_caller_transport);
	Test.add_func ("/context/llvm-exception-catch-retirement", llvm_exception_catch_retirement);
	Test.add_func ("/context/llvm-exception-composition", llvm_exception_composition);
	Test.add_func ("/context/llvm-exception-context-companion", llvm_exception_context_companion);
	Test.add_func ("/context/llvm-exception-success-output", llvm_exception_success_output);
	Test.add_func ("/context/llvm-exception-null-payload", llvm_exception_null_payload);
	Test.add_func ("/context/llvm-exception-repeated-retirement", llvm_exception_repeated_retirement);
	Test.add_func ("/context/llvm-borrowed-scalar-fields", llvm_borrowed_scalar_fields);
	Test.add_func ("/context/llvm-nested-formal-authority", llvm_nested_formal_authority);
	Test.add_func ("/context/cfg-record-inputs", cfg_record_inputs);
	Test.add_func ("/context/ssa-record-inputs", ssa_record_inputs);
	Test.add_func ("/context/llvm-record-owned-inputs", llvm_record_owned_inputs);
	Test.add_func ("/context/llvm-record-borrowed-inputs", llvm_record_borrowed_inputs);
	Test.add_func ("/context/llvm-record-context-inputs", llvm_record_context_inputs);
	Test.add_func ("/context/llvm-mixed-record-inputs", llvm_mixed_record_inputs);
	Test.add_func ("/context/ssa-record-creation", ssa_record_creation);
	Test.add_func ("/context/ssa-record-local-moves", ssa_record_local_moves);
	Test.add_func ("/context/cfg-record-results", cfg_record_results);
	Test.add_func ("/context/ssa-record-results", ssa_record_results);
	Test.add_func ("/context/cfg-record-producers", cfg_record_producers);
	Test.add_func ("/context/cfg-checked-record-producers", cfg_checked_record_producers);
	Test.add_func ("/context/ssa-checked-record-producers", ssa_checked_record_producers);
	Test.add_func ("/context/llvm-checked-record-error-payload", llvm_checked_record_error_payload);
	Test.add_func ("/context/ssa-record-producers", ssa_record_producers);
	Test.add_func ("/context/llvm-output-scope-inventory", llvm_output_scope_inventory);
	Test.add_func ("/context/llvm-single-record-results", llvm_single_record_results);
	Test.add_func ("/context/llvm-multi-record-results", llvm_multi_record_results);
	Test.add_func ("/context/llvm-record-result-loans", llvm_record_result_loans);
	Test.add_func ("/context/llvm-class-loan-origins", llvm_class_loan_origins);
	Test.add_func ("/context/llvm-receiver-origins", llvm_receiver_origins);
	Test.add_func ("/context/llvm-empty-carriers", llvm_empty_carriers);
	Test.add_func ("/context/llvm-fresh-scoped-construction", llvm_fresh_scoped_construction);
	Test.add_func ("/context/llvm-fresh-scoped-results", llvm_fresh_scoped_results);
	Test.add_func ("/context/llvm-scoped-owning-receiver", llvm_scoped_owning_receiver);
	Test.add_func ("/context/llvm-fresh-owning-results", llvm_fresh_owning_results);
	Test.add_func ("/context/llvm-fresh-graph-results", llvm_fresh_graph_results);
	Test.add_func ("/context/llvm-scoped-child-graphs", llvm_scoped_child_graphs);
	Test.add_func ("/context/llvm-scoped-graph-forwarding", llvm_scoped_graph_forwarding);
	Test.add_func ("/context/llvm-nullable-owned-arguments", llvm_nullable_owned_arguments);
	Test.add_func ("/context/llvm-scoped-graph-consumption", llvm_scoped_graph_consumption);
	Test.add_func ("/context/llvm-scoped-constructor-rollback", llvm_scoped_constructor_rollback);
	Test.add_func ("/context/llvm-scoped-owned-constructor-rollback", llvm_scoped_owned_constructor_rollback);
	Test.add_func ("/context/llvm-scoped-child-constructor-rollback", llvm_scoped_child_constructor_rollback);
	Test.add_func ("/context/llvm-scoped-deep-constructor-rollback", llvm_scoped_deep_constructor_rollback);
	Test.add_func ("/context/llvm-scoped-record-constructor-rollback", llvm_scoped_record_constructor_rollback);
	Test.add_func ("/context/llvm-scoped-record-child-paths", llvm_scoped_record_child_paths);
	Test.add_func ("/context/llvm-checked-record-child-paths", llvm_checked_record_child_paths);
	Test.add_func ("/context/llvm-scoped-buffer-graph-forwarding", llvm_scoped_buffer_graph_forwarding);
	Test.add_func ("/context/llvm-scoped-buffer-constructor-rollback", llvm_scoped_buffer_constructor_rollback);
	Test.add_func ("/context/llvm-scoped-heap-constructor-rollback", llvm_scoped_heap_constructor_rollback);
	Test.add_func ("/context/llvm-borrowed-graph-discovery", llvm_borrowed_graph_discovery);
	Test.add_func ("/context/llvm-multi-record-context-results", llvm_multi_record_context_results);
	Test.add_func ("/context/llvm-checked-single-record-results", llvm_checked_single_record_results);
	Test.add_func ("/context/llvm-exception-field-layout", llvm_exception_field_layout);
	Test.add_func ("/context/llvm-missing-formal-authority", llvm_missing_formal_authority);
	Test.add_func ("/context/llvm-detached-checked-context-input", llvm_checked_context_input);
	Test.add_func ("/context/llvm-detached-checked-scoped-input", llvm_checked_scoped_input);
	Test.add_func ("/context/llvm-detached-fallible-scoped-input", llvm_fallible_scoped_input);
	Test.add_func ("/context/llvm-detached-mixed-scoped-input", llvm_mixed_scoped_input);
	Test.add_func ("/context/llvm-detached-scoped-class-graph", llvm_scoped_graph_inventory);
	Test.add_func ("/context/llvm-detached-scoped-allocation-artifact", llvm_scoped_allocation_artifact);
	Test.add_func ("/context/llvm-detached-native-receiver-borrow", llvm_scoped_native_borrow);
	Test.add_func ("/context/native-detached-allocator-parameter-roles", native_allocator_parameters);
	Test.add_func ("/context/llvm-detached-scoped-context-inputs", llvm_scoped_context_inputs);
	Test.add_func ("/context/llvm-detached-scoped-owned-inputs", llvm_scoped_owned_inputs);
	Test.add_func ("/context/llvm-detached-scoped-forwarded-owner", llvm_scoped_forwarded_owner);
	return Test.run ();
}

}
