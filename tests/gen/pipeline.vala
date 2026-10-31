// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.Generics {
private void lifetime() throws GLib.Error {
	CheckedProgram? checked = check (read ("property"));
	var generic = WeakRef (checked.generic_functions[1]);
	var symbol = WeakRef (checked.generic_functions[1].symbol);
	var tp = WeakRef (checked.generic_functions[1].definition.type_parameters[0]);
	var property = WeakRef (checked.classes[0].properties[0]);
	var method = WeakRef (checked.classes[0].methods[0]);
	CoreProgram? parameterized = CoreBuilder.build (checked);
	checked = null;
	assert (generic.get () == null && symbol.get () == null && tp.get () == null && property.get () == null && method.get () == null);
	CoreVerifier.verify (parameterized);
	var definition = WeakRef (parameterized.generic_functions[1]);
	var type = WeakRef (parameterized.generic_functions[1].return_type);
	CoreProgram? concrete = CoreGenericMonomorphizer.build (parameterized);
	parameterized = null;
	assert (definition.get () == null && type.get () == null);
	CoreVerifier.verify_concrete (concrete);
	var function = WeakRef (concrete.functions[concrete.functions.length - 1]);
	CfgProgram? cfg = CfgBuilder.build (concrete);
	concrete = null;
	assert (function.get () == null);
	CfgVerifier.verify (cfg);
	var cf = WeakRef (cfg.functions[cfg.functions.length - 1]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cf.get () == null);
	SsaVerifier.verify (ssa);
	var sf = WeakRef (ssa.functions[ssa.functions.length - 1]);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	ssa = null;
	assert (sf.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
}
private void member_identity() throws GLib.Error {
	var parameterized = CoreBuilder.build (check (read ("property")));
	var property = parameterized.classes[0].properties[0];
	var method = parameterized.classes[0].methods[0];
	var field = parameterized.classes[0].fields[0];
	var generic = parameterized.generic_functions[1];
	var get = ((CoreInitialize) generic.body.statements[0]).value as CoreCallValue;
	assert (get.target == property.getter);
	var original_method = ((CoreCallValue) ((CoreInitialize) generic.body.statements[1]).value).target;
	var ordinary = ((CoreCallValue) ((CoreInitialize) generic.body.statements[3]).value).target;
	var concrete = CoreGenericMonomorphizer.build (parameterized);
	int count = 0;
	foreach (var instance in concrete.functions) {
		if (instance.generic_instance == null || instance.generic_instance.origin != generic.identity) {
			continue;
		}
		count++;
		assert (((CoreCallValue) ((CoreInitialize) instance.body.statements[0]).value).target == property.getter);
		assert (((CoreCallValue) ((CoreInitialize) instance.body.statements[1]).value).target == method && method == original_method);
		assert (((CoreIndirectFieldPlace) ((CoreLoadValue) ((CoreInitialize) instance.body.statements[2]).value).source).field == field);
		assert (((CoreCallValue) ((CoreInitialize) instance.body.statements[3]).value).target == ordinary);
		assert (instance.locals[0] != generic.locals[0] && instance.parameters[0] != generic.parameters[0]);
	}
	assert (count == 2);
}
private void inventory() throws GLib.Error {
	var parameterized = CoreBuilder.build (check (read ("dedup")));
	assert (parameterized.generic_functions.length == 3);
	var concrete = CoreGenericMonomorphizer.build (parameterized);
	int identities = 0;
	int phantoms = 0;
	int ints = 0;
	foreach (var f in concrete.functions) {
		var instance = f.generic_instance;
		if (instance == null) {
			continue;
		}
		assert (instance.state == GenericInstanceState.COMPLETE);
		if (instance.origin.name == "identity") {
			identities++;
			if (instance.type_arguments[0].kind == TypeKind.INT) {
				ints++;
				assert (instance.callers.length >= 6 && instance.requests >= 7);
			}
		}
		if (instance.origin.name == "tag") {
			phantoms++;
			assert (f.parameters.length == 0 && f.return_type.kind == TypeKind.INT);
		}
		assert (instance.origin.name != "unused");
	}
	assert (identities == 8 && phantoms == 2 && ints == 1);
	assert (CoreDump.format (concrete) == CoreDump.format (core (read ("dedup"))));
}
private void profiles() throws GLib.Error {
	string declaration = "T identity<T>(T x){return x;}";
	foreach (string type in new string[] {"int", "i8", "f32", "f64", "void*", "i16<8>"}) {
		var ssa = build (declaration + type + " root(" + type + " x){return identity<" + type + ">(x);}");
		var nabi = NativeAbiBuilder.build (ssa);
		assert (nabi.functions.length == 2);
		var signature = nabi.functions[1].signature;
		assert (signature.parameters.length == 1 && signature.physical_parameter_count == 1);
		if (type == "int") {
			assert (nabi.abi_version == NativeAbiVersion.SCALAR_V0);
		}
		if (type == "i8") {
			assert (nabi.abi_version == NativeAbiVersion.SCALAR_INT_V2);
		}
		if (type == "f32") {
			assert (nabi.abi_version == NativeAbiVersion.SCALAR_FP_V3 && signature.result.scalar_type == NativeScalarType.F32);
		}
		if (type == "f64") {
			assert (nabi.abi_version == NativeAbiVersion.FP64_V6 && signature.result.scalar_type == NativeScalarType.F64);
		}
		if (type == "void*") {
			assert (nabi.abi_version == NativeAbiVersion.SCALAR_PTR_V1 && signature.result.scalar_type == NativeScalarType.PTR);
		}
		if (type == "i16<8>") {
			assert (nabi.abi_version == NativeAbiVersion.VECTOR_V4 && signature.result.abi_type is NativeVectorType);
		}
	}
	var unused = build ("T unused<T>(T x){return x;}");
	assert (unused.functions.length == 0 && NativeAbiBuilder.build (unused).functions.length == 0);
	var mixed = build ("T mix<T>(borrowed Resource r,f32 f,void* p,i16<8> v,T x){return x;}f64 root(borrowed Resource r,f32 f,void* p,i16<8> v,f64 x){return mix<f64>(r,f,p,v,x);}");
	assert (NativeAbiBuilder.build (mixed).abi_version == NativeAbiVersion.FP64_V6);
}
private void flow() throws GLib.Error {
	SsaVerifier.verify (build ("class C{int raw;init(int x){this.raw=x;}}owned C make<T>(T ignored){return C.init(42);}int main(){owned C c=make<f64>(1.25);return c.raw;}"));
	foreach (string fixture in new string[] {"choose", "loop", "chain", "recursive", "mutual", "cross", "property", "owned", "object-owned", "concrete"}) {
		SsaVerifier.verify (build (read (fixture)));
	}
	foreach (string fixture in new string[] {"choose", "loop"}) {
		var ssa = build (read (fixture));
		int floating = 0;
		int vectors = 0;
		foreach (var f in ssa.functions) {
			foreach (var block in f.blocks) {
				foreach (var p in block.parameters) {
					if (p.semantic_type is F64Type) {
						floating++;
					}
					if (p.semantic_type is VectorType) {
						vectors++;
					}
					assert (!(p.semantic_type is TypeParameterType));
				}
			}
		}
		assert (floating > 0 && vectors > 0);
	}
}
private void firewalls() throws GLib.Error {
	bool rejected = false;
	try {
		SsaVerifier.verify (unresolved_ssa ());
	} catch (SsaError error) {
		rejected = true;
	}
	assert (rejected);
	rejected = false;
	try {
		NativeAbiBuilder.build (unresolved_ssa ());
	} catch (NativeAbiError error) {
		rejected = true;
	}
	assert (rejected);
	rejected = false;
	try {
		NativeTypeMapper.map_type (new TypeParameterType ("T"));
	} catch (NativeAbiError error) {
		rejected = true;
	}
	assert (rejected);
	string bindings;
	FileUtils.get_contents ("tests/obj-life/fixtures/lifecycle.vapi", out bindings);
	var vapi = Astra.Vapi.VapiParser.parse (new SourceFile.from_text ("resource.vapi", bindings));
	var parsed = Parser.parse (new SourceFile.from_text ("bad.astra", "int tag<T>(){return 1;}int main(){return tag<Resource>();}"));
	var checked = SemanticAnalyzer.analyze (parsed.unit, Astra.Vapi.VapiNormalizer.normalize (vapi.file), Astra.Vapi.VapiNormalizer.normalize_handles (vapi.file));
	assert (checked.diagnostic != null && checked.diagnostic.message.contains ("GEN-1 type argument 'Resource'"));
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/gen/pipeline/generic-firewalls-resource-deferral", firewalls);
	add ("/gen/pipeline/all-stage-lifetimes", lifetime);
	add ("/gen/pipeline/exact-member-identities", member_identity);
	add ("/gen/pipeline/inventory-global-dedup-phantom", inventory);
	add ("/gen/pipeline/concrete-nabi-profiles-mixed-unused", profiles);
	add ("/gen/pipeline/ssa-flow-ownership-concrete-code", flow);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
