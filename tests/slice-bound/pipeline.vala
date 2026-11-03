// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.SliceBound {
private void lifetime() throws GLib.Error {
	CheckedProgram? checked = check ("void f(borrowed i16[] s){i16[] local=s;local[0]=s[0];helper(local);} void helper(borrowed i16[] s){int n=len(s);}");
	var type = checked.functions[0].symbol.parameters[0].semantic_type;
	var parameter = WeakRef (checked.functions[0].symbol.parameters[0]);
	var region = WeakRef (checked.functions[0].body.region);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (parameter.get () == null && region.get () == null);
	CoreVerifier.verify (core);
	assert (core.functions[0].parameters.length == 1 && core.functions[0].parameters[0].semantic_type == type && core.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	var core_witness = WeakRef (core.functions[0].parameters[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_witness.get () == null);
	CfgVerifier.verify (cfg);
	assert (cfg.functions[0].parameters.length == 1 && cfg.functions[0].parameters[0].semantic_type == type && cfg.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	var cfg_witness = WeakRef (cfg.functions[0].parameters[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_witness.get () == null);
	SsaVerifier.verify (ssa);
	assert (ssa.functions[0].parameters.length == 1 && ssa.functions[0].parameters[0].semantic_type == type && ssa.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
	assert (ssa.functions[0].storage.length == 0);
	var ssa_witness = WeakRef (ssa.functions[0].parameters[0]);
	var type_witness = WeakRef (type);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	type = null;
	ssa = null;
	assert (ssa_witness.get () == null && type_witness.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
	assert (nabi.functions[0].signature.parameters.length == 1 && nabi.functions[0].signature.physical_parameter_count == 2);
}

private void grouping() throws GLib.Error {
	var ssa = build (read ("sum"));
	assert (ssa.functions.length == 2 && ssa.functions[0].parameters.length == 1);
	int calls = 0;
	foreach (var block in ssa.functions[1].blocks) {
		foreach (var instruction in block.instructions) {
			var call = instruction as SsaCallInstruction;
			if (call == null) {
				continue;
			}
			assert (call.target == ssa.functions[0] && call.arguments.length == 1 && call.arguments[0].semantic_type == ssa.functions[0].parameters[0].semantic_type);
			calls++;
		}
	}
	assert (calls == 2);
	assert (((ArrayType) ssa.functions[1].storage[0].semantic_type).length == 4 && ((ArrayType) ssa.functions[1].storage[1].semantic_type).length == 8);
	var abi = NativeAbiBuilder.build (ssa);
	assert (abi.abi_version == NativeAbiVersion.SLICE_V5 && abi.functions[0].signature.parameters[0].abi_type is NativeSliceType);
	assert (NativeAbiDump.format (abi).contains ("(parameter #0 SLICE(PTR,I32))"));
	ssa = build (read ("merge"));
	int phis = 0;
	foreach (var block in ssa.functions[1].blocks) {
		foreach (var p in block.parameters) {
			if (p.semantic_type is SliceType) {
				phis++;
			}
		}
	}
	assert (phis >= 2);
	foreach (string fixture in new string[] {"alias", "forward", "mixed", "owned", "bit", "dsp", "dot", "owned-result"}) {
		SsaVerifier.verify (build (read (fixture)));
	}
	ssa = build (read ("owned-result"));
	abi = NativeAbiBuilder.build (ssa);
	assert (ssa.functions[0].parameters.length == 2 && ssa.functions[0].parameters[0].semantic_type is SliceType);
	assert (ssa.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && ssa.functions[0].parameters[1].pointer_contract == PointerParameterContract.OWNED_TRANSFER);
	assert (abi.functions[0].signature.parameters[0].abi_type is NativeSliceType && abi.functions[0].signature.physical_parameter_count == 3);
	assert (abi.functions[0].signature.result.abi_type.spelling () == "PTR");
	foreach (string source in new string[] {"void f(){int[1] a={1};int[] s=slice(a);}", "void f(){i16<8> v=splat(1,8);i16<8>[1] a={v};i16<8>[] s=slice(a);}"}) {
		assert (NativeAbiBuilder.build (build (source)).abi_version == NativeAbiVersion.SCALAR_V0);
	}
	assert (NativeAbiBuilder.build (build ("void f(i16<8>* p){}")).abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("void f(i16<8> v){}")).abi_version == NativeAbiVersion.VECTOR_V4);
	foreach (string source in new string[] {"void f(borrowed int[] s){} void g(f32<4> v){}", "void g(f32<4> v){} void f(borrowed int[] s){}"}) {
		assert (NativeAbiBuilder.build (build (source)).abi_version == NativeAbiVersion.SLICE_V5);
	}
}

private void order() throws GLib.Error {
	string declarations = "int start(){return 0;} int count(){return 2;} int later(){return 7;} void consume(owned Resource r,borrowed int[] s,int n){}";
	var cfg = CfgBuilder.build (CoreBuilder.build (check (declarations + "void f(owned Resource r){int[2] a={1,2};consume(move r,slice(a,start(),count()),later());}")));
	var events = new StringBuilder ();
	CfgEvaluateInstruction? construction = null;
	CfgCallInstruction? consume = null;
	foreach (var instruction in cfg.functions[4].entry.instructions) {
		if (instruction is CfgOwnedArgumentCapture) {
			events.append ("capture ");
		}
		if (instruction is CfgOwnedCallTransferCommit) {
			events.append ("commit ");
		}
		var evaluation = instruction as CfgEvaluateInstruction;
		if (evaluation != null && evaluation.value is CfgSliceFromArrayValue) {
			events.append ("slice ");
			construction = evaluation;
		}
		var call = instruction as CfgCallInstruction;
		if (call != null) {
			events.append (call.target.name + " ");
			if (call.target.name == "consume") {
				consume = call;
			}
		}
	}
	assert (events.str == "capture start count slice later commit consume ");
	assert (consume.arguments[1] == construction.result);
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	SsaVerifier.verify (SsaBuilder.build (cfg));
	// A malformed CFG may not postpone a trapping constructor past commit.
	consume.arguments[1] = construction.value;
	bool rejected = false;
	try {
		CfgVerifier.verify (cfg);
	} catch (CfgError error) {
		rejected = error.message.contains ("before transfer commit");
	}
	assert (rejected);
	foreach (string call in new string[] {"consume(move r,slice(a,start(r),2),0);", "consume(move r,slice(a,0,start(r)),0);"}) {
		cfg = CfgBuilder.build (CoreBuilder.build (check ("int start(borrowed Resource r){return 0;} void consume(owned Resource r,borrowed int[] s,int n){} void f(owned Resource r){int[2] a={1,2};" + call + "}")));
		assert (CfgFlowChecker.check (cfg).diagnostic.message.contains ("moved owned value 'r'"));
	}
	SsaVerifier.verify (build ("int start(borrowed Resource r){return 0;} void consume(borrowed int[] s,owned Resource r){} void f(owned Resource r){int[2] a={1,2};consume(slice(a,start(r),2),move r);}"));
}

private void exact_calls() throws GLib.Error {
	var ssa = build ("void signed_slice(borrowed i8[] s){} void unsigned_slice(borrowed u8[] s){unsigned_slice(s);}");
	var abi = NativeAbiBuilder.build (ssa);
	assert (abi.functions[0].signature.parameters[0].abi_type.same_type (abi.functions[1].signature.parameters[0].abi_type));
	var arguments = new GenericArray<SsaValue> ();
	arguments.add (ssa.functions[1].parameters[0]);
	var call = new SsaCallInstruction (ssa.span, null, -1, ssa.functions[0], arguments);
	var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
	for (int i = 0; i < ssa.functions.length; i++) {
		map.insert (ssa.functions[i], abi.functions[i]);
	}
	bool rejected = false;
	try {
		NativeAbiValidator.validate_call (call, abi, map, "call");
	} catch (NativeAbiError error) {
		rejected = error.message.contains ("exact semantic parameter type");
	}
	assert (rejected);
	ssa.functions[1].entry.instructions[0] = call;
	rejected = false;
	try {
		SsaVerifier.verify (ssa);
	} catch (SsaError error) {
		rejected = error.message.contains ("call argument type");
	}
	assert (rejected);
	var types = new BuiltinTypes ();
	foreach (var contract in new PointerParameterContract[] {PointerParameterContract.UNMANAGED, PointerParameterContract.OWNED_TRANSFER}) {
		rejected = false;
		try {
			NativeTypeMapper.map_parameter (types.slice_of (types.int_type), contract);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
	}
	rejected = false;
	try {
		NativeTypeMapper.map_result (types.slice_of (types.int_type));
	} catch (NativeAbiError error) {
		rejected = true;
	}
	assert (rejected);
}

private void foreign_guards() throws GLib.Error {
	foreach (string source in new string[] {"void f(borrowed int[] s);", "void f(int[] s);", "int[] f();", "void f(owned int[] s);"}) {
		var parsed = Astra.Vapi.VapiParser.parse (new Astra.Source.SourceFile.from_text ("slice-bound.vapi", source));
		assert (parsed.diagnostic != null);
	}
	var parsed = Astra.Syntax.Parser.parse (new Astra.Source.SourceFile.from_text ("slice-bound.astra", "void f(borrowed Resource[] s){}"));
	assert (parsed.unit != null);
	var vapi = Astra.Vapi.VapiParser.parse (new Astra.Source.SourceFile.from_text ("resource.vapi", declarations ()));
	var result = SemanticAnalyzer.analyze (parsed.unit, Astra.Vapi.VapiNormalizer.normalize (vapi.file), Astra.Vapi.VapiNormalizer.normalize_handles (vapi.file));
	assert (result.diagnostic.message.contains ("unsupported slice element"));
	SsaVerifier.verify (build ("void helper(borrowed Resource r){} void f(borrowed Resource r,borrowed int[] s){helper(r);s[0]=resource_id(r);} void raw(borrowed void* p){} void handle(borrowed void* p){raw(p);}"));
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/slice-bound/pipeline/independent-lifetimes", lifetime);
	add ("/slice-bound/pipeline/one-parameter-merges-and-profiles", grouping);
	add ("/slice-bound/pipeline/owned-capture-range-evaluation-commit", order);
	add ("/slice-bound/pipeline/exact-call-and-mapping-guards", exact_calls);
	add ("/slice-bound/pipeline/foreign-deferrals-and-handle-regressions", foreign_guards);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
