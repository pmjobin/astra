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

namespace Astra.Tests.OwnerSlots {
private CheckedProgram check() throws GLib.Error {
	string text;
	FileUtils.get_contents ("tests/container-1a/smoke.astra", out text);
	var parsed = Parser.parse (new SourceFile.from_text ("tests/container-1a/smoke.astra", text));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}
private CoreProgram core() throws GLib.Error {
	var p = CoreBuilder.build (check ());
	CoreVerifier.verify (p);
	return p;
}
private CfgProgram cfg() throws GLib.Error {
	return CfgBuilder.build (core ());
}
private SsaProgram ssa() throws GLib.Error {
	return SsaBuilder.build (cfg ());
}
private CoreFunction core_function(CoreProgram p, string name) {
	foreach (var f in p.functions) {
		if (f.name == name) {
			return f;
		}
	}
	assert_not_reached ();
}
private CfgFunction cfg_function(CfgProgram p, string name) {
	foreach (var f in p.functions) {
		if (f.name == name) {
			return f;
		}
	}
	assert_not_reached ();
}
private SsaFunction ssa_function(SsaProgram p, string name) {
	foreach (var f in p.functions) {
		if (f.name == name) {
			return f;
		}
	}
	assert_not_reached ();
}
private CoreStructField core_field(CoreProgram p) {
	foreach (var c in p.classes) {
		foreach (var f in c.fields) {
			if (f.semantic_type is OwnerSlotsType) {
				return f;
			}
		}
	}
	assert_not_reached ();
}
private CfgStructField cfg_field(CfgProgram p) {
	foreach (var c in p.classes) {
		foreach (var f in c.fields) {
			if (f.semantic_type is OwnerSlotsType) {
				return f;
			}
		}
	}
	assert_not_reached ();
}
private SsaStructField ssa_field(SsaProgram p) {
	foreach (var c in p.classes) {
		foreach (var f in c.fields) {
			if (f.semantic_type is OwnerSlotsType) {
				return f;
			}
		}
	}
	assert_not_reached ();
}
private void core_reject(CoreProgram p, string diagnostic) {
	bool rejected = false;
	try {
		CoreVerifier.verify (p);
	} catch (CoreError error) {
		Test.message ("%s", error.message);
		rejected = error.message.contains (diagnostic);
	}
	assert (rejected);
}
private void cfg_reject(CfgProgram p, string diagnostic) {
	bool rejected = false;
	try {
		CfgVerifier.verify (p);
	} catch (CfgError error) {
		Test.message ("%s", error.message);
		rejected = error.message.contains (diagnostic);
	}
	assert (rejected);
}
private void ssa_reject(SsaProgram p, string diagnostic) {
	bool rejected = false;
	try {
		SsaVerifier.verify (p);
	} catch (SsaError error) {
		Test.message ("%s", error.message);
		rejected = error.message.contains (diagnostic);
	}
	assert (rejected);
}
private void llvm_reject(LlvmModuleArtifact a) {
	bool rejected = false;
	try {
		a.verify ();
	} catch (LlvmError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}
private void independent_models() {
	try {
		CheckedProgram? checked = check ();
		var prior = WeakRef (checked.functions[0]);
		CoreProgram? c = CoreBuilder.build (checked);
		checked = null;
		assert (prior.get () == null);
		CoreVerifier.verify (c);
		assert (core_field (c).slots_cleanup.is_heap_object);
		prior = WeakRef (core_function (c, "append"));
		CfgProgram? graph = CfgBuilder.build (c);
		c = null;
		assert (prior.get () == null);
		CfgVerifier.verify (graph);
		prior = WeakRef (cfg_function (graph, "append"));
		SsaProgram? model = SsaBuilder.build (graph);
		graph = null;
		assert (prior.get () == null);
		SsaVerifier.verify (model);
		assert (ssa_field (model).slots_cleanup.object_class.semantic_type == ((OwnerSlotsType) ssa_field (model).semantic_type).element);
		var native = NativeAbiBuilder.build (model);
		assert (native.abi_version == NativeAbiVersion.OWNER_SLOTS_V15);
		var a = LlvmLowering.lower (model, native, CAbiBuilder.build (model, native));
		prior = WeakRef (ssa_function (model, "append"));
		model = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (native);
		a.verify ();
		assert (a.dump ().contains ("reserve.moved.carrier") && a.dump ().contains ("drop.reverse.header"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void checked_mutations() {
	try {
		var p = check ();
		CheckedFunction? inspect = null;
		foreach (var f in p.functions) {
			if (f.symbol.name == "check") {
				inspect = f;
			}
		}
		assert (inspect != null);
		var returned = (CheckedReturnStatement) inspect.body.statements[0];
		var call = (CheckedCallExpression) returned.expression;
		var loan = (CheckedSlotsValue) call.arguments[0];
		var parameter = loan.borrower;
		var fake = new ParameterSymbol (parameter.span, parameter.name_span, parameter.semantic_type, parameter.ordinal, parameter.pointer_contract);
		call.arguments[0] = new CheckedSlotsValue (loan.span, loan.semantic_type, loan.store, loan.action, loan.operand, fake);
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (p));
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("loan lost exact call parameter");
		}
		assert (rejected);
		call.arguments[0] = loan;
		CoreVerifier.verify (CoreBuilder.build (p));
		// The incoming source's heap flag cannot reclassify its storage into
		// a lexical lifetime while the store still promises heap destruction.
		CheckedSlotsAppend? append = null;
		foreach (var f in p.functions) {
			foreach (var statement in f.body.statements) {
				if (statement is CheckedSlotsAppend) {
					append = (CheckedSlotsAppend) statement;
				}
			}
		}
		assert (append != null);
		append.incoming.source.heap_object = false;
		rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (p));
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			rejected = true;
		}
		assert (rejected);
		append.incoming.source.heap_object = true;
		CoreVerifier.verify (CoreBuilder.build (p));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void core_mutations() {
	try {
		var p = core ();
		var field = core_field (p);
		var cleanup = field.slots_cleanup;
		field.slots_cleanup = null;
		core_reject (p, "owner slots lost exact");
		field.slots_cleanup = cleanup;
		CoreVerifier.verify (p);
		var owner = (CoreClass) field.containing_type;
		var epilogue = owner.destructor.field_cleanups[0];
		owner.destructor.field_cleanups.remove_index (0);
		core_reject (p, "complete automatic destructor epilogue");
		owner.destructor.field_cleanups.add (epilogue);
		CoreVerifier.verify (p);
		var ctor = owner.constructor;
		var initialization = ctor.body.statements[0];
		ctor.body.statements.remove_index (0);
		core_reject (p, "not definitely initialized");
		ctor.body.statements.add (initialization);
		CoreVerifier.verify (p);
		var reserve = core_function (p, "reserve");
		var returned = (CoreReturn) reserve.body.statements[0];
		var v = (CoreSlotsValue) returned.value;
		reserve.body.statements[0] = new CoreReturn (returned.span, new CoreSlotsValue (v.span, v.semantic_type, v.store, OwnerSlotsAction.LENGTH, v.operand));
		core_reject (p, "query/reserve lost exact");
		reserve.body.statements[0] = returned;
		CoreVerifier.verify (p);
		var inspect = core_function (p, "check");
		var call = (CoreCallValue) ((CoreReturn) inspect.body.statements[0]).value;
		var loan = (CoreSlotsValue) call.arguments[0];
		call.arguments[0] = new CoreSlotsValue (loan.span, loan.semantic_type, loan.store, loan.action, null, loan.borrower);
		core_reject (p, "loan lost exact");
		call.arguments[0] = loan;
		CoreVerifier.verify (p);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void cfg_mutations() {
	try {
		var p = cfg ();
		var field = cfg_field (p);
		var cleanup = field.slots_cleanup;
		field.slots_cleanup = null;
		cfg_reject (p, "owner slots lost exact");
		field.slots_cleanup = cleanup;
		CfgVerifier.verify (p);
		var owner = (CfgClass) field.containing_type;
		var block = owner.destructor.entry;
		var drop = block.instructions[0];
		block.instructions.remove_index (0);
		cfg_reject (p, "reverse-order slot cleanup");
		block.instructions.add (drop);
		CfgVerifier.verify (p);
		var append_function = cfg_function (p, "append");
		CfgSlotsAppend? append = null;
		int index = -1;
		for (int i = 0; i < append_function.entry.instructions.length; i++) {
			if (append_function.entry.instructions[i] is CfgSlotsAppend) {
				append = (CfgSlotsAppend) append_function.entry.instructions[i];
				index = i;
			}
		}
		assert (append != null);
		var input = append.incoming;
		var fake = new CfgLocalPlace (input.span, input.name_span, input.name, input.semantic_type, input.ordinal, false, input.cleanup);
		append_function.entry.instructions[index] = new CfgSlotsAppend (append.span, append.store, fake);
		cfg_reject (p, "containing function");
		append_function.entry.instructions[index] = append;
		CfgVerifier.verify (p);
		assert (append_function.entry.instructions[index] == append);
		var reserve = cfg_function (p, "reserve");
		CfgEvaluateInstruction? evaluation = null;
		int reserve_index = -1;
		for (int i = 0; i < reserve.entry.instructions.length; i++) {
			var candidate = reserve.entry.instructions[i] as CfgEvaluateInstruction;
			if (candidate != null && candidate.value is CfgSlotsValue) {
				evaluation = candidate;
				reserve_index = i;
			}
		}
		assert (evaluation != null);
		var value = (CfgSlotsValue) evaluation.value;
		reserve.entry.instructions[reserve_index] = new CfgEvaluateInstruction (evaluation.span, new CfgSlotsValue (value.span, value.semantic_type, value.store, value.action, null), evaluation.result);
		cfg_reject (p, "count/capacity operand group");
		reserve.entry.instructions[reserve_index] = evaluation;
		CfgVerifier.verify (p);
		var inspect = cfg_function (p, "check");
		CfgSlotsBorrow? borrowed = null;
		int position = -1;
		for (int i = 0; i < inspect.entry.instructions.length; i++) {
			if (inspect.entry.instructions[i] is CfgSlotsBorrow) {
				borrowed = (CfgSlotsBorrow) inspect.entry.instructions[i];
				position = i;
			}
		}
		assert (borrowed != null);
		var loan = borrowed.result;
		// Inserting a genuine well-typed reserve between capture and call
		// must reject even though the element referent would stay in place.
		var requested = new CfgIntegerValue.typed (loan.span, loan.index.semantic_type, AstraIntegerValue.from_int64 ((IntegerType) loan.index.semantic_type, 3));
		var effect = new CfgSlotsValue (loan.span, value.semantic_type, loan.store, OwnerSlotsAction.RESERVE, requested);
		var captured = new CfgEvaluatedValue (loan.span, value.semantic_type);
		inspect.entry.instructions.insert (position + 1, new CfgEvaluateInstruction (loan.span, effect, captured));
		cfg_reject (p, "crosses indexed loan");
		inspect.entry.instructions.remove_index (position + 1);
		CfgVerifier.verify (p);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void ssa_mutations() {
	try {
		var p = ssa ();
		var field = ssa_field (p);
		var cleanup = field.slots_cleanup;
		field.slots_cleanup = null;
		ssa_reject (p, "owner slots lost exact");
		field.slots_cleanup = cleanup;
		SsaVerifier.verify (p);
		var append_function = ssa_function (p, "append");
		SsaSlotsEffect? append = null;
		SsaBlock? block = null;
		int position = -1;
		foreach (var candidate in append_function.blocks) {
			for (int i = 0; i < candidate.instructions.length; i++) {
				if (candidate.instructions[i] is SsaSlotsEffect) {
					append = (SsaSlotsEffect) candidate.instructions[i];
					block = candidate;
					position = i;
				}
			}
		}
		assert (append != null);
		var disarm = block.instructions[position + 1];
		block.instructions.remove_index (position + 1);
		ssa_reject (p, "immediate exact input disarm");
		block.instructions.insert (position + 1, disarm);
		SsaVerifier.verify (p);
		block.instructions[position] = new SsaSlotsEffect (append.span, append.action, append.store, new SsaNullPointerConstant (append.span, append.incoming.semantic_type), append.owner);
		ssa_reject (p, "input disarm");
		block.instructions[position] = append;
		SsaVerifier.verify (p);
		var forged = new SsaSlotsEffect (append.span, append.action, append.store, new SsaNullPointerConstant (append.span, append.incoming.semantic_type), append.owner);
		block.instructions[position] = forged;
		block.instructions[position + 1] = new SsaHeapOwnerEvent (append.span, append.owner, SsaHeapOwnerAction.MOVE, forged.incoming, forged);
		ssa_reject (p, "current exact owner pointer");
		block.instructions[position] = append;
		block.instructions[position + 1] = disarm;
		SsaVerifier.verify (p);
		var reserve = ssa_function (p, "reserve");
		var v = (SsaSlotsValueInstruction) reserve.entry.instructions[0];
		reserve.entry.instructions[0] = new SsaSlotsValueInstruction (v.span, v.result.semantic_type, v.result.ordinal, v.store, v.action);
		ssa_reject (p, "grouped operation shape");
		reserve.entry.instructions[0] = v;
		SsaVerifier.verify (p);
		var owner = (SsaClass) field.containing_type;
		var retirement = owner.destructor.entry.instructions[0];
		owner.destructor.entry.instructions.remove_index (0);
		ssa_reject (p, "reverse declaration owner-slot cleanup");
		owner.destructor.entry.instructions.add (retirement);
		SsaVerifier.verify (p);
		var inspect = ssa_function (p, "check");
		SsaSlotsValueInstruction? loan = null;
		int loan_index = -1;
		int next_ordinal = 0;
		foreach (var candidate in inspect.blocks) {
			for (int i = 0; i < candidate.instructions.length; i++) {
				var instruction = candidate.instructions[i];
				if (instruction.result != null) {
					next_ordinal = int.max (next_ordinal, instruction.result.ordinal + 1);
				}
				if (instruction is SsaSlotsValueInstruction && ((SsaSlotsValueInstruction) instruction).action == OwnerSlotsAction.BORROW) {
					loan = (SsaSlotsValueInstruction) instruction;
					block = candidate;
					loan_index = i;
				}
			}
		}
		assert (loan != null);
		var parameter = loan.borrower;
		var fake = new SsaFunctionParameter (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, parameter.ordinal, parameter.pointer_contract);
		block.instructions[loan_index] = new SsaSlotsValueInstruction (loan.span, loan.result.semantic_type, loan.result.ordinal, loan.store, loan.action, loan.operand, fake);
		ssa_reject (p, "requires one exact native call consumer");
		block.instructions[loan_index] = loan;
		SsaVerifier.verify (p);
		var request = new SsaIntegerConstant.typed (loan.span, loan.operand.semantic_type, AstraIntegerValue.from_int64 ((IntegerType) loan.operand.semantic_type, 3));
		block.instructions.insert (loan_index + 1, new SsaSlotsValueInstruction (loan.span, v.result.semantic_type, next_ordinal, loan.store, OwnerSlotsAction.RESERVE, request));
		ssa_reject (p, "crosses indexed loan");
		block.instructions.remove_index (loan_index + 1);
		SsaVerifier.verify (p);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_mutations() {
	try {
		var p = ssa ();
		var n = NativeAbiBuilder.build (p);
		var c = CAbiBuilder.build (p, n);
		var field = ssa_field (p);
		var owner = n.classes[field.containing_type.ordinal];
		var saved = owner.fields[field.ordinal];
		var slots = (NativeOwnerSlotsType) saved.storage_type;
		owner.fields[field.ordinal] = new NativeClassField (saved.span, saved.name, saved.type_name, saved.ordinal, saved.text_snapshot, new NativeSliceType (), -1);
		bool rejected = false;
		try {
			LlvmLowering.lower (p, n, c);
		} catch (GLib.Error error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("field") || error.message.contains ("storage");
		}
		assert (rejected);
		owner.fields[field.ordinal] = saved;
		LlvmLowering.lower (p, n, c).verify ();
		owner.fields[field.ordinal] = new NativeClassField (saved.span, saved.name, saved.type_name, saved.ordinal, false, new NativeOwnerSlotsType (slots.element_ordinal, slots.element_name, slots.destructor_ordinal, NativeScalarType.PTR, NativeScalarType.I32, NativeScalarType.PTR), -1);
		rejected = false;
		try {
			NativeAbiVerifier.verify (n);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("PTR/I32/I32");
		}
		assert (rejected);
		owner.fields[field.ordinal] = saved;
		LlvmLowering.lower (p, n, c).verify ();
		owner.fields[field.ordinal] = new NativeClassField (saved.span, saved.name, saved.type_name, saved.ordinal, false, new NativeOwnerSlotsType (owner.ordinal, owner.name, owner.destructor_ordinal), -1);
		rejected = false;
		try {
			NativeAbiVerifier.verify (n);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("owner slots require");
		}
		assert (rejected);
		owner.fields[field.ordinal] = saved;
		LlvmLowering.lower (p, n, c).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private LlvmModuleArtifact artifact() throws GLib.Error {
	var p = ssa ();
	var n = NativeAbiBuilder.build (p);
	return LlvmLowering.lower (p, n, CAbiBuilder.build (p, n));
}
private void llvm_mutations() {
	try {
		var a = artifact ();
		a.verify ();
		bool count = false, transfer = false, clear = false, commit = false, bounds = false, cleanup = false, destructor = false, old_free = false;
		for (var function = CApi.first_function (a.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			string name = CApi.value_name (function, out length);
			if (!name.has_prefix ("astra.slots.")) {
				continue;
			}
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					string value_name = CApi.value_name (instruction, out length);
					if (name.has_suffix (".reserve") && value_name == "reserve.checked.bytes" && !count) {
						var value = CApi.operand (instruction, 0);
						CApi.set_operand (instruction, 0, CApi.const_int (CApi.type_of (value), uint64.MAX, 0));
						llvm_reject (a);
						CApi.set_operand (instruction, 0, value);
						a.verify ();
						count = true;
					}
					if (name.has_suffix (".reserve") && value_name == "reserve.old.slot" && !transfer) {
						var index = CApi.operand (instruction, 1);
						CApi.set_operand (instruction, 1, CApi.const_int (CApi.type_of (index), int32.MAX, 0));
						llvm_reject (a);
						CApi.set_operand (instruction, 1, index);
						a.verify ();
						transfer = true;
					}
					if (name.has_suffix (".reserve") && CApi.opcode (instruction) == CApi.Opcode.STORE) {
						var destination = CApi.operand (instruction, 1);
						string target = CApi.value_name (destination, out length);
						if (target == "reserve.old.slot" && !clear) {
							var value = CApi.operand (instruction, 0);
							CApi.set_operand (instruction, 0, CApi.get_param (function, 0));
							llvm_reject (a);
							CApi.set_operand (instruction, 0, value);
							a.verify ();
							clear = true;
						}
						if (target == "slots.capacity.address" && !commit) {
							var value = CApi.operand (instruction, 0);
							CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (value)));
							llvm_reject (a);
							CApi.set_operand (instruction, 0, value);
							a.verify ();
							commit = true;
						}
					}
					if (name.has_suffix (".borrow") && value_name == "slots.index.outside.live" && !bounds) {
						var value = CApi.operand (instruction, 1);
						CApi.set_operand (instruction, 1, CApi.const_int (CApi.type_of (value), int32.MAX, 0));
						llvm_reject (a);
						CApi.set_operand (instruction, 1, value);
						a.verify ();
						bounds = true;
					}
					if (name.has_suffix (".drop") && value_name == "drop.slot.address" && !cleanup) {
						var index = CApi.operand (instruction, 1);
						CApi.set_operand (instruction, 1, CApi.const_null (CApi.type_of (index)));
						llvm_reject (a);
						CApi.set_operand (instruction, 1, index);
						a.verify ();
						cleanup = true;
					}
					if (CApi.opcode (instruction) == CApi.Opcode.CALL) {
						var callee = CApi.called_value (instruction);
						string called = CApi.value_name (callee, out length);
						if (name.has_suffix (".drop") && called.has_prefix ("astra.dtor.") && !destructor) {
							CApi.set_operand (instruction, CApi.argument_count (instruction), function);
							llvm_reject (a);
							CApi.set_operand (instruction, CApi.argument_count (instruction), callee);
							a.verify ();
							destructor = true;
						}
						if (name.has_suffix (".reserve") && called == "free" && !old_free) {
							var old = CApi.operand (instruction, 0);
							CApi.set_operand (instruction, 0, CApi.get_param (function, 0));
							llvm_reject (a);
							CApi.set_operand (instruction, 0, old);
							a.verify ();
							old_free = true;
						}
					}
				}
			}
		}
		assert (count && transfer && clear && commit && bounds && cleanup && destructor && old_free);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/container-1a/independent-models-and-v15-layout", independent_models);
	Test.add_func ("/container-1a/checked-heap-origin-and-call-loan-restored", checked_mutations);
	Test.add_func ("/container-1a/core-type-initialization-count-cleanup-loan-restored", core_mutations);
	Test.add_func ("/container-1a/cfg-heap-capacity-cleanup-mutation-exclusion-restored", cfg_mutations);
	Test.add_func ("/container-1a/ssa-group-owner-disarm-cleanup-restored", ssa_mutations);
	Test.add_func ("/container-1a/native-nominal-group-and-extent-restored", native_mutations);
	Test.add_func ("/container-1a/actual-llvm-count-transfer-disarm-commit-bounds-drop-restored", llvm_mutations);
	return Test.run ();
}
}
