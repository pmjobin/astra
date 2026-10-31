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

namespace Astra.Tests.ConcurrentAtomics {
[CCode (cheader_filename = "llvm-c/Core.h", cname = "LLVMSetCmpXchgFailureOrdering")]
private static extern void failure_order(CApi.ValueRef instruction, int ordering);
[CCode (cheader_filename = "llvm-c/Core.h", cname = "LLVMSetAtomicSingleThread")]
private static extern void single_thread(CApi.ValueRef instruction, int enabled);
[CCode (cheader_filename = "llvm-c/Core.h", cname = "LLVMSetWeak")]
private static extern void weak_cas(CApi.ValueRef instruction, int enabled);

private void atomics() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("atomic-contract",
			"class P{init(){}} int main(){var p=new P();var s=shared_acquire(move p);var w=shared_downgrade(s);var t=weak_upgrade(w);return 0;}"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		artifact.verify ();
		int loads = 0;
		int stores = 0;
		int exchanges = 0;
		foreach (var binding in artifact.shared_atomics) {
			var instruction = binding.instruction;
			bool rejected = false;
			CApi.set_alignment (instruction, 4);
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
			}
			assert (rejected);
			CApi.set_alignment (instruction, 8);
			artifact.verify ();

			if (CApi.opcode (instruction) == CApi.Opcode.ATOMIC_CMP_XCHG) {
				failure_order (instruction, 2);
				rejected = false;
				try {
					artifact.verify ();
				} catch (LlvmError error) {
					rejected = true;
				}
				assert (rejected);
				failure_order (instruction, 4);
				artifact.verify ();
				weak_cas (instruction, 1);
				rejected = false;
				try {
					artifact.verify ();
				} catch (LlvmError error) {
					rejected = true;
				}
				assert (rejected);
				weak_cas (instruction, 0);
				artifact.verify ();
				single_thread (instruction, 1);
				rejected = false;
				try {
					artifact.verify ();
				} catch (LlvmError error) {
					rejected = true;
				}
				assert (rejected);
				single_thread (instruction, 0);
				artifact.verify ();
				exchanges++;
			} else {
				int ordering = (int) CApi.get_ordering (instruction);
				CApi.set_ordering (instruction, 0);
				rejected = false;
				try {
					artifact.verify ();
				} catch (LlvmError error) {
					rejected = true;
				}
				assert (rejected);
				CApi.set_ordering (instruction, ordering);
				artifact.verify ();
				if (CApi.opcode (instruction) == CApi.Opcode.LOAD) {
					loads++;
				} else {
					stores++;
				}
			}
		}
		assert (loads > 0 && stores == 2 && exchanges >= 4);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/concurrency/atomic-order-scope-alignment-and-restore", atomics);
	return Test.run ();
}
}
