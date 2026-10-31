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

namespace Astra.Tests.Resource {
private void identity() throws GLib.Error {
	var program = check (BASIC);
	SemanticType type = program.handles[0].semantic_type;
	assert (type is HandleType && !(type is RawPointerType) && !(type is StructType));
	assert (type != program.handles[1].semantic_type && type != program.types.raw_pointer_type);
	assert (program.handles[0].cleanup == program.handles[1].cleanup);
	assert (program.c_functions[0].return_type == type && program.c_functions[0].metadata.owned_result.cleanup == program.handles[0].cleanup);
	assert (program.c_functions[1].metadata.owned_result.cleanup == program.handles[0].cleanup);
	assert (program.functions[0].locals[0].semantic_type == type && program.functions[0].locals[0].cleanup == program.handles[0].cleanup);
	assert (program.c_functions[4].metadata.owned_result == null);
	var core = CoreBuilder.build (program);
	CoreVerifier.verify (core);
	assert (core.handles[0].semantic_type == type && core.handles[0].cleanup == core.c_functions[0].owned_cleanup);
	assert (core.functions[0].owned_locals[0].place.semantic_type == type && core.functions[0].owned_locals[0].cleanup == core.handles[0].cleanup);
	assert (SemanticDump.format (program).contains ("(borrow-owner #0 \"r\" : Resource)"));
	assert (CoreDump.format (core).contains ("(borrow-owner #0 \"r\" : Resource)"));
	var control = CfgBuilder.build (core);
	assert (CfgDump.format (control).contains ("(borrowed-owner #0 : Resource)"));
	assert (control.handles[0].semantic_type == type && control.functions[0].locals[0].cleanup == control.handles[0].cleanup);
	assert (CfgFlowChecker.check (control).diagnostic == null);
	var ssa = SsaBuilder.build (control);
	assert (ssa.handles[0].semantic_type == type && ssa.handles[1].semantic_type != type);
	assert (ssa.c_functions[0].owned_cleanup == ssa.handles[0].cleanup && ssa.c_functions[2].owned_cleanup == ssa.handles[1].cleanup);
	assert (ssa.functions[0].storage.length == 0);
}
private void physical() throws GLib.Error {
	var ssa = build ("Resource empty(Resource r) { return null; } int use(borrowed Resource r) { return inspect(r); }" + BASIC);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
	assert (NativeTypeMapper.map_scalar (ssa.handles[0].semantic_type) == NativeScalarType.PTR);
	assert (CAbiTypeMapper.map_scalar (ssa.handles[1].semantic_type) == CAbiScalarType.PTR);
	assert (NativeAbiDump.format (nabi).contains ("scalar-ptr-v1"));
	assert (CAbiDump.format (cabi).contains ("scalar-ptr-v1"));
	assert (cabi.cleanups.length == 2);
	assert (cabi.functions[0].owned_cleanup == cabi.functions[2].owned_cleanup);
	assert (cabi.functions[7].signature.parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
}
private void native_differential() throws GLib.Error {
	var resource = build ("Resource empty(Resource r) { return null; }", TYPES);
	var pointer = build ("void* empty(borrowed void* r) { return null; }", "");
	assert (NativeAbiDump.format (NativeAbiBuilder.build (resource)) == NativeAbiDump.format (NativeAbiBuilder.build (pointer)));
	assert (resource.functions[0].return_type is HandleType && pointer.functions[0].return_type is RawPointerType);
}
private void cross_file(bool reversed) throws GLib.Error {
	var types = VapiParser.parse (new SourceFile.from_text ("types.vapi", TYPES));
	var api = VapiParser.parse (new SourceFile.from_text ("api.vapi", API));
	var inputs = new GenericArray<ForeignDeclarationInput> ();
	var handles = new GenericArray<ForeignHandleInput> ();
	VapiFileSyntax[] files = reversed ? new VapiFileSyntax[] {
		api.file, types.file
	} : new VapiFileSyntax[] {
		types.file, api.file
	};
	foreach (var file in files) {
		foreach (var input in VapiNormalizer.normalize (file)) {
			inputs.add (input);
		}
		foreach (var input in VapiNormalizer.normalize_handles (file)) {
			handles.add (input);
		}
	}
	var result = SemanticAnalyzer.analyze (Parser.parse (new SourceFile.from_text ("resource.astra", BASIC)).unit, inputs, handles);
	assert (result.diagnostic == null);
	assert (SemanticDump.format (result.program) == SemanticDump.format (check (BASIC)));
	assert (result.program.handles[0].ordinal == 0 && result.program.handles[1].ordinal == 1);
}
private void extern_equivalence() throws GLib.Error {
	string body = "int f() { owned Resource r = create(1); return inspect(r); }";
	var vapi = check (body, TYPES + "owned Resource create(int id); int inspect(borrowed Resource r);");
	var source = check ("extern(C) owned Resource create(int id); extern(C) int inspect(borrowed Resource r);" + body, TYPES);
	assert (SemanticDump.format (vapi) == SemanticDump.format (source));
	var left = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (vapi)));
	var right = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (source)));
	assert (CAbiDump.format (CAbiBuilder.build (left, NativeAbiBuilder.build (left))) == CAbiDump.format (CAbiBuilder.build (right, NativeAbiBuilder.build (right))));
}
private void null_phi() throws GLib.Error {
	var ssa = build ("Resource f(bool c) { Resource q = null; if (c) { q = raw(); } return q; }");
	var type = ssa.handles[0].semantic_type;
	int count = 0;
	foreach (var block in ssa.functions[0].blocks) {
		foreach (var parameter in block.parameters) {
			assert (parameter.semantic_type == type);
			count++;
		}
	}
	assert (count == 1 && ssa.functions[0].storage.length == 0);
	assert (SsaDump.format (ssa).contains ("null : Resource"));
}
private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/resource/pipeline/identity-and-contract", identity);
	add ("/resource/abi/ptr-contracts-and-interning", physical);
	add ("/resource/abi/native-pointer-differential", native_differential);
	add ("/resource/types/cross-file-api-first", () => cross_file (true));
	add ("/resource/types/cross-file-types-first", () => cross_file (false));
	add ("/resource/types/source-extern-equivalence", extern_equivalence);
	add ("/resource/ssa/typed-null-phi", null_phi);
	register_diagnostics ();
	register_lifetime ();
	foreach (string name in fixture_names ()) {
		add ("/resource/fixture/" + name, () => SsaVerifier.verify (build (read (name + ".astra"), fixture_declarations (name))));
	}
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
