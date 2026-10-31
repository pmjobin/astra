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

namespace Astra.Tests.Ownership {
private string cleanup_names(CfgBlock block) {
	var names = new StringBuilder ();
	foreach (var instruction in block.instructions) {
		var cleanup = instruction as CfgCleanupInstruction;
		if (cleanup != null) {
			names.append (((CfgLocalPlace) ((CfgLoadValue) cleanup.value).source).name);
		}
	}
	return names.str;
}
private void model() throws GLib.Error {
	var program = check (BASIC);
	var declaration = (CheckedOwnedLocalDeclaration) program.functions[0].body.statements[0];
	assert (declaration.local == program.functions[0].locals[0] && declaration.local.semantic_type == program.types.raw_pointer_type);
	assert (declaration.lexical_region == program.functions[0].body.region);
	assert (declaration.owned_initializer.ownership_kind == OwnershipKind.OWNED && declaration.owned_initializer.semantic_type.is_void_pointer ());
	assert (declaration.cleanup == program.c_functions[0].metadata.owned_result.cleanup);
	assert (SemanticDump.format (program).contains ("-> owned void*"));
	var core = CoreBuilder.build (program);
	CoreVerifier.verify (core);
	var initialization = (CoreInitialize) core.functions[0].body.statements[0];
	assert (initialization.acquisition == core.functions[0].owned_locals[0]);
	assert (initialization.acquisition.scope == core.functions[0].body && initialization.acquisition.place == initialization.target);
	assert (initialization.acquisition.cleanup == core.cleanups[0] && core.c_functions[0].owned_cleanup == core.cleanups[0]);
	assert (core.c_functions[0].metadata.owned_result == null && initialization.target.is_promotable ());
	assert (CoreDump.format (core).contains ("owned-initialize"));
	var control = CfgBuilder.build (core);
	assert (cleanup_names (control.functions[0].entry) == "h");
	var ssa = SsaBuilder.build (control);
	var instructions = ssa.functions[0].entry.instructions;
	assert (instructions.length == 2 && instructions[0] is SsaCCallInstruction && instructions[1] is SsaCleanupInstruction);
	assert (((SsaCleanupInstruction) instructions[1]).value == instructions[0].result);
	assert (((SsaCleanupInstruction) instructions[1]).cleanup == ssa.cleanups[0] && instructions[1].result == null);
	assert (ssa.functions[0].storage.length == 0 && ssa.functions[0].entry.parameters.length == 0);
	var nabi = NativeAbiBuilder.build (ssa);
	assert (nabi.abi_version == NativeAbiVersion.SCALAR_V0);
	var ordinary = build ("int f() { void* h = raw(); return 7; }");
	assert (NativeAbiDump.format (nabi) == NativeAbiDump.format (NativeAbiBuilder.build (ordinary)));
	var cabi = CAbiBuilder.build (ssa, nabi);
	assert (cabi.profile == CAbiProfile.SCALAR_PTR_V1 && cabi.cleanups.length == 1);
	assert (cabi.functions[0].owned_cleanup == cabi.cleanups[0] && cabi.cleanups[0].signature.result == null);
	assert (cabi.cleanups[0].signature.parameters.length == 1 && cabi.cleanups[0].signature.parameters[0].scalar_type == CAbiScalarType.PTR);
}

private void cleanup_stack(string statements, string expected) throws GLib.Error {
	var program = cfg ("void f() { " + statements + " }");
	assert (cleanup_names (program.functions[0].entry) == expected);
	CfgVerifier.verify (program);
}

private void nested_exits(string transfer) throws GLib.Error {
	string text = "int f() { owned void* a = create(1); while (true) { owned void* b = create(2); if (true) { owned void* c = create(3); " + transfer + " } } return 0; }";
	var program = cfg (text);
	var function = program.functions[0];
	var block = function.blocks[4];
	assert (cleanup_names (block) == (transfer == "return 7;" ? "cba" : "cb"));
	if (transfer == "return 7;") {
		assert (block.terminator is CfgReturn);
	} else {
		assert (((CfgBranch) block.terminator).target == function.blocks[transfer == "break;" ? 3 : 1]);
	}
	var ssa = SsaBuilder.build (program);
	foreach (var ssa_block in ssa.functions[0].blocks) {
		foreach (var parameter in ssa_block.parameters) {
			assert (!parameter.semantic_type.is_void_pointer ());
		}
	}
}

private void branch() throws GLib.Error {
	var program = cfg ("void f(bool condition) { if (condition) { owned void* h = create(1); } }");
	var function = program.functions[0];
	var split = (CfgConditionalBranch) function.entry.terminator;
	assert (cleanup_names (function.blocks[1]) == "h" && cleanup_names (function.blocks[2]) == "");
	assert (split.false_target == function.blocks[2]);
	assert (((CfgBranch) function.blocks[1].terminator).target == function.blocks[2]);
}

private void return_order() throws GLib.Error {
	var program = cfg ("int f(int divisor) { owned void* h = create(1); return effect() / divisor; }");
	var instructions = program.functions[0].entry.instructions;
	assert (instructions[2] is CfgCCallInstruction && instructions[3] is CfgEvaluateInstruction && instructions[4] is CfgCleanupInstruction);
	assert (((CfgEvaluateInstruction) instructions[3]).value is CfgBinaryValue);
	assert (((CfgReturn) program.functions[0].entry.terminator).value == ((CfgEvaluateInstruction) instructions[3]).result);
	var function = SsaBuilder.build (program).functions[0];
	assert (function.entry.instructions[1] is SsaCCallInstruction && function.entry.instructions[2] is SsaBinaryInstruction && function.entry.instructions[3] is SsaCleanupInstruction);
	assert (((SsaReturn) function.entry.terminator).value == function.entry.instructions[2].result);
}

private void unreachable() throws GLib.Error {
	var program = cfg ("int f() { owned void* a = create(1); return 7; owned void* b = create(2); return 8; }");
	var function = program.functions[0];
	assert (function.blocks.length == 2 && cleanup_names (function.entry) == "a" && cleanup_names (function.blocks[1]) == "ba");
	assert (!CfgReachability.analyze (function).is_reachable (function.blocks[1]));
	var ssa = SsaBuilder.build (program).functions[0];
	assert (ssa.blocks.length == 1 && ssa.entry.instructions.length == 2);
}

private void interning() throws GLib.Error {
	var first = VapiParser.parse (new SourceFile.from_text ("a.vapi", "[CCode(destroy_function = \"destroy\")] void* a();"));
	var second = VapiParser.parse (new SourceFile.from_text ("b.vapi", "[CCode(destroy_function = \"destroy\")] void* b();"));
	var inputs = VapiNormalizer.normalize (first.file);
	inputs.add (VapiNormalizer.normalize (second.file)[0]);
	var parsed = Parser.parse (new SourceFile.from_text ("own.astra", "void f() { owned void* a = a(); owned void* b = b(); }"));
	var result = SemanticAnalyzer.analyze (parsed.unit, inputs);
	assert (result.diagnostic == null);
	assert (result.program.c_functions[0].metadata.owned_result.cleanup == result.program.c_functions[1].metadata.owned_result.cleanup);
	var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (result.program)));
	assert (ssa.cleanups.length == 1 && ssa.c_functions[0].owned_cleanup == ssa.c_functions[1].owned_cleanup);
	var cabi = CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa));
	assert (cabi.cleanups.length == 1 && cabi.functions[0].owned_cleanup == cabi.functions[1].owned_cleanup);
}

private void acquisition_order() throws GLib.Error {
	var core = CoreBuilder.build (check ("void f() { owned void* a = create(1); owned void* b = create(2); }"));
	var statements = core.functions[0].body.statements;
	var first = statements[0];
	statements[0] = statements[1];
	statements[1] = first;
	// Static declaration ordinals remain a,b; successful execution is b,a.
	assert (cleanup_names (CfgBuilder.build (core).functions[0].entry) == "ab");
}

private void distinct_contracts() throws GLib.Error {
	var ssa = build ("void f() { owned void* a = create(1); owned void* b = second(); }", VAPI + "[CCode(cname = \"second_impl\", destroy_function = \"second_destroy\")] void* second();");
	assert (ssa.cleanups.length == 2 && ssa.cleanups[0] != ssa.cleanups[1]);
	var instructions = ssa.functions[0].entry.instructions;
	assert (((SsaCleanupInstruction) instructions[2]).cleanup == ssa.cleanups[1]);
	assert (((SsaCleanupInstruction) instructions[3]).cleanup == ssa.cleanups[0]);
	var cabi = CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa));
	assert (cabi.cleanups.length == 2 && cabi.functions[4].owned_cleanup == cabi.cleanups[1]);
	assert (cabi.cleanups[1].external_symbol == "second_destroy");
}

private void collision(bool exported) throws GLib.Error {
	var ssa = build (exported ? "export(C) void resource_destroy_impl(void* p) {}" : "extern(C) void resource_destroy_impl(void* p);");
	try {
		CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa));
		assert_not_reached ();
	} catch (CAbiError.DUPLICATE_SYMBOL error) {
		assert (error.message.contains ("resource_destroy_impl"));
	}
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/own/model-promotion-abi", model);
	add ("/own/acquisition-execution-order", acquisition_order);
	add ("/own/distinct-contracts", distinct_contracts);
	add ("/own/stack/fallthrough", () => cleanup_stack ("owned void* a = create(1); owned void* b = create(2);", "ba"));
	add ("/own/stack/return", () => cleanup_stack ("owned void* a = create(1); owned void* b = create(2); return;", "ba"));
	add ("/own/stack/nested-return", () => nested_exits ("return 7;"));
	add ("/own/stack/break", () => nested_exits ("break;"));
	add ("/own/stack/continue", () => nested_exits ("continue;"));
	add ("/own/stack/branch-join", branch);
	add ("/own/return-order", return_order);
	add ("/own/unreachable", unreachable);
	add ("/own/interning-across-files", interning);
	add ("/own/collision/import", () => collision (false));
	add ("/own/collision/export", () => collision (true));
	register_diagnostics ();
	register_lifetime ();
	foreach (string name in new string[] {"basic", "null", "lifo", "nested", "return", "early-return", "branch", "branch-both", "loop", "continue", "break", "loop-return", "shortcircuit", "mixed", "unreachable", "nested-loop", "fallthrough", "trap", "null-trap"}) {
		add ("/own/pipeline/" + name, () => {
				var ssa = build (read ("own-" + name + ".astra"), read ("owned-resource.vapi"));
				SsaVerifier.verify (ssa);
				CAbiVerifier.verify (CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa)));
				assert (SsaDump.format (ssa) == SsaDump.format (build (read ("own-" + name + ".astra"), read ("owned-resource.vapi"))));
			});
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
