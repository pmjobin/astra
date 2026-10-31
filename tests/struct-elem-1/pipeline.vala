// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.StructElementsPipeline {
private void qualify() {
	try {
		for (int repeat = 0; repeat < 3; repeat++) {
			foreach (string name in new string[] {"borrowed", "method", "call-entry", "compose", "generic-boundaries", "owned", "lifetime", "mixed-leaves"}) {
				SsaProgram? ssa = build (name);
				var function = WeakRef (ssa.functions[0]);
				var shape = WeakRef (ssa.structs[0]);
				var native = NativeAbiBuilder.build (ssa);
				var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
				for (int i = 0; i < ssa.functions.length; i++) {
					map.insert (ssa.functions[i], native.functions[i]);
				}
				NativeAbiValidator.validate_ssa_calls (ssa, native, map);
				map.remove_all ();
				assert (native.abi_version == NativeAbiVersion.STRUCT_ELEMENTS_V11 && native.record_elements.length > 0);
				ssa = null;
				assert (function.get () == null && shape.get () == null);
				NativeAbiVerifier.verify (native);
				foreach (var record in native.record_elements) {
					NativeRecordLayout.x86_64 (record).verify_x86_64 ();
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void malformed() {
	string source = "struct S{int x;int y;}S make(){S s={x=1,y=2};return s;}void f(){S[2] a={make(),make()};a[1]=a[0];}";
	for (int variant = 0; variant < 5; variant++) {
		try {
			var cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (source))));
			var body = cfg.functions[1].entry.instructions;
			bool changed = false;
			for (int i = 0; i < body.length; i++) {
				var entry = body[i] as CfgArrayInitialize;
				if (entry == null) {
					continue;
				}
				if (variant == 0) {
					entry.elements.remove_index (1);
				}
				if (variant == 1) {
					entry.record_fields[1] = entry.record_fields[0];
				}
				if (variant == 2) {
					var first = entry.elements[0];
					entry.elements[0] = entry.elements[1];
					entry.elements[1] = first;
				}
				if (variant == 3) {
					body.remove_index (i - 1);
				}
				if (variant == 4) {
					body.remove_index (i);
				}
				changed = true;
				break;
			}
			assert (changed);
			bool rejected = false;
			try {
				CfgVerifier.verify (cfg);
			} catch (CfgError error) {
				Test.message ("CFG variant %d: %s", variant, error.message);
				rejected = true;
			}
			assert (rejected);
		} catch (GLib.Error error) {
			GLib.error ("%s", error.message);
		}
	}
	for (int variant = 0; variant < 4; variant++) {
		try {
			var cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (check (source))));
			var ssa = SsaBuilder.build (cfg);
			cfg = null;
			var body = ssa.functions[1].entry.instructions;
			bool changed = false;
			for (int i = 0; i < body.length; i++) {
				var entry = body[i] as SsaArrayInitialize;
				if (entry == null) {
					continue;
				}
				if (variant == 0) {
					entry.elements.remove_index (1);
				}
				if (variant == 1) {
					entry.record_fields[1] = entry.record_fields[0];
				}
				if (variant == 2) {
					body.remove_index (i - 1);
				}
				if (variant == 3) {
					body.remove_index (i);
				}
				changed = true;
				break;
			}
			assert (changed);
			bool rejected = false;
			try {
				SsaVerifier.verify (ssa);
			} catch (SsaError error) {
				Test.message ("SSA variant %d: %s", variant, error.message);
				rejected = true;
			}
			assert (rejected);
		} catch (GLib.Error error) {
			GLib.error ("%s", error.message);
		}
	}
	for (int variant = 0; variant < 5; variant++) {
		try {
			var ssa = build ("borrowed");
			var native = NativeAbiBuilder.build (ssa);
			var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
			for (int i = 0; i < ssa.functions.length; i++) {
				map.insert (ssa.functions[i], native.functions[i]);
			}
			if (variant == 0) {
				native.record_elements.remove_index (0);
			}
			if (variant == 1) {
				var record = native.record_elements[0];
				var field = record.fields[0];
				record.fields[0] = new NativeRecordField (field.ordinal, "wrong", field.leaf, field.record);
			}
			if (variant == 2) {
				var record = native.record_elements[0];
				native.record_elements[0] = new NativeRecordElement (record.struct_ordinal, "StaleNominalType", record.fields);
			}
			if (variant >= 3) {
				bool changed = false;
				foreach (var function in native.functions) {
					for (int i = 0; i < function.signature.parameters.length; i++) {
						var parameter = function.signature.parameters[i];
						if (!(parameter.abi_type is NativeRecordSliceType)) {
							continue;
						}
						function.signature.parameters[i] = new NativeParameter.typed (parameter.span, parameter.name_span, parameter.name, parameter.ordinal, variant == 3 ? (NativeAbiType) new NativeSliceType () : new NativeTextSliceType ());
						changed = true;
					}
				}
				assert (changed);
				NativeAbiVerifier.verify (native);
			}
			bool rejected = false;
			try {
				NativeAbiValidator.validate_ssa_calls (ssa, native, map);
			} catch (NativeAbiError error) {
				Test.message ("NABI variant %d: %s", variant, error.message);
				rejected = true;
			}
			assert (rejected);
		} catch (GLib.Error error) {
			GLib.error ("%s", error.message);
		}
	}
}
private void byte_length() {
	string nested = "struct I{int byte_length;}struct O{I inner;}int f(){O a={inner={byte_length=1}};return a.inner.byte_length;}";
	var syntax = Parser.parse (new SourceFile.from_text ("control", nested));
	assert (syntax.diagnostic == null);
	assert (SyntaxDump.format (syntax.unit).contains ("(field-access (base (field-access \"a\" \"inner\")) \"byte_length\")"));
	check (nested);
	string indexed = "int f(string[] args){return args[0].byte_length;}";
	syntax = Parser.parse (new SourceFile.from_text ("control", indexed));
	assert (syntax.diagnostic == null);
	assert (SyntaxDump.format (syntax.unit).contains ("(text-member byte_length (vector-extract (lane 0) (name \"args\")))"));
	check (indexed);
	check ("struct S{int byte_length;}int f(){S[1] a={{byte_length=3}};return a[0].byte_length;}");
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/struct-elements/pipeline/recursive-generic-ownership-plans-predecessor-lifetimes", qualify);
	Test.add_func ("/struct-elements/pipeline/incomplete-snapshots-entry-results-and-stale-native-models", malformed);
	Test.add_func ("/struct-elements/pipeline/indexed-text-and-ordinary-field-byte-length-controls", byte_length);
	return Test.run ();
}
}
