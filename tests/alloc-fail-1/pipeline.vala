// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.AllocationFailure {
private void lifetimes() {
	try {
		ParseResult? syntax = Parser.parse (new SourceFile.from_text ("allocation-action.astra", SOURCE));
		var ast = WeakRef (syntax.unit);
		var analyzed = SemanticAnalyzer.analyze (syntax.unit);
		syntax = null;
		assert (ast.get () == null && analyzed.diagnostic == null);
		CheckedProgram? checked = analyzed.program;
		analyzed = null;
		var definition = WeakRef (checked.generic_functions[0]);
		var universe = WeakRef (checked.types);
		var allocation = (CheckedOwnedBufferAllocate) ((CheckedOwnershipReturn) checked.generic_functions[0].body.statements[0]).producer;
		var call = WeakRef (allocation.failure_call);
		var argument = WeakRef (allocation.failure_call.arguments[0]);
		CoreProgram? parameterized = CoreBuilder.build (checked);
		allocation.failure_call.arguments.remove_range (0, allocation.failure_call.arguments.length);
		allocation = null;
		checked = null;
		assert (definition.get () == null && universe.get () == null && call.get () == null && argument.get () == null);
		CoreVerifier.verify (parameterized);
		var generic = WeakRef (parameterized.generic_functions[0]);
		var structure = WeakRef (parameterized.generic_structs[0]);
		CoreProgram? core = CoreGenericMonomorphizer.build (parameterized);
		parameterized = null;
		assert (generic.get () == null && structure.get () == null);
		CoreVerifier.verify_concrete (core);
		var core_graph = WeakRef (core);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_graph.get () == null);
		CfgVerifier.verify (cfg);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		var cfg_graph = WeakRef (cfg);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_graph.get () == null);
		SsaVerifier.verify (ssa);
		int instances = 0;
		foreach (var function in ssa.functions) {
			if (function.name.has_prefix ("astra.gen.")) {
				instances++;
			}
		}
		assert (instances == 1);
		var ssa_graph = WeakRef (ssa);
		var type = WeakRef (ssa.structs[0].semantic_type);
		var source = WeakRef (ssa.span.file);
		var native = NativeAbiBuilder.build (ssa);
		var foreign = CAbiBuilder.build (ssa, native);
		ssa = null;
		assert (ssa_graph.get () == null && type.get () == null);
		NativeAbiVerifier.verify (native);
		CAbiVerifier.verify (foreign);
		// Spans are legitimate immutable leaves, not executable predecessors.
		assert (source.get () != null);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void correspondence() {
	try {
		var ssa = build ("struct A{int x;}struct B{int x;}void report(A[] a){}owned A[] make(A[] a,int n){return new A[n] else report(a);}void unused(B[] b){}");
		var native = NativeAbiBuilder.build (ssa);
		var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		for (int i = 0; i < ssa.functions.length; i++) {
			map.insert (ssa.functions[i], native.functions[i]);
		}
		NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		var signature = native.functions[0].signature;
		var parameter = signature.parameters[0];
		signature.parameters[0] = new NativeParameter.typed (parameter.span, parameter.name_span, parameter.name, parameter.ordinal, new NativeRecordSliceType (native.record_elements[1]));
		NativeAbiVerifier.verify (native);
		bool rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		// Independently remove required receiver provenance after valid lowering.
		var text = "void report(int n){}class C{owned int[] a;init(){this.a=new int[2] else report(2);}}void root(){var c=C.init();}";
		var cfg = CfgBuilder.build (CoreBuilder.build (check (text)));
		bool found = false;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				var request = block.terminator as CfgBufferAllocationBranch;
				if (request != null) {
					assert (request.allocation.failure.captured_receiver != null);
					request.allocation.failure.captured_receiver = null;
					found = true;
				}
			}
		}
		assert (found);
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		ssa = build (text);
		found = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				var request = block.terminator as SsaBufferAllocationBranch;
				if (request != null) {
					assert (request.allocation.failure.captured_receiver != null);
					request.allocation.failure.captured_receiver = null;
					found = true;
				}
			}
		}
		assert (found);
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		// Relocate actual old-owner cleanup before the action, not a dummy
		// malformed free. Structural region proof must reject it independently.
		text = "void report(int n){}void replace(owned int[] old,int n){old=new int[n] else report(len(old));}";
		cfg = CfgBuilder.build (CoreBuilder.build (check (text)));
		found = false;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				var request = block.terminator as CfgBufferAllocationBranch;
				if (request == null) {
					continue;
				}
				var success = request.success_target;
				for (int i = 0; i < success.instructions.length; i++) {
					if (success.instructions[i] is CfgOwnershipRearmInstruction) {
						var rearm = (CfgOwnershipRearmInstruction) success.instructions[i];
						request.failure_target.instructions.insert (0, new CfgCleanupInstruction (rearm.span, new CfgLoadValue (rearm.span, rearm.owner), rearm.cleanup));
						found = true;
						break;
					}
				}
			}
		}
		assert (found);
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		ssa = build (text);
		found = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				var request = block.terminator as SsaBufferAllocationBranch;
				if (request == null) {
					continue;
				}
				var success = request.success_edge.target;
				for (int i = 0; i < success.instructions.length; i++) {
					var cleanup = success.instructions[i] as SsaBufferDeallocateInstruction;
					if (cleanup != null) {
						success.instructions.remove_index (i);
						request.failure_edge.target.instructions.insert (0, cleanup);
						found = true;
						break;
					}
				}
			}
		}
		assert (found);
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/alloc-fail/pipeline/predecessor-destruction-and-dedup", lifetimes);
	Test.add_func ("/alloc-fail/pipeline/independent-abi-and-capture-correspondence", correspondence);
	return Test.run ();
}

}
