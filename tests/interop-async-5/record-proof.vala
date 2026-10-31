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
namespace Astra.Tests.CRecordValues {
private CheckedProgram source() {
	string text = "struct R { i64 count; f64 total; i64 tag; }"
	    + "[CCode(record_abi=\"value-lp64\")]extern(C) R echo(R value);"
	    + "[CCode(record_abi=\"value-lp64\")]export(C) R wrapped(R value){R result=echo(value);return result;}"
	    + "int main(){return 0;}";
	var syntax = Parser.parse (new SourceFile.from_text ("record-proof", text));
	if (syntax.diagnostic != null) {
		GLib.error ("%s", syntax.diagnostic.message);
	}
	var checked = SemanticAnalyzer.analyze (syntax.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.message);
	}
	return checked.program;
}
private bool core_rejects(CoreProgram program) {
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		return true;
	}
	return false;
}
private bool cfg_rejects(CfgProgram program) {
	try {
		CfgVerifier.verify (program);
	} catch (CfgError error) {
		return true;
	}
	return false;
}
private bool ssa_rejects(SsaProgram program) {
	try {
		SsaVerifier.verify (program);
	} catch (SsaError error) {
		return true;
	}
	return false;
}
private bool cabi_rejects(CAbiProgram program) {
	try {
		CAbiVerifier.verify (program);
	} catch (CAbiError error) {
		return true;
	}
	return false;
}
private bool llvm_rejects(LlvmModuleArtifact artifact) {
	try {
		artifact.verify ();
	} catch (LlvmError error) {
		return true;
	}
	return false;
}
private void core_contract() {
	try {
		var program = CoreBuilder.build(source());
		CoreVerifier.verify(program);
		CoreCStructCallResult? call = null;
		foreach (var f in program.functions) {
			foreach (var statement in f.body.statements) {
				var initialize = statement as CoreStructResultStore;
				if (initialize != null && initialize.producer is CoreCStructCallResult) {
					call = (CoreCStructCallResult)initialize.producer;
				}
			}
		}
		// Field-copy initializer may own its producer in a declaration group.
		if (call == null) {
			var imported = program.c_functions[0];
			program.c_functions[0] = new CoreCFunction(imported.span, imported.name_span, imported.name, new Astra.Foreign.CForeignMetadata(imported.external_symbol), imported.abi, imported.return_type, imported.parameter_types, imported.ordinal, null, imported.parameters);
			assert(core_rejects(program));
			program.c_functions[0] = imported;
			CoreVerifier.verify(program);
		} else {
			var argument = call.arguments[0];
			call.arguments.remove_index(0);
			assert(core_rejects(program));
			call.arguments.add(argument);
			CoreVerifier.verify(program);
		}
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
private void cfg_contract() {
	try {
		var program = CfgBuilder.build(CoreBuilder.build(source()));
		CfgVerifier.verify(program);
		CfgCCallInstruction? call = null;
		foreach (var f in program.functions) {
			foreach (var b in f.blocks) {
				foreach (var i in b.instructions) {
					if (i is CfgCCallInstruction) {
						call = (CfgCCallInstruction)i;
					}
				}
			}
		}
		assert(call != null);
		var group = call.struct_arguments[0];
		call.struct_arguments[0] = new StructBoundaryGroup(group.source_ordinal + 1, group.first_leaf, group.shape);
		assert(cfg_rejects(program));
		call.struct_arguments[0] = group;
		CfgVerifier.verify(program);
		var leaf = call.struct_result.leaves[0];
		call.struct_result.leaves.remove_index(0);
		assert(cfg_rejects(program));
		call.struct_result.leaves.insert(0, leaf);
		CfgVerifier.verify(program);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
private void ssa_contract() {
	try {
		var program = SsaBuilder.build(CfgBuilder.build(CoreBuilder.build(source())));
		SsaVerifier.verify(program);
		SsaCCallInstruction? call = null;
		foreach (var f in program.functions) {
			foreach (var b in f.blocks) {
				foreach (var i in b.instructions) {
					if (i is SsaCCallInstruction) {
						call = (SsaCCallInstruction)i;
					}
				}
			}
		}
		assert(call != null);
		var group = call.struct_arguments[0];
		call.struct_arguments[0] = new StructBoundaryGroup(group.source_ordinal, group.first_leaf + 1, group.shape);
		assert(ssa_rejects(program));
		call.struct_arguments[0] = group;
		SsaVerifier.verify(program);
		var leaf = call.struct_result.leaves[0];
		call.struct_result.leaves[0] = call.struct_result.leaves[1];
		assert(ssa_rejects(program));
		call.struct_result.leaves[0] = leaf;
		SsaVerifier.verify(program);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
private void cabi_contract() {
	try {
		var ssa = SsaBuilder.build(CfgBuilder.build(CoreBuilder.build(source())));
		var nabi = NativeAbiBuilder.build(ssa);
		var cabi = CAbiBuilder.build(ssa, nabi);
		CAbiVerifier.verify(cabi);
		var record = cabi.functions[0].signature.result.record;
		assert(record.by_value && record.memory && record.size == 24 && record.alignment == 8);
		var field = record.fields[1];
		record.fields[1] = new CAbiRecordField(field.name, field.scalar_name, field.offset + 1);
		assert(cabi_rejects(cabi));
		record.fields[1] = field;
		CAbiVerifier.verify(cabi);
		// Exact scalar identity is checked against source independently of layout.
		var map = new HashTable<SsaCFunction, CAbiFunction>(direct_hash, direct_equal);
		map.insert(ssa.c_functions[0], cabi.functions[0]);
		var parameter = cabi.functions[0].signature.parameters[0].record;
		var original = parameter.fields[1];
		parameter.fields[1] = new CAbiRecordField(original.name, "i64", original.offset);
		CAbiVerifier.verify(cabi);
		bool rejected = false;
		try{
			CAbiValidator.validate_ssa_calls(ssa, cabi, map);
		} catch (CAbiError error) {
			rejected = true;
		}
		assert(rejected);
		parameter.fields[1] = original;
		CAbiValidator.validate_ssa_calls(ssa, cabi, map);
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
private void llvm_contract() {
	try {
		var ssa = SsaBuilder.build(CfgBuilder.build(CoreBuilder.build(source())));
		var nabi = NativeAbiBuilder.build(ssa);
		var cabi = CAbiBuilder.build(ssa, nabi);
		var artifact = LlvmLowering.lower(ssa, nabi, cabi);
		artifact.verify();
		var imported = artifact.c_imports[0];
		var byval = CApi.enum_attribute_kind("byval", 5);
		CApi.remove_enum_attribute(imported.value, 2, byval);
		assert(llvm_rejects(artifact));
		var mapper = new LlvmCTypeMapper(artifact.context);
		mapper.attributes(cabi.functions[0].signature, imported.value);
		artifact.verify();
		var exported = artifact.c_exports[0];
		var sret = CApi.enum_attribute_kind("sret", 4);
		CApi.remove_enum_attribute(exported.value, 1, sret);
		assert(llvm_rejects(artifact));
		mapper.attributes(cabi.exports[0].signature, exported.value);
		artifact.verify();
		var first = CApi.operand(exported.call, 0);
		CApi.set_operand(exported.call, 0, CApi.const_int(CApi.int_type_in_context(artifact.context, 64), 777, 0));
		assert(llvm_rejects(artifact));
		CApi.set_operand(exported.call, 0, first);
		artifact.verify();
	} catch (GLib.Error error) {
		GLib.error("%s", error.message);
	}
}
int main(string[] args) {
	Test.init(ref args);
	Test.add_func("/record-value/core", core_contract);
	Test.add_func("/record-value/cfg", cfg_contract);
	Test.add_func("/record-value/ssa", ssa_contract);
	Test.add_func("/record-value/cabi", cabi_contract);
	Test.add_func("/record-value/llvm", llvm_contract);
	return Test.run();
}
}
