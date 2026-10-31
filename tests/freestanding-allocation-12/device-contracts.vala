// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Foreign;
using Astra.Backend.LLVM;

namespace Astra.Tests.PcDeviceProof {
private const string PROGRAM = "[CCode(device=\"pc-edu-read32\")] extern(C) int reg(); [CCode(device=\"pc-atomic-add-seq-cst\")] extern(C) int add(int v); [CCode(device=\"pc-uart-tx8\")] extern(C) int put(int v); export(C) int astra_entry(int a,int b,int c){int v=reg();add(3);put(65);return v;}";

private CheckedProgram check() {
	var syntax = Parser.parse (new SourceFile.from_text ("pc-device-contract", PROGRAM));
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
		var contract = source.c_functions[0].metadata.device;
		contract.operation = PcDeviceOperation.ATOMIC_LOAD_RELAXED;
		bool rejected = false;
		try {
			CoreBuilder.build (source);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		contract.operation = PcDeviceOperation.EDU_READ32;
		CoreVerifier.verify (CoreBuilder.build (source));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void core_contract() {
	try {
		CheckedProgram? source = check ();
		var upstream = WeakRef (source.c_functions[0]);
		var program = CoreBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		var contract = program.c_functions[0].metadata.device;
		contract.operation = PcDeviceOperation.ATOMIC_LOAD_RELAXED;
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		contract.operation = PcDeviceOperation.EDU_READ32;
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void cfg_contract() {
	try {
		CoreProgram? source = CoreBuilder.build (check ());
		var upstream = WeakRef (source.c_functions[0]);
		var program = CfgBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		var contract = program.c_functions[0].metadata.device;
		contract.operation = PcDeviceOperation.ATOMIC_LOAD_RELAXED;
		bool rejected = false;
		try {
			CfgVerifier.verify (program);
		} catch (CfgError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		contract.operation = PcDeviceOperation.EDU_READ32;
		CfgVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void ssa_contract() {
	try {
		CfgProgram? source = CfgBuilder.build (CoreBuilder.build (check ()));
		var upstream = WeakRef (source.c_functions[0]);
		var program = SsaBuilder.build (source);
		source = null;
		assert (upstream.get () == null);
		var contract = program.c_functions[0].metadata.device;
		contract.operation = PcDeviceOperation.ATOMIC_LOAD_RELAXED;
		bool rejected = false;
		try {
			SsaVerifier.verify (program);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		contract.operation = PcDeviceOperation.EDU_READ32;
		SsaVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void cabi_contract() {
	try {
		SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check ())));
		var upstream = WeakRef (source.c_functions[0]);
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		var program = CAbiBuilder.build (source, native);
		source = null;
		native = null;
		assert (upstream.get () == null);
		var contract = program.functions[0].metadata.device;
		contract.operation = PcDeviceOperation.ATOMIC_LOAD_RELAXED;
		bool rejected = false;
		try {
			CAbiVerifier.verify (program);
		} catch (CAbiError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		contract.operation = PcDeviceOperation.EDU_READ32;
		CAbiVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private LlvmModuleArtifact artifact() throws GLib.Error {
	SsaProgram? source = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check ())));
	var upstream = WeakRef (source.c_functions[0]);
	NativeAbiProgram? native = NativeAbiBuilder.build (source);
	CAbiProgram? cabi = CAbiBuilder.build (source, native);
	var result = LlvmLowering.lower (source, native, cabi);
	source = null;
	native = null;
	cabi = null;
	assert (upstream.get () == null);
	result.runtime_profile = new LlvmRuntimeProfile (LlvmTargetMachineArtifact.PC_BARE_METAL);
	return result;
}
private void llvm_reject(LlvmModuleArtifact result) {
	bool rejected = false;
	try {
		result.verify ();
	} catch (LlvmError error) {
		rejected = true;
		Test.message ("%s", error.message);
	}
	assert (rejected);
}
private void llvm_contract() {
	try {
		var result = artifact ();
		assert (result.pc_atomics.length == 1 && result.volatile_accesses.length == 1);
		var atomic = result.pc_atomics[0].instruction;
		CApi.set_ordering (atomic, 2);
		llvm_reject (result);
		CApi.set_ordering (atomic, 7);
		result.verify ();
		CApi.set_alignment (atomic, 1);
		llvm_reject (result);
		CApi.set_alignment (atomic, 4);
		result.verify ();
		var pointer = CApi.operand (atomic, 0);
		CApi.set_operand (atomic, 0, CApi.const_null (CApi.type_of (pointer)));
		llvm_reject (result);
		CApi.set_operand (atomic, 0, pointer);
		result.verify ();
		var memory = result.volatile_accesses[0].operation;
		CApi.set_volatile (memory, 0);
		llvm_reject (result);
		CApi.set_volatile (memory, 1);
		result.verify ();
		var address = CApi.operand (memory, 0);
		CApi.set_operand (memory, 0, CApi.const_null (CApi.type_of (address)));
		llvm_reject (result);
		CApi.set_operand (memory, 0, address);
		result.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void target_contract() {
	try {
		var result = artifact ();
		var target = new LlvmTargetMachineArtifact (0, LlvmTargetMachineArtifact.PC_BARE_METAL);
		target.configure (result);
		result.runtime_profile = new LlvmRuntimeProfile ("aarch64-none-elf", true);
		bool rejected = false;
		try {
			target.configure (result);
		} catch (LlvmError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		result.runtime_profile = new LlvmRuntimeProfile (target.triple);
		target.configure (result);
		var host = new LlvmTargetMachineArtifact ();
		rejected = false;
		try {
			host.configure (result);
		} catch (LlvmError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
		target.configure (result);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/pc-device/checked", checked_contract);
	Test.add_func ("/pc-device/core-detached", core_contract);
	Test.add_func ("/pc-device/cfg-detached", cfg_contract);
	Test.add_func ("/pc-device/ssa-detached", ssa_contract);
	Test.add_func ("/pc-device/cabi-detached", cabi_contract);
	Test.add_func ("/pc-device/llvm-detached", llvm_contract);
	Test.add_func ("/pc-device/target", target_contract);
	return Test.run ();
}
}
