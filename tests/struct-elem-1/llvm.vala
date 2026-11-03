// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;

namespace Astra.Tests.StructElementsPipeline {
private void qualify() {
	try {
		foreach (string name in new string[] {"borrowed", "method", "call-entry", "compose", "generic-boundaries", "owned", "lifetime", "mixed-leaves"}) {
			SsaProgram? ssa = build (name);
			var function = WeakRef (ssa.functions[0]);
			NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
			var plan = WeakRef (native);
			var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
			ssa = null;
			native = null;
			assert (function.get () == null && plan.get () == null);
			artifact.verify ();
			var target = new LlvmTargetMachineArtifact ();
			target.configure (artifact);
			artifact.verify ();
			assert (artifact.record_layouts.length > 0);
			string text = artifact.dump ();
			if (name == "borrowed" || name == "call-entry") {
				assert (!artifact.requires_hosted_buffers && !text.contains ("@calloc") && !text.contains ("@free"));
			} else {
				assert (artifact.requires_hosted_buffers && text.contains ("nobuiltin"));
			}
			assert (!text.contains ("byval") && !text.contains ("sret") && !text.contains ("@llvm.memcpy"));
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private LlvmModuleArtifact overflow(bool index, bool unsigned_overflow = false) throws LlvmError {
	var artifact = new LlvmModuleArtifact ();
	var i32 = CApi.int32_type_in_context (artifact.context);
	var type = CApi.function_type (i32, null, 0, 0);
	var function = CApi.add_function (artifact.module, "main", type);
	var entry = CApi.append_basic_block_in_context (artifact.context, function, "entry");
	var state = new LlvmBlockState (entry);
	var builder = CApi.create_builder_in_context (artifact.context);
	CApi.position_builder_at_end (builder, entry);
	var scalars = new LlvmScalarLowering (artifact, new LlvmTypeMapper (artifact.context), builder, function);
	var allocation = new LlvmBufferAllocation (artifact, builder, function, scalars);
	var element = CApi.array_type (CApi.int_type_in_context (artifact.context, 8), ((uint64) 1) << 60);
	if (index) {
		allocation.guard_record_offset (CApi.const_int (CApi.int_type_in_context (artifact.context, 64), unsigned_overflow ? 32 : 8, 0), element, "record", state);
	} else {
		allocation.allocate (CApi.const_int (i32, unsigned_overflow ? 32 : 8, 0), element, "record", state, true);
	}
	CApi.build_ret (builder, CApi.const_int (i32, 1, 0));
	CApi.dispose_builder (builder);
	var target = new LlvmTargetMachineArtifact ();
	target.configure (artifact);
	artifact.verify ();
	return artifact;
}

private void arithmetic() {
	try {
		foreach (bool index in new bool[] {false, true}) {
			foreach (bool unsigned_overflow in new bool[] {false, true}) {
				var artifact = overflow (index, unsigned_overflow);
				string text = artifact.dump ();
				assert (text.contains ("record.address.trap") && text.contains ("9223372036854775807") && text.contains ("umul.with.overflow.i64") && artifact.requires_hosted_buffers != index);
			}
		}
		LlvmTargetMachineArtifact.qualify_record_elements ("x86_64-pc-linux-gnu", 8);
		foreach (string triple in new string[] {"aarch64-unknown-linux-gnu", "x86_64-pc-windows-msvc", "x86_64-unknown-none"}) {
			bool rejected = false;
			try {
				LlvmTargetMachineArtifact.qualify_record_elements (triple, 8);
			} catch (LlvmError error) {
				rejected = true;
			}
			assert (rejected);
		}
		bool rejected = false;
		try {
			LlvmTargetMachineArtifact.qualify_record_elements ("x86_64-pc-linux-gnux32", 4);
		} catch (LlvmError error) {
			rejected = true;
		}
		assert (rejected);
	} catch (LlvmError error) {
		GLib.error ("%s", error.message);
	}
}

private int emit(string[] args) throws GLib.Error {
	var files = new GenericArray<SourceFile> ();
	var foreign = new GenericArray<ForeignDeclarationInput> ();
	var handles = new GenericArray<ForeignHandleInput> ();
	for (int i = 3; i < args.length; i++) {
		bool vapi = args[i] == "--vapi";
		if (vapi) {
			i++;
		}
		string bytes;
		FileUtils.get_contents (args[i], out bytes);
		var source = new SourceFile.from_text (args[i], bytes);
		if (vapi) {
			var parsed = Astra.Vapi.VapiParser.parse (source);
			assert (parsed.diagnostic == null);
			foreach (var item in Astra.Vapi.VapiNormalizer.normalize (parsed.file)) {
				foreign.add (item);
			}
			foreach (var item in Astra.Vapi.VapiNormalizer.normalize_handles (parsed.file)) {
				handles.add (item);
			}
		} else {
			files.add (source);
		}
	}
	var syntax = SyntaxProgram.parse (new SourceSet (files));
	if (syntax.diagnostic != null) {
		GLib.error ("%s", syntax.diagnostic.format ());
	}
	var checked = SemanticAnalyzer.analyze_program (syntax.program, foreign, handles);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	var cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program)));
	var flow = CfgFlowChecker.check (cfg);
	if (flow.diagnostic != null) {
		GLib.error ("%s", flow.diagnostic.format ());
	}
	var ssa = SsaBuilder.build (cfg);
	var nabi = NativeAbiBuilder.build (ssa);
	var artifact = LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi), Astra.Driver.ProgramEntry.resolve (ssa));
	artifact.configure_executable (new LlvmTargetMachineArtifact ());
	FileUtils.set_contents (args[2], artifact.dump ());
	return 0;
}

int main(string[] args) {
	if (args.length >= 4 && args[1] == "--emit") {
		try {
			return emit (args);
		} catch (GLib.Error error) {
			stderr.printf ("%s\n", error.message);
			return 1;
		}
	}
	if (args.length == 2 && (args[1] == "--dump-overflow" || args[1] == "--dump-offset" || args[1] == "--dump-overflow-unsigned" || args[1] == "--dump-offset-unsigned")) {
		try {
			stdout.puts (overflow (args[1].has_prefix ("--dump-offset"), args[1].has_suffix ("-unsigned")).dump ());
			return 0;
		} catch (GLib.Error error) {
			stderr.printf ("%s\n", error.message);
			return 1;
		}
	}
	Test.init (ref args);
	Test.add_func ("/struct-elements/llvm/target-layout-predecessor-lifetimes-allocator-separation", qualify);
	Test.add_func ("/struct-elements/llvm/independent-physical-overflow-and-target-gates", arithmetic);
	return Test.run ();
}

}
