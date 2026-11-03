// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.VectorCfg {
private CfgProgram sample(BuiltinTypes types, int variant = 0) throws CfgError {
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "provenance"), 0, 10);
	var type = types.vector_of (types.i16_type, 4);
	var mask = types.vector_of (types.bool_type, 4);
	SemanticType constructed = type;
	if (variant == 3) {
		constructed = new VectorType (types.i16_type, 16);
	}
	if (variant == 4) {
		constructed = new VectorType (types.i16_type, 4);
	}
	if (variant == 5) {
		constructed = new VectorType (type, 4);
	}
	if (variant == 6) {
		constructed = new SemanticType (TypeKind.VECTOR);
	}
	if (variant == 17) {
		constructed = new VectorType (new BuiltinTypes ().i16_type, 4);
	}
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (new CfgParameter (span, span, "p", type, 0));
	var local = new CfgLocalPlace (span, span, "v", type, 0, variant == 18);
	var locals = new GenericArray<CfgLocalPlace> ();
	locals.add (local);
	var lanes = new GenericArray<CfgValue> ();
	for (int i = 0; i < (variant == 1 ? 3 : 4); i++) {
		var element = variant == 2 ? types.u16_type : types.i16_type;
		lanes.add (new CfgIntegerValue.typed (span, element, AstraIntegerValue.from_int64 (element, i)));
	}
	var construction = new CfgVectorConstructInstruction (span, constructed, lanes);
	var block = new CfgBlock.reserve (span, 0);
	block.instructions.add (construction);
	block.instructions.add (new CfgInitialize (span, local, construction.result));
	CfgValue right = new CfgParameterValue (span, parameters[0]);
	if (variant == 8) {
		right = new CfgVectorConstructValue (span, types.vector_of (types.i16_type, 2), lanes);
	}
	var arithmetic = new CfgBinaryValue (span, variant == 7 ? (SemanticType) mask : type, variant == 9 ? BinaryOperator.DIVIDE : BinaryOperator.ADD, new CfgLoadValue (span, local), right);
	var negative = new CfgPrefixValue (span, type, PrefixOperator.NEGATIVE, arithmetic);
	SemanticType compared = variant == 10 ? types.bool_type : variant == 11 ? (SemanticType) types.vector_of (types.bool_type, 8) : mask;
	CfgValue comparison = new CfgBinaryValue (span, compared, BinaryOperator.LESS, negative, right);
	if (variant == 15) {
		comparison = new CfgPrefixValue (span, types.vector_of (types.u16_type, 4), PrefixOperator.NEGATIVE, new CfgVectorConstructValue (span, types.vector_of (types.u16_type, 4), lanes));
	}
	if (variant == 16) {
		comparison = new CfgBinaryValue (span, mask, BinaryOperator.LESS, comparison, comparison);
	}
	var inverted = new CfgPrefixValue (span, mask, PrefixOperator.NOT, comparison);
	var op = variant == 14 ? (VectorReductionOperator) 99 : VectorReductionOperator.ALL;
	SemanticType result_type = variant == 13 ? (SemanticType) mask : types.bool_type;
	var reduction = new CfgVectorReductionInstruction (span, result_type, op, variant == 12 ? right : inverted);
	block.instructions.add (new CfgStore (span, local, arithmetic));
	block.instructions.add (reduction);
	block.complete (span, new CfgReturn (span, reduction.result));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", types.bool_type, 0, parameters, locals, blocks, block));
	return new CfgProgram (span, functions);
}

private void values() {
	try {
		var types = new BuiltinTypes ();
		CfgProgram? program = sample (types);
		var function = WeakRef (program.functions[0]);
		CfgVerifier.verify (program);
		string dump = CfgDump.format (program);
		assert (dump.contains ("vector-init : i16<4>") && dump.contains ("binary < : bool<4>") && dump.contains ("vector-all : bool"));
		assert (program.functions[0].locals[0].is_promotable ());
		program = null;
		assert (function.get () == null);
		// VEC-MEM-1 admits the formerly deferred address-taken numeric vector.
		var addressable = sample (types, 18);
		CfgVerifier.verify (addressable);
		assert (!addressable.functions[0].locals[0].is_promotable ());
		for (int variant = 1; variant <= 17; variant++) {
			bool rejected = false;
			try {
				CfgVerifier.verify (sample (types, variant));
			} catch (CfgError error) {
				rejected = true;
			}
			if (!rejected) {
				GLib.error ("Accepted malformed vector variant %d", variant);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void branch_merge() {
	try {
		var types = new BuiltinTypes ();
		var span = SourceSpan (new SourceFile.from_text ("synthetic", "branch"), 0, 6);
		var type = types.vector_of (types.i16_type, 8);
		var mask = types.vector_of (types.bool_type, 8);
		var parameters = new GenericArray<CfgParameter> ();
		parameters.add (new CfgParameter (span, span, "condition", types.bool_type, 0));
		parameters.add (new CfgParameter (span, span, "a", type, 1));
		parameters.add (new CfgParameter (span, span, "b", type, 2));
		var local = new CfgLocalPlace (span, span, "v", type, 0);
		var locals = new GenericArray<CfgLocalPlace> ();
		locals.add (local);
		var blocks = new GenericArray<CfgBlock> ();
		for (int i = 0; i < 4; i++) {
			blocks.add (new CfgBlock.reserve (span, i));
		}
		var a = new CfgParameterValue (span, parameters[1]);
		var b = new CfgParameterValue (span, parameters[2]);
		blocks[0].instructions.add (new CfgInitialize (span, local, a));
		blocks[0].complete (span, new CfgConditionalBranch (span, new CfgParameterValue (span, parameters[0]), blocks[1], blocks[2]));
		blocks[1].instructions.add (new CfgStore (span, local, new CfgBinaryValue (span, type, BinaryOperator.ADD, a, b)));
		blocks[1].complete (span, new CfgBranch (span, blocks[3]));
		blocks[2].instructions.add (new CfgStore (span, local, b));
		blocks[2].complete (span, new CfgBranch (span, blocks[3]));
		var comparison = new CfgBinaryValue (span, mask, BinaryOperator.EQUAL, new CfgLoadValue (span, local), a);
		var reduction = new CfgVectorReductionInstruction (span, types.bool_type, VectorReductionOperator.ANY, comparison);
		blocks[3].instructions.add (reduction);
		blocks[3].complete (span, new CfgReturn (span, reduction.result));
		var function = new CfgFunction (span, span, "f", types.bool_type, 0, parameters, locals, blocks, blocks[0]);
		var functions = new GenericArray<CfgFunction> ();
		functions.add (function);
		var program = new CfgProgram (span, functions);
		CfgVerifier.verify (program);
		assert (CfgFlowChecker.check (program).diagnostic == null);
		assert (CfgPredecessors.analyze (function).predecessors (blocks[3]).length == 2);
		assert (function.locals.length == 1 && local.is_promotable ());
		assert (CfgDump.format (program).contains ("vector-any : bool"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vec/cfg/standalone-values-operators-reductions-addressability-17-rejections", values);
	Test.add_func ("/vec/cfg/standalone-branch-whole-vector-merge", branch_merge);
	return Test.run ();
}

}
