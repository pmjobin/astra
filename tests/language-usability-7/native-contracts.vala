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

namespace Astra.Tests.UsabilityNative {
private SsaProgram sample() throws GLib.Error {
	var files = new GenericArray<SourceFile> ();
	foreach (string path in new string[] {"lib/astra/text/float-format.astra", "lib/astra/text/utf8-message.astra", "lib/astra/base/errors.astra"}) {
		string text;
		FileUtils.get_contents (path, out text);
		files.add (new SourceFile.from_text (path, text));
	}
	files.add (new SourceFile.from_text ("numeric-proof.astra", "void proof(f32 first,f64 second) throws Error {var a=format_f32(first);var b=format_f64(second);}"));
	var syntax = SyntaxProgram.parse (new SourceSet (files));
	assert (syntax.diagnostic == null);
	var checked = SemanticAnalyzer.analyze_program (syntax.program);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	var graph = CfgBuilder.build (CoreBuilder.build (checked.program));
	assert (CfgFlowChecker.check (graph).diagnostic == null);
	return SsaBuilder.build (graph);
}

private void native_signature() {
	try {
		var model = sample ();
		var native = NativeAbiBuilder.build (model);
		var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		int tested = 0;
		for (int i = 0; i < model.functions.length; i++) {
			map.insert (model.functions[i], native.functions[i]);
		}
		foreach (var function in native.functions) {
			if (function.name != "format_f32" && function.name != "format_f64") {
				continue;
			}
			var original = function.signature.parameters[0];
			function.signature.parameters[0] = new NativeParameter (original.span, original.name_span, original.name, original.ordinal, NativeScalarType.I32);
			bool rejected = false;
			try {
				NativeAbiValidator.validate_ssa_calls (model, native, map);
			} catch (NativeAbiError error) {
				rejected = true;
			}
			assert (rejected);
			function.signature.parameters[0] = original;
			NativeAbiVerifier.verify (native);
			NativeAbiValidator.validate_ssa_calls (model, native, map);
			tested++;
		}
		assert (tested == 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void c_signature_and_record() {
	try {
		var model = sample ();
		var native = NativeAbiBuilder.build (model);
		var cabi = CAbiBuilder.build (model, native);
		var map = new HashTable<SsaCFunction, CAbiFunction> (direct_hash, direct_equal);
		for (int i = 0; i < model.c_functions.length; i++) {
			map.insert (model.c_functions[i], cabi.functions[i]);
		}
		int tested = 0;
		foreach (var function in cabi.functions) {
			if (function.external_symbol.has_prefix ("astra_numeric_format_")) {
				var original = function.signature.parameters[0];
				function.signature.parameters[0] = new CAbiParameter (original.span, original.name_span, original.name, original.ordinal, CAbiScalarType.I32);
				CAbiVerifier.verify (cabi);
				bool rejected = false;
				try {
					CAbiValidator.validate_ssa_calls (model, cabi, map);
				} catch (CAbiError error) {
					rejected = true;
				}
				assert (rejected);
				function.signature.parameters[0] = original;
				CAbiVerifier.verify (cabi);
				CAbiValidator.validate_ssa_calls (model, cabi, map);
				tested++;
			}
			if (function.external_symbol == "astra_numeric_parse_f64") {
				var record = function.signature.parameters[1].record;
				var field = record.fields[0];
				record.fields[0] = new CAbiRecordField (field.name, "i64", field.offset);
				CAbiVerifier.verify_record (record);
				bool rejected = false;
				try {
					CAbiValidator.validate_ssa_calls (model, cabi, map);
				} catch (CAbiError error) {
					rejected = true;
				}
				assert (rejected);
				record.fields[0] = field;
				CAbiVerifier.verify (cabi);
				CAbiValidator.validate_ssa_calls (model, cabi, map);
				tested++;
			}
		}
		assert (tested == 3);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void llvm_calls() {
	try {
		SsaProgram? model = sample ();
		var native = NativeAbiBuilder.build (model);
		var artifact = LlvmLowering.lower (model, native, CAbiBuilder.build (model, native));
		var old = WeakRef (model);
		model = null;
		assert (old.get () == null);
		artifact.verify ();
		int tested = 0;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
						continue;
					}
					var target = CApi.called_value (instruction);
					size_t length;
					string name = CApi.value_name (target, out length);
					if (!name.has_prefix ("astra_numeric_format_")) {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					CApi.set_operand (instruction, 0, CApi.const_int (CApi.int32_type_in_context (artifact.context), 1, 0));
					bool rejected = false;
					try {
						artifact.verify ();
					} catch (LlvmError error) {
						rejected = true;
					}
					assert (rejected);
					CApi.set_operand (instruction, 0, original);
					artifact.verify ();
					tested++;
					CApi.set_function_call_conv (target, CApi.CallConv.FAST);
					rejected = false;
					try {
						artifact.verify ();
					} catch (LlvmError error) {
						rejected = true;
					}
					assert (rejected);
					CApi.set_function_call_conv (target, CApi.CallConv.C);
					artifact.verify ();
					tested++;
				}
			}
		}
		assert (tested == 4);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/usability/numeric/native-signature", native_signature);
	Test.add_func ("/usability/numeric/c-signature-and-record", c_signature_and_record);
	Test.add_func ("/usability/numeric/independent-llvm-calls", llvm_calls);
	return Test.run ();
}

}
