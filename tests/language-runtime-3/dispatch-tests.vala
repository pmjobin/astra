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

namespace Astra.Tests.NativeInterfaces {
private CoreProgram source() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("dispatch-mutation", "interface Read{int read(int n);int tag(int n);}class Add:Read{int offset;init(int n):base(){this.offset=n;}override int read(int n){return n+this.offset;}override int tag(int n){return n+100;}}int inspect(Read r){return r.read(7)+r.tag(1);}int main(){var x=new Add(3);return inspect(x);}"));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.message);
	}
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.message);
	}
	return CoreBuilder.build (checked.program);
}

private void slot_identity() {
	try {
		var core = source ();
		CoreVerifier.verify (core);
		var saved = core.classes[1].virtual_entries[0];
		core.classes[1].virtual_entries[0] = core.classes[1].virtual_entries[1];
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Core: %s", error.message);
		}
		assert (rejected);
		core.classes[1].virtual_entries[0] = saved;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		var cfg_saved = cfg.classes[1].virtual_entries[0];
		cfg.classes[1].virtual_entries[0] = cfg.classes[0].virtual_entries[0];
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
			Test.message ("CFG: %s", error.message);
		}
		assert (rejected);
		cfg.classes[1].virtual_entries[0] = cfg_saved;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		var ssa_saved = ssa.classes[1].virtual_entries[0];
		ssa.classes[1].virtual_entries[0] = ssa.classes[1].virtual_entries[1];
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("SSA: %s", error.message);
		}
		assert (rejected);
		ssa.classes[1].virtual_entries[0] = ssa_saved;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		NativeAbiVerifier.verify (native);
		int native_saved = native.classes[1].virtual_targets[0];
		native.classes[1].virtual_targets[0] = native.classes[1].virtual_targets[1];
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native selector: %s", error.message);
		}
		assert (rejected);
		native.classes[1].virtual_targets[0] = native.classes[0].virtual_targets[0];
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native abstract: %s", error.message);
		}
		assert (rejected);
		native.classes[1].virtual_targets[0] = native_saved;
		NativeAbiVerifier.verify (native);
		var root = native.classes[0];
		native.classes[0] = new NativeClassPlan (root.span, root.name, root.ordinal, root.parent_ordinal, root.destructor_ordinal, root.polymorphic, root.exception_root, root.fields, root.virtual_targets);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native nominal: %s", error.message);
		}
		assert (rejected);
		native.classes[0] = root;
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		artifact.verify ();
		int mutations = 0;
		foreach (var binding in artifact.class_addresses) {
			var instruction = binding.instruction;
			if ((void*) CApi.is_instruction (instruction) == null) {
				continue;
			}
			int last = CApi.operand_count (instruction) - 1;
			if (last != 1) {
				continue;
			}
			var selected = CApi.operand (instruction, last);
			if ((void*) CApi.is_constant_int (selected) == null) {
				continue;
			}
			uint64 index = CApi.const_int_zext (selected);
			CApi.set_operand (instruction, last, CApi.const_int (CApi.type_of (selected), index == 0 ? 1 : 0, 0));
			rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM: %s", error.message);
			}
			assert (rejected);
			CApi.set_operand (instruction, last, selected);
			artifact.verify ();
			mutations++;
		}
		assert (mutations > 0);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/native-interface/exact-slot-and-abstract-metadata", slot_identity);
	return Test.run ();
}

}
