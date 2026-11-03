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

namespace Astra.Tests.CAbiRecordProof {
private const string SOURCE = "struct P{u8 tag;i64 total;int calls;}int apply(borrowed P* p,int x){return x;}[CCode(record_abi=\"natural-lp64\",callback=\"apply\",callback_abi=\"i32-context-i32-sync\")]extern(C) int provider(borrowed P* p,int x);int go(){P p={tag=7,total=9,calls=0};return provider(&p,23);}";
private CoreProgram core() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("c-record-proof.astra", SOURCE));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return CoreBuilder.build (checked.program);
}

private void stage_callback_authority() {
	try {
		var c = core ();
		var cp = c.functions[0].parameters[0];
		c.functions[0].parameters[0] = new CoreParameter (cp.span, cp.name_span, cp.name, cp.semantic_type, 0);
		bool rejected = false;
		try {
			CoreVerifier.verify (c);
		} catch (CoreError e) {
			rejected = e.message.contains ("C callback requires exact");
		}
		assert (rejected);
		var cfg = CfgBuilder.build (core ());
		var gp = cfg.functions[0].parameters[0];
		cfg.functions[0].parameters[0] = new CfgParameter (gp.span, gp.name_span, gp.name, gp.semantic_type, 0);
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError e) {
			rejected = e.message.contains ("C callback requires exact");
		}
		assert (rejected);
		var ssa = SsaBuilder.build (CfgBuilder.build (core ()));
		var sp = ssa.functions[0].parameters[0];
		ssa.functions[0].parameters[0] = new SsaFunctionParameter (sp.span, sp.name_span, sp.name, sp.semantic_type, 0);
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError e) {
			rejected = e.message.contains ("C callback requires exact");
		}
		assert (rejected);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void cabi_layout_and_nominal_authority() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (core ()));
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		var imported = cabi.functions[0];
		var p = imported.signature.parameters[0];
		var record = p.record;
		var bad_fields = new GenericArray<CAbiRecordField> ();
		foreach (var field in record.fields) {
			bad_fields.add (new CAbiRecordField (field.name, field.scalar_name, field.offset + 1));
		}
		var bad_layout = new CAbiRecordPlan (record.name, bad_fields, record.size, record.alignment);
		bool rejected = false;
		try {
			CAbiVerifier.verify_record (bad_layout);
		} catch (CAbiError e) {
			rejected = true;
		}
		assert (rejected);
		var fields = new GenericArray<CAbiRecordField> ();
		foreach (var field in record.fields) {
			fields.add (new CAbiRecordField (field.name, field.scalar_name == "i64" ? "u64" : field.scalar_name, field.offset));
		}
		var wrong_identity = new CAbiRecordPlan (record.name, fields, record.size, record.alignment);
		CAbiVerifier.verify_record (wrong_identity);
		imported.signature.parameters[0] = new CAbiParameter.record_view (p.span, p.name_span, p.name, p.ordinal, p.physical_ordinal, wrong_identity);
		var map = new HashTable<SsaCFunction, CAbiFunction> (direct_hash, direct_equal);
		map.insert (ssa.c_functions[0], imported);
		rejected = false;
		try {
			CAbiValidator.validate_ssa_calls (ssa, cabi, map);
		} catch (CAbiError e) {
			rejected = e.message.contains ("record field lost exact");
		}
		assert (rejected);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void cabi_callback_correspondence() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (core ()));
		var nabi = NativeAbiBuilder.build (ssa);
		var original = CAbiBuilder.build (ssa, nabi).functions[0];
		var signature = new CAbiSignature (original.signature.profile, original.signature.parameters, original.signature.result, new CAbiCallbackPlan (999, "apply"));
		var functions = new GenericArray<CAbiFunction> ();
		var imported = new CAbiFunction (original.span, original.name_span, original.name, 0, signature, original.metadata);
		functions.add (imported);
		var bad = new CAbiProgram (ssa.span, signature.profile, functions);
		CAbiVerifier.verify (bad);
		var map = new HashTable<SsaCFunction, CAbiFunction> (direct_hash, direct_equal);
		map.insert (ssa.c_functions[0], imported);
		bool rejected = false;
		try {
			CAbiValidator.validate_ssa_calls (ssa, bad, map);
		} catch (CAbiError e) {
			rejected = e.message.contains ("callback lost exact");
		}
		assert (rejected);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void native_callback_correspondence() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (core ()));
		var nabi = NativeAbiBuilder.build (ssa);
		var parameter = nabi.functions[0].signature.parameters[0];
		nabi.functions[0].signature.parameters[0] = new NativeParameter (parameter.span, parameter.name_span, parameter.name, 0, NativeScalarType.I32);
		var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		for (uint f = 0; f < ssa.functions.length; f++) {
			map.insert (ssa.functions[f], nabi.functions[f]);
		}
		bool rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, nabi, map);
		} catch (NativeAbiError e) {
			rejected = true;
		}
		assert (rejected);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

private void llvm_callback_and_context() {
	try {
		SsaProgram? ssa = SsaBuilder.build (CfgBuilder.build (core ()));
		NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
		var artifact = LlvmLowering.lower (ssa, nabi, cabi);
		var old_source = WeakRef (ssa);
		ssa = null;
		assert (old_source.get () == null);
		nabi = null;
		cabi = null;
		artifact.verify ();
		var call = (CApi.ValueRef) artifact.c_imports[0].calls[0];
		for (uint p = 0; p < 3; p++) {
			var original = CApi.operand (call, p);
			CApi.set_operand (call, p, CApi.const_null (CApi.type_of (original)));
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError e) {
				rejected = true;
			}
			CApi.set_operand (call, p, original);
			assert (rejected);
			artifact.verify ();
		}
		var callback = artifact.c_callbacks[0].value;
		CApi.set_function_call_conv (callback, CApi.CallConv.FAST);
		bool rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError e) {
			rejected = true;
		}
		CApi.set_function_call_conv (callback, CApi.CallConv.C);
		assert (rejected);
		artifact.verify ();
		var forwarded = CApi.first_instruction (CApi.first_block (callback));
		var original_context = CApi.operand (forwarded, 0);
		CApi.set_operand (forwarded, 0, CApi.const_null (CApi.type_of (original_context)));
		rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError e) {
			rejected = true;
		}
		CApi.set_operand (forwarded, 0, original_context);
		assert (rejected);
		artifact.verify ();
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/c-record/core-cfg-ssa-callback-authority", stage_callback_authority);
	Test.add_func ("/c-record/physical-layout-and-nominal-authority", cabi_layout_and_nominal_authority);
	Test.add_func ("/c-record/callback-exact-native-correspondence", cabi_callback_correspondence);
	Test.add_func ("/c-record/native-callback-parameter-correspondence", native_callback_correspondence);
	Test.add_func ("/c-record/llvm-callback-context-and-lifetime", llvm_callback_and_context);
	return Test.run ();
}

}
