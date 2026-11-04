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

namespace Astra.Tests.AllocationProof {
private const string PROGRAM = "[Repr(layout=\"C\")][Align(bytes=\"8\")] struct Pair{u8 tag;i64 wide;} [Allocator(kind=\"pool\",domain=\"proof.pool\",capacity=\"128\",blocks=\"2\")][Align(bytes=\"64\")] class Cell{int value;init(int value){this.value=value;}deinit(){this.value=0;}} int main(){Pair pair={tag=7,wide=4294967300};var cell=try_new Cell(42);if(cell==null){return 1;}Cell local=Cell.init(1);if(pair.tag!=7 || pair.wide!=4294967300){return 2;}return cell.value+local.value-1;}";
private CheckedProgram check() {
	var syntax = Parser.parse (new SourceFile.from_text ("allocation-proof", PROGRAM));
	assert (syntax.diagnostic == null);
	var result = SemanticAnalyzer.analyze (syntax.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void checked_contract() {
	try {
		var source = check ();
		bool rejected = false;
		source.classes[0].allocation_policy.capacity = 256;
		try {
			CoreBuilder.build (source);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		source.classes[0].allocation_policy.capacity = 128;
		source.structs[0].representation.minimum_alignment = 4;
		rejected = false;
		try {
			CoreBuilder.build (source);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		source.structs[0].representation.minimum_alignment = 8;
		CoreVerifier.verify (CoreBuilder.build (source));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void core_contract() {
	try {
		CheckedProgram? source = check ();
		var upstream = WeakRef (source.classes[0]);
		var program = CoreBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		program.classes[0].allocation_policy.alignment = 1;
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		program.classes[0].allocation_policy.alignment = 64;
		program.structs[0].representation.field_types[0] = "u16";
		rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		program.structs[0].representation.field_types[0] = "u8";
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_contract() {
	try {
		CoreProgram? source = CoreBuilder.build (check ());
		var upstream = WeakRef (source.classes[0]);
		var program = CfgBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		program.classes[0].allocation_policy.kind = AllocationKind.REGION;
		bool rejected = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		program.classes[0].allocation_policy.kind = AllocationKind.POOL;
		program.structs[0].representation.minimum_alignment = 4;
		rejected = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		program.structs[0].representation.minimum_alignment = 8;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private SsaProgram ssa() throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check ())));
}

private void ssa_contract() {
	try {
		CfgProgram? source = CfgBuilder.build (CoreBuilder.build (check ()));
		var upstream = WeakRef (source.classes[0]);
		var program = SsaBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		program.classes[0].allocation_policy.blocks = 1;
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		program.classes[0].allocation_policy.blocks = 2;
		assert (program.structs.length == 1 && program.structs[0].representation != null);
		program.structs[0].representation.field_types[1] = "u64";
		rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		program.structs[0].representation.field_types[1] = "i64";
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_contract() {
	try {
		SsaProgram? source = ssa ();
		var upstream = WeakRef (source.classes[0]);
		var program = NativeAbiBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		program.classes[0].allocation_policy.capacity = 256;
		bool rejected = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		program.classes[0].allocation_policy.capacity = 128;
		program.pod_layouts[0].minimum_alignment = 4;
		rejected = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		program.pod_layouts[0].minimum_alignment = 8;
		var site = program.functions[0].allocation_sites[0];
		site.fallible = false;
		rejected = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		site.fallible = true;
		NativeAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private LlvmModuleArtifact artifact() throws GLib.Error {
	SsaProgram? source = ssa ();
	var upstream = WeakRef (source.classes[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (source);
	CAbiProgram? cabi = CAbiBuilder.build (source, native);
	var result = LlvmLowering.lower (source, native, cabi);
	source = null;
	native = null;
	cabi = null;
	assert (upstream.get () == null);
	return result;
}

private void reject_llvm(LlvmModuleArtifact program) {
	bool rejected = false;
	try {
		program.verify ();
	} catch (LlvmError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}

private void llvm_contract() {
	try {
		var program = artifact ();
		program.verify ();
		assert (program.allocation_globals.length == 3 && program.pod_layouts.length == 1);
		var backing = program.allocation_globals[0].value;
		CApi.set_alignment (backing, 1);
		reject_llvm (program);
		CApi.set_alignment (backing, 4096);
		program.verify ();
		var target = CApi.named_function (program.module, "astra_alloc12_allocate");
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		for (var function = CApi.first_function (program.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) target) {
						allocation = instruction;
					}
				}
			}
		}
		assert ((void*) allocation != null);
		foreach (uint operand in new uint[] { 0, 2, 3, 4 }) {
			var original = CApi.operand (allocation, operand);
			CApi.set_operand (allocation, operand, CApi.const_null (CApi.type_of (original)));
			reject_llvm (program);
			CApi.set_operand (allocation, operand, original);
			program.verify ();
		}
		// The complete fallible construction path is independently sealed.
		var function = CApi.named_function (program.module, "astra.fn.0");
		bool changed = false;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			var branch = CApi.block_terminator (block);
			if ((void*) branch != null && CApi.opcode (branch) == CApi.Opcode.COND_BR && CApi.operand_count (branch) == 3) {
				var original = CApi.operand (branch, 0);
				CApi.set_operand (branch, 0, CApi.const_int (CApi.type_of (original), 1, 0));
				reject_llvm (program);
				CApi.set_operand (branch, 0, original);
				program.verify ();
				changed = true;
				break;
			}
		}
		assert (changed);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/allocation/checked-policy-and-pod", checked_contract);
	Test.add_func ("/allocation/core-detached", core_contract);
	Test.add_func ("/allocation/cfg-detached", cfg_contract);
	Test.add_func ("/allocation/ssa-detached", ssa_contract);
	Test.add_func ("/allocation/native-detached", native_contract);
	Test.add_func ("/allocation/llvm-detached", llvm_contract);
	return Test.run ();
}

}
