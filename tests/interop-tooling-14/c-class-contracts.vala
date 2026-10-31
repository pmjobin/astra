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

namespace Astra.Tests.ForeignClassContracts {
private delegate void Check() throws GLib.Error;
private const string SOURCE = "[CExport(name=\"proof14\",property=\"value\")][Shared]class Cell{private int raw;init(int n){this.raw=n;}property int value{get{return this.raw;}set(int n){this.raw=n;}}deinit(){}}";
private void refused(string label, owned Check check) throws GLib.Error {
	bool rejected = false;
	try {
		check ();
	} catch (GLib.Error failure) {
		rejected = true;
		Test.message ("%s: %s", label, failure.message);
	}
	if (!rejected) {
		Test.message ("unexpectedly accepted %s", label);
	}
	assert (rejected);
}
private CheckedProgram source(bool com = false) {
	string attributes = com ? "[COMExport(value_iid=\"849ad154-8d1e-4c63-9ea2-14329b022001\",scale_iid=\"849ad154-8d1e-4c63-9ea2-14329b022002\",threading=\"constructing\")]" : "";
	var parsed = Parser.parse (new SourceFile.from_text ("foreign-class-proof.astra", attributes + SOURCE));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	return checked.program;
}
private void stage_authority() {
	try {
		CheckedProgram? checked = source ();
		var policy = checked.classes[0].foreign_export;
		checked.classes[0].foreign_export = null;
		refused ("checked policy loss", () => { CoreBuilder.build (checked);
		});
		checked.classes[0].foreign_export = policy;
		var upstream = WeakRef (checked.classes[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (upstream.get () == null);
		var core_policy = core.classes[0].foreign_export;
		core.classes[0].foreign_export = null;
		refused ("Core policy loss", () => CoreVerifier.verify (core));
		core.classes[0].foreign_export = core_policy;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.classes[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		var cfg_policy = cfg.classes[0].foreign_export;
		cfg.classes[0].foreign_export = null;
		refused ("CFG policy loss", () => CfgVerifier.verify (cfg));
		cfg.classes[0].foreign_export = cfg_policy;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.classes[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		var ssa_policy = ssa.classes[0].foreign_export;
		ssa.classes[0].foreign_export = new ForeignClassPolicy (ssa_policy.native_name, "substituted", ssa_policy.property_name, ssa_policy.property_ordinal);
		refused ("SSA substituted policy", () => SsaVerifier.verify (ssa));
		ssa.classes[0].foreign_export = ssa_policy;
		SsaVerifier.verify (ssa);
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		var getter = native.classes[0].foreign_getter;
		native.classes[0].foreign_getter = native.classes[0].foreign_setter;
		refused ("native substituted accessor", () => NativeAbiVerifier.verify (native));
		native.classes[0].foreign_getter = getter;
		NativeAbiVerifier.verify (native);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		assert (cabi.class_adapters.length == 1);
		var adapter = cabi.class_adapters[0];
		int original_getter = adapter.getter;
		adapter.getter = adapter.setter;
		refused ("C ABI substituted accessor", () => CAbiVerifier.verify (cabi));
		adapter.getter = original_getter;
		CAbiVerifier.verify (cabi);
		cabi.class_adapters.remove_index (0);
		refused ("C ABI missing adapter", () => { LlvmLowering.lower (ssa, native, cabi);
		});
		cabi.class_adapters.add (adapter);
		CAbiVerifier.verify (cabi);
		upstream = WeakRef (ssa.classes[0]);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		ssa = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		new LlvmTargetMachineArtifact ().configure (artifact);
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void ordinary(LlvmModuleArtifact module) {
	char* message;
	int status = CApi.verify_module (module.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	string diagnostic = message == null ? "" : (string) message;
	if (message != null) {
		CApi.dispose_message (message);
	}
	if (status != 0) {
		error ("ordinary LLVM control failed: %s", diagnostic);
	}
}
private void com_authority() {
	try {
		var checked = source (true);
		var contract = checked.classes[0].foreign_export.com;
		contract.release_slot = 1;
		refused ("checked COM premature release slot", () => { CoreBuilder.build (checked);
		});
		contract.release_slot = 2;
		var core = CoreBuilder.build (checked);
		contract = core.classes[0].foreign_export.com;
		contract.get_slot = 4;
		refused ("Core COM wrong vtable slot", () => CoreVerifier.verify (core));
		contract.get_slot = 3;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		contract = cfg.classes[0].foreign_export.com;
		contract.query_acquires = false;
		refused ("CFG COM missing QI retain", () => CfgVerifier.verify (cfg));
		contract.query_acquires = true;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		var policy = ssa.classes[0].foreign_export;
		contract = policy.com;
		policy.com = new ComExportContract ("849ad154-8d1e-4c63-9ea2-14329b022003", contract.scale_iid);
		refused ("SSA COM substituted IID", () => SsaVerifier.verify (ssa));
		policy.com = contract;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		contract = native.classes[0].foreign_export.com;
		contract.checked_context = false;
		refused ("native COM missing apartment guard", () => NativeAbiVerifier.verify (native));
		contract.checked_context = true;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		contract = cabi.class_adapters[0].policy.com;
		contract.windows_x64 = false;
		refused ("C ABI COM changed platform convention", () => CAbiVerifier.verify (cabi));
		contract.windows_x64 = true;
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi, null, null, false, false, null, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		new LlvmTargetMachineArtifact (0, LlvmTargetMachineArtifact.WINDOWS_INTEROP).configure (artifact);
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void scalar_pointer_authority() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("c-pointer-proof.astra", "[CImport(pointer_abi=\"i32-noescape\")]int update(int mode,borrowed int* value);int main(){int value=2;return update(0,&value);}"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var core = CoreBuilder.build (checked.program);
		var cfg = CfgBuilder.build (core);
		var ssa = SsaBuilder.build (cfg);
		var native = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, native);
		var parameter = cabi.functions[0].signature.parameters[1];
		assert (parameter.i32_pointer);
		parameter.i32_pointer = false;
		refused ("C ABI lost int pointer role", () => CAbiVerifier.verify (cabi));
		parameter.i32_pointer = true;
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		artifact.verify ();
		ordinary (artifact);
		int changed = 0;
		foreach (var imported in artifact.c_imports) {
			foreach (void* pointer in imported.calls) {
				var call = (CApi.ValueRef) pointer;
				var original = CApi.operand (call, 1);
				assert ((void*) CApi.is_constant_pointer_null (original) == null);
				CApi.set_operand (call, 1, CApi.const_null (CApi.type_of (original)));
				ordinary (artifact);
				refused ("LLVM substituted int out place", () => artifact.verify ());
				CApi.set_operand (call, 1, original);
				artifact.verify ();
				changed++;
			}
		}
		assert (changed == 1);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void imported_com_authority() {
	try {
		ParseResult? parsed = Parser.parse (new SourceFile.from_text ("com-import-proof.astra", "[COMImport(name=\"imported14\",iid=\"849ad154-8d1e-4c63-9ea2-14329b022001\",view=\"value\",threading=\"constructing\")]interface Imported;int exercise(void* input){int status=0;owned Imported value=imported14_acquire(input,&status);if(value==null){return status;}owned Imported copy=imported14_clone(value,&status);int out=0;return imported14_get(copy,&out);}"));
		assert (parsed.diagnostic == null);
		SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		parsed = null;
		var policy = checked.program.handles[0].com_import;
		checked.program.handles[0].com_import = null;
		refused ("checked COM import policy loss", () => { CoreBuilder.build (checked.program);
		});
		checked.program.handles[0].com_import = policy;
		var upstream = WeakRef (checked.program.handles[0]);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		assert (upstream.get () == null);
		var contract = core.handles[0].com_import;
		core.handles[0].com_import = new ComImportContract (contract.native_name, contract.prefix, "849ad154-8d1e-4c63-9ea2-14329b022003", contract.view);
		refused ("Core imported IID substitution", () => CoreVerifier.verify (core));
		core.handles[0].com_import = contract;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.handles[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		contract = cfg.handles[0].com_import;
		contract.release_slot = 1;
		refused ("CFG imported wrong release slot", () => CfgVerifier.verify (cfg));
		contract.release_slot = 2;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.handles[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		contract = ssa.handles[0].com_import;
		contract.checked_context = false;
		refused ("SSA imported missing context guard", () => SsaVerifier.verify (ssa));
		contract.checked_context = true;
		SsaVerifier.verify (ssa);
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		contract = native.com_imports[0];
		native.com_imports.remove_index (0);
		refused ("native imported missing identity", () => NativeAbiVerifier.verify (native));
		native.com_imports.add (contract);
		NativeAbiVerifier.verify (native);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		contract = cabi.functions[0].metadata.com_import;
		contract.query_slot = 1;
		refused ("C ABI imported wrong QI slot", () => CAbiVerifier.verify (cabi));
		contract.query_slot = 0;
		CAbiVerifier.verify (cabi);
		refused ("COM import relabeled Linux", () => { LlvmLowering.lower (ssa, native, cabi);
		});
		upstream = WeakRef (ssa.handles[0]);
		var artifact = LlvmLowering.lower (ssa, native, cabi, null, null, false, false, null, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		ssa = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		new LlvmTargetMachineArtifact (0, LlvmTargetMachineArtifact.WINDOWS_INTEROP).configure (artifact);
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void gobject_authority() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("gobject-proof.astra", "[GObjectExport(type=\"Proof14Cell\",namespace=\"Proof14\",version=\"1.0\")]" + SOURCE.replace ("proof14", "proof14_cell")));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var contract = checked.program.classes[0].foreign_export.gobject;
		contract.native_owner = false;
		refused ("checked GObject missing native owner", () => { CoreBuilder.build (checked.program);
		});
		contract.native_owner = true;
		var core = CoreBuilder.build (checked.program);
		contract = core.classes[0].foreign_export.gobject;
		contract.weak_cache = false;
		refused ("Core GObject unsafe cache", () => CoreVerifier.verify (core));
		contract.weak_cache = true;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		contract = cfg.classes[0].foreign_export.gobject;
		contract.floating = true;
		refused ("CFG GObject changed floating convention", () => CfgVerifier.verify (cfg));
		contract.floating = false;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		contract = ssa.classes[0].foreign_export.gobject;
		contract.checked_context = false;
		refused ("SSA GObject missing affinity", () => SsaVerifier.verify (ssa));
		contract.checked_context = true;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var policy = native.classes[0].foreign_export;
		contract = policy.gobject;
		policy.gobject = new GObjectExportContract ("Proof14Other", "Proof14", "1.0");
		refused ("native substituted GType", () => NativeAbiVerifier.verify (native));
		policy.gobject = contract;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		contract = cabi.class_adapters[0].policy.gobject;
		contract.native_owner = false;
		refused ("C ABI GObject missing root owner", () => CAbiVerifier.verify (cabi));
		contract.native_owner = true;
		CAbiVerifier.verify (cabi);
		refused ("GObject relabeled Windows", () => { LlvmLowering.lower (ssa, native, cabi, null, null, false, false, null, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		});
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact ().configure (artifact);
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void gobject_import_origin() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("gobject-import-proof.astra", "[GObjectImport(name=\"read14\",header=\"bridge.h\",pointer_abi=\"i32-noescape\")]int read(borrowed int* value);int main(){int value=0;return read(&value);}"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		checked.program.c_functions[0].metadata.import_policy = DeclarationPolicyId.C_IMPORT;
		refused ("checked GObject import origin loss", () => { CoreBuilder.build (checked.program);
		});
		checked.program.c_functions[0].metadata.import_policy = DeclarationPolicyId.GOBJECT_IMPORT;
		var core = CoreBuilder.build (checked.program);
		core.c_functions[0].metadata.import_policy = DeclarationPolicyId.C_IMPORT;
		refused ("Core GObject import relabeled C", () => CoreVerifier.verify (core));
		core.c_functions[0].metadata.import_policy = DeclarationPolicyId.GOBJECT_IMPORT;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		cfg.c_functions[0].metadata.import_policy = DeclarationPolicyId.C_IMPORT;
		refused ("CFG GObject import relabeled C", () => CfgVerifier.verify (cfg));
		cfg.c_functions[0].metadata.import_policy = DeclarationPolicyId.GOBJECT_IMPORT;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		ssa.c_functions[0].metadata.import_policy = DeclarationPolicyId.C_IMPORT;
		refused ("SSA GObject import relabeled C", () => SsaVerifier.verify (ssa));
		ssa.c_functions[0].metadata.import_policy = DeclarationPolicyId.GOBJECT_IMPORT;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		string identity = native.gobject_imports[0];
		native.gobject_imports.remove_index (0);
		refused ("native GObject import origin loss", () => NativeAbiVerifier.verify (native));
		native.gobject_imports.add (identity);
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		cabi.functions[0].metadata.import_policy = DeclarationPolicyId.C_IMPORT;
		refused ("C ABI GObject import relabeled C", () => CAbiVerifier.verify (cabi));
		cabi.functions[0].metadata.import_policy = DeclarationPolicyId.GOBJECT_IMPORT;
		CAbiVerifier.verify (cabi);
		refused ("GObject import relabeled Windows", () => { LlvmLowering.lower (ssa, native, cabi, null, null, false, false, null, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		});
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact ().configure (artifact);
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void union_authority() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("c-union-proof.astra", "[Repr(layout=\"C-tagged-union\",members=\"integer:i64,bits:u64\",active=\"integer\",tag=\"1\")]struct Packet{i64 tag;i64 integer;}[CImport(name=\"packet14\",record_abi=\"value-lp64\")]Packet receive(Packet value);[CExport(name=\"out_packet14\",record_abi=\"value-lp64\")]Packet send(Packet value){return receive(value);}"));
		assert (parsed.diagnostic == null);
		CheckedProgram? checked = SemanticAnalyzer.analyze (parsed.unit).program;
		assert (checked != null);
		checked.structs[0].representation.active_member = "bits";
		refused ("checked incompatible active union member", () => { CoreBuilder.build (checked);
		});
		checked.structs[0].representation.active_member = "integer";
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		core.structs[0].representation.union_tag = 2;
		refused ("Core substituted active union tag", () => CoreVerifier.verify (core));
		core.structs[0].representation.union_tag = 1;
		CoreVerifier.verify (core);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		cfg.structs[0].representation.union_members = "integer:f64,bits:u64";
		refused ("CFG incompatible union ABI class", () => CfgVerifier.verify (cfg));
		cfg.structs[0].representation.union_members = "integer:i64,bits:u64";
		CfgVerifier.verify (cfg);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		var representation = ssa.structs[0].representation;
		ssa.structs[0].representation = null;
		refused ("SSA missing active union projection", () => SsaVerifier.verify (ssa));
		ssa.structs[0].representation = representation;
		SsaVerifier.verify (ssa);
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		native.pod_layouts[0].active_member = "bits";
		refused ("native incompatible union member", () => NativeAbiVerifier.verify (native));
		native.pod_layouts[0].active_member = "integer";
		NativeAbiVerifier.verify (native);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var projection = cabi.functions[0].signature.result.record.union_projection;
		cabi.functions[0].signature.result.record.union_projection = null;
		refused ("C ABI missing union return projection", () => CAbiVerifier.verify (cabi));
		cabi.functions[0].signature.result.record.union_projection = projection;
		cabi.functions[0].signature.parameters[0].record.union_projection.union_tag = 2;
		refused ("C ABI invalid active union argument", () => CAbiVerifier.verify (cabi));
		cabi.functions[0].signature.parameters[0].record.union_projection.union_tag = 1;
		CAbiVerifier.verify (cabi);
		var upstream = WeakRef (ssa.structs[0]);
		representation = null;
		projection = null;
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		ssa = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		new LlvmTargetMachineArtifact ().configure (artifact);
		artifact.verify ();
		ordinary (artifact);
		int comparisons = 0;
		foreach (var binding in artifact.class_values) {
			var instruction = binding.instruction;
			size_t length;
			string name = CApi.value_name (instruction, out length);
			if (!name.has_prefix ("c.union.active.tag")) {
				continue;
			}
			var prior = CApi.operand (instruction, 1);
			CApi.set_operand (instruction, 1, CApi.const_int (CApi.type_of (prior), 2, 0));
			ordinary (artifact);
			refused ("LLVM ordinary-valid wrong union member tag", () => artifact.verify ());
			CApi.set_operand (instruction, 1, prior);
			artifact.verify ();
			comparisons++;
		}
		assert (comparisons == 4);
		var wrapper = CApi.named_function (artifact.module, "out_packet14");
		int edges = 0;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			var branch = CApi.block_terminator (block);
			if (CApi.successor_count (branch) != 2) {
				continue;
			}
			var accepted = CApi.successor (branch, 0);
			CApi.set_successor (branch, 0, CApi.successor (branch, 1));
			ordinary (artifact);
			refused ("LLVM ordinary-valid changed union admission edge", () => artifact.verify ());
			CApi.set_successor (branch, 0, accepted);
			artifact.verify ();
			edges++;
		}
		assert (edges == 2);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void physical_authority() {
	try {
		var checked = source ();
		var core = CoreBuilder.build (checked);
		var cfg = CfgBuilder.build (core);
		var ssa = SsaBuilder.build (cfg);
		var native = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		artifact.verify ();
		ordinary (artifact);
		int calls = 0, guards = 0, retirements = 0;
		foreach (var binding in artifact.class_calls) {
			var call = binding.instruction;
			size_t length;
			string name = CApi.value_name (CApi.called_value (call), out length);
			if (name == "free" && CApi.argument_count (call) == 1 && (void*) CApi.is_constant_pointer_null (CApi.operand (call, 0)) == null) {
				var argument = CApi.operand (call, 0);
				CApi.set_operand (call, 0, CApi.const_null (CApi.type_of (argument)));
				ordinary (artifact);
				refused ("changed root/wrapper retirement", () => artifact.verify ());
				CApi.set_operand (call, 0, argument);
				artifact.verify ();
				retirements++;
			}
			if (CApi.instruction_call_conv (call) == LlvmLowering.CALL_CONVENTION) {
				CApi.set_instruction_call_conv (call, CApi.CallConv.C);
				ordinary (artifact);
				refused ("changed native role convention", () => artifact.verify ());
				CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
				artifact.verify ();
				calls++;
			}
		}
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					if (CApi.opcode (instruction) != CApi.Opcode.ICMP || !CApi.value_name (instruction, out length).has_prefix ("foreign.wrong.thread")) {
						continue;
					}
					assert (CApi.predicate (instruction) == CApi.IntPredicate.NE);
					var original = CApi.operand (instruction, 0);
					var other = CApi.operand (instruction, 1);
					assert ((void*) original != (void*) other);
					CApi.set_operand (instruction, 0, other);
					ordinary (artifact);
					refused ("bypassed foreign thread guard", () => artifact.verify ());
					CApi.set_operand (instruction, 0, original);
					artifact.verify ();
					guards++;
				}
			}
		}
		assert (calls > 0 && guards > 0 && retirements > 0);
		Test.message ("%d native calls, %d thread guards and %d retirements changed, rejected and restored", calls, guards, retirements);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void c_bool_authority() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("c-bool-proof.astra", "[CImport(name=\"bool14\",bool_abi=\"c99\")]bool receive(bool value);[CExport(name=\"bool14_out\",bool_abi=\"c99\")]bool send(bool value){return receive(value);}"));
		assert (parsed.diagnostic == null);
		var analysis = SemanticAnalyzer.analyze (parsed.unit);
		assert (analysis.diagnostic == null);
		CheckedProgram? checked = analysis.program;
		analysis = null;
		checked.c_functions[0].metadata.bool_abi = Astra.Foreign.CBoolAbi.NONE;
		refused ("checked lost C99 import policy", () => { CoreBuilder.build (checked);
		});
		checked.c_functions[0].metadata.bool_abi = Astra.Foreign.CBoolAbi.C99;
		checked.c_exports[0].bool_abi = Astra.Foreign.CBoolAbi.NONE;
		refused ("checked lost C99 export policy", () => { CoreBuilder.build (checked);
		});
		checked.c_exports[0].bool_abi = Astra.Foreign.CBoolAbi.C99;
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		core.c_functions[0].metadata.bool_abi = Astra.Foreign.CBoolAbi.NONE;
		refused ("Core bool relabeled unannotated", () => CoreVerifier.verify (core));
		core.c_functions[0].metadata.bool_abi = Astra.Foreign.CBoolAbi.C99;
		CoreVerifier.verify (core);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		cfg.c_exports[0].bool_abi = Astra.Foreign.CBoolAbi.NONE;
		refused ("CFG bool export policy loss", () => CfgVerifier.verify (cfg));
		cfg.c_exports[0].bool_abi = Astra.Foreign.CBoolAbi.C99;
		CfgVerifier.verify (cfg);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		ssa.c_functions[0].metadata.bool_abi = Astra.Foreign.CBoolAbi.NONE;
		refused ("SSA bool import policy loss", () => SsaVerifier.verify (ssa));
		ssa.c_functions[0].metadata.bool_abi = Astra.Foreign.CBoolAbi.C99;
		SsaVerifier.verify (ssa);
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		assert (native.c_bool_policies.length == 2);
		string identity = native.c_bool_policies[1];
		native.c_bool_policies.remove_index (1);
		refused ("native C99 boundary inventory loss", () => NativeAbiVerifier.verify (native));
		native.c_bool_policies.add (identity);
		NativeAbiVerifier.verify (native);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		cabi.functions[0].metadata.bool_abi = Astra.Foreign.CBoolAbi.NONE;
		refused ("C ABI CBOOL without policy", () => CAbiVerifier.verify (cabi));
		cabi.functions[0].metadata.bool_abi = Astra.Foreign.CBoolAbi.C99;
		CAbiVerifier.verify (cabi);
		refused ("C99 relabeled Windows", () => { LlvmLowering.lower (ssa, native, cabi, null, null, false, false, null, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		});
		var upstream = WeakRef (ssa.c_functions[0]);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		ssa = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		new LlvmTargetMachineArtifact ().configure (artifact);
		artifact.verify ();
		ordinary (artifact);
		uint kind = CApi.enum_attribute_kind ("zeroext", 7);
		int changed = 0;
		foreach (string name in new string[] { "bool14", "bool14_out" }) {
			var function = CApi.named_function (artifact.module, name);
			foreach (uint index in new uint[] { 0, 1 }) {
				CApi.remove_enum_attribute (function, index, kind);
				ordinary (artifact);
				refused ("ordinary-valid lost C bool declaration/wrapper zeroext", () => artifact.verify ());
				CApi.add_attribute (function, index, CApi.create_enum_attribute (artifact.context, kind, 0));
				artifact.verify ();
				changed++;
			}
		}
		foreach (var handle in artifact.c_imports[0].calls) {
			var call = (CApi.ValueRef) handle;
			foreach (uint index in new uint[] { 0, 1 }) {
				CApi.remove_call_enum_attribute (call, index, kind);
				ordinary (artifact);
				refused ("ordinary-valid lost C bool call-site zeroext", () => artifact.verify ());
				CApi.add_call_attribute (call, index, CApi.create_enum_attribute (artifact.context, kind, 0));
				artifact.verify ();
				changed++;
			}
		}
		assert (changed == 6);
		artifact.requires_c_bool = false;
		refused ("lost physical C99 target requirement", () => artifact.verify ());
		artifact.requires_c_bool = true;
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/foreign-class/stage-authority-and-graph-release", stage_authority);
	Test.add_func ("/foreign-class/ordinary-LLVM-valid-mutations-restoration", physical_authority);
	Test.add_func ("/foreign-class/com-iid-vtable-lifetime-context-authority", com_authority);
	Test.add_func ("/foreign-class/c-int-pointer-role-and-exact-out-place", scalar_pointer_authority);
	Test.add_func ("/foreign-class/com-import-exact-identity-ownership-context-graphs", imported_com_authority);
	Test.add_func ("/foreign-class/gobject-native-owner-cache-floating-affinity-identity", gobject_authority);
	Test.add_func ("/foreign-class/gobject-import-origin-all-stages-restored", gobject_import_origin);
	Test.add_func ("/foreign-class/c-union-active-member-tag-all-stages-restored", union_authority);
	Test.add_func ("/foreign-class/c99-bool-policy-zeroext-target-restored-graphs", c_bool_authority);
	return Test.run ();
}
}
