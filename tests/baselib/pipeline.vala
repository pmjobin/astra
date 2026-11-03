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
#if BASELIB_LLVM
using Astra.Backend.LLVM;
#endif

namespace Astra.Tests.BaseLibrary {
private class Witness : Object {
	private WeakRef reference;
	public Witness (Object value) {
		reference = WeakRef (value);
	}

	public new Object? get() {
		return reference.get ();
	}

}
private string read(string path) throws FileError {
	string text;
	FileUtils.get_contents (path, out text);
	return text;
}

private CheckedProgram consumer(string[] paths, string[] apis, out GenericArray<Witness> sources) throws GLib.Error {
	var files = new GenericArray<SourceFile> ();
	foreach (string path in paths) {
		files.add (new SourceFile.from_text (path, read (path)));
	}
	SyntaxProgramResult? parsed = SyntaxProgram.parse (new SourceSet (files));
	files = null;
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	sources = new GenericArray<Witness> ();
	var syntax = new GenericArray<Witness> ();
	foreach (var unit in parsed.program.units) {
		sources.add (new Witness (unit.span.file));
		syntax.add (new Witness (unit));
	}
	var declarations = new GenericArray<ForeignDeclarationInput> ();
	var handles = new GenericArray<ForeignHandleInput> ();
	foreach (string path in apis) {
		var api = VapiParser.parse (new SourceFile.from_text (path, read (path)));
		assert (api.diagnostic == null);
		foreach (var declaration in VapiNormalizer.normalize (api.file)) {
			declarations.add (declaration);
		}
		foreach (var handle in VapiNormalizer.normalize_handles (api.file)) {
			handles.add (handle);
		}
	}
	var result = SemanticAnalyzer.analyze_program (parsed.program, declarations, handles);
	parsed = null;
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	foreach (var reference in syntax) {
		assert (reference.get () == null);
	}
	return result.program;
}

private void lifetime(string[] paths, string[] apis) throws GLib.Error {
	GenericArray<Witness> sources;
	CheckedProgram? checked = consumer (paths, apis, out sources);
	var function = WeakRef (checked.functions[0]);
	var body = WeakRef (checked.functions[0].body);
	var parameters = new GenericArray<Witness> ();
	foreach (var generic in checked.generic_functions) {
		foreach (var parameter in generic.definition.type_parameters) {
			parameters.add (new Witness (parameter));
		}
	}
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (function.get () == null && body.get () == null);
	CoreVerifier.verify (core);
	foreach (var parameter in parameters) {
		assert (parameter.get () == null);
	}
	core = CoreGenericMonomorphizer.build (core);
	var core_function = WeakRef (core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_function.get () == null);
	CfgVerifier.verify (cfg);
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	var cfg_function = WeakRef (cfg.functions[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_function.get () == null);
	SsaVerifier.verify (ssa);
	var ssa_function = WeakRef (ssa.functions[0]);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
#if BASELIB_LLVM
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
#endif
	ssa = null;
	assert (ssa_function.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
	nabi = null;
	cabi = null;
	foreach (var source in sources) {
		assert (source.get () == null);
	}
#if BASELIB_LLVM
	artifact.verify ();
#endif
}

private void consumers() {
	try {
		string[] base_paths = {
			"lib/astra/base/order.astra", "lib/astra/base/classify.astra", "lib/astra/base/contracts.astra", "lib/astra/base/clamp.astra"
		};
		lifetime ({base_paths[0], base_paths[1], "examples/base/pure.astra"}, {});
		lifetime ({base_paths[0], base_paths[1], base_paths[2], base_paths[3], "examples/base/contracts.astra"}, {});
		lifetime ({"lib/astra/hosted/equality.astra", "examples/base/diagnostics.astra"}, {});
		lifetime ({"examples/base/math.astra"}, {"lib/astra/hosted/math.vapi"});
		lifetime ({base_paths[0], base_paths[1], base_paths[2], base_paths[3], "lib/astra/hosted/equality.astra", "examples/base/buffer/model.astra", "examples/base/buffer/process.astra", "examples/base/buffer/main.astra"}, {"lib/astra/hosted/math.vapi"});
		lifetime ({base_paths[2], "tests/baselib/fixtures/lifetime.astra"}, {"tests/baselib/fixtures/runtime.vapi"});
		lifetime ({base_paths[0], base_paths[2], base_paths[3], "tests/baselib/fixtures/permutation.astra"}, {});
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void capabilities() {
	try {
		var types = new BuiltinTypes ();
		var universe = new GenericArray<SemanticType> ();
		foreach (string name in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "u32", "f32", "f64", "void*"}) {
			universe.add (types.resolve (name));
		}
		foreach (string element in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32", "bool"}) {
			foreach (int lanes in new int[] {2, 4, 8, 16}) {
				var vector = types.vector_of (types.resolve (element), lanes);
				if (vector != null) {
					universe.add (vector);
				}
			}
		}
		assert (universe.length == 34);
		int admitted = 0;
		foreach (var type in universe) {
			string source = read ("lib/astra/base/order.astra") + "void use(" + type.display_name () + " a," + type.display_name () + " b){min(a,b);max(a,b);}";
			var parsed = Parser.parse (new SourceFile.from_text ("capabilities.astra", source));
			assert (parsed.diagnostic == null);
			var result = SemanticAnalyzer.analyze (parsed.unit);
			assert ((result.diagnostic == null) == GenericCapabilityAuthority.satisfies (type, GenericCapabilityIdentity.ORDERED));
			if (result.diagnostic == null) {
				admitted++;
			} else {
				assert (result.diagnostic.message.contains ("does not satisfy capability 'Ordered'"));
			}
		}
		assert (admitted == 8);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/baselib/consumer-stage-lifetimes", consumers);
	Test.add_func ("/baselib/exact-ordered-universe", capabilities);
	return Test.run ();
}

}
