// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.VectorCore {
private CoreProgram sample(BuiltinTypes types, int variant = 0) throws CoreError {
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
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (new CoreParameter (span, span, "p", type, 0));
	var local = new CoreLocalPlace (span, span, "v", type, 0, variant == 18);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (local);
	var lanes = new GenericArray<CoreValue> ();
	for (int i = 0; i < (variant == 1 ? 3 : 4); i++) {
		var element = variant == 2 ? types.u16_type : types.i16_type;
		lanes.add (new CoreIntegerValue.typed (span, element, AstraIntegerValue.from_int64 (element, i)));
	}
	var construction = new CoreVectorConstructValue (span, constructed, lanes);
	var statements = new GenericArray<CoreStatement> ();
	statements.add (new CoreInitialize (span, local, construction));
	CoreValue right = new CoreParameterValue (span, parameters[0]);
	if (variant == 8) {
		right = new CoreVectorConstructValue (span, types.vector_of (types.i16_type, 2), lanes);
	}
	var arithmetic = new CoreBinaryValue (span, variant == 7 ? (SemanticType) mask : type, variant == 9 ? BinaryOperator.DIVIDE : BinaryOperator.ADD, new CoreLoadValue (span, local), right);
	var negative = new CorePrefixValue (span, type, PrefixOperator.NEGATIVE, arithmetic);
	SemanticType compared = variant == 10 ? types.bool_type : variant == 11 ? (SemanticType) types.vector_of (types.bool_type, 8) : mask;
	CoreValue comparison = new CoreBinaryValue (span, compared, BinaryOperator.LESS, negative, right);
	if (variant == 15) {
		comparison = new CorePrefixValue (span, types.vector_of (types.u16_type, 4), PrefixOperator.NEGATIVE, new CoreVectorConstructValue (span, types.vector_of (types.u16_type, 4), lanes));
	}
	if (variant == 16) {
		comparison = new CoreBinaryValue (span, mask, BinaryOperator.LESS, comparison, comparison);
	}
	var inverted = new CorePrefixValue (span, mask, PrefixOperator.NOT, comparison);
	var op = variant == 14 ? (VectorReductionOperator) 99 : VectorReductionOperator.ALL;
	SemanticType result_type = variant == 13 ? (SemanticType) mask : types.bool_type;
	var reduction = new CoreVectorReductionValue (span, result_type, op, variant == 12 ? right : inverted);
	statements.add (new CoreStore (span, local, arithmetic));
	statements.add (new CoreReturn (span, reduction));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", types.bool_type, parameters, locals, new CoreBlock (span, statements)));
	return new CoreProgram (span, functions);
}

private void values() {
	try {
		var types = new BuiltinTypes ();
		CoreProgram? program = sample (types);
		var function = WeakRef (program.functions[0]);
		CoreVerifier.verify (program);
		string dump = CoreDump.format (program);
		assert (dump.contains ("vector-init : i16<4>") && dump.contains ("binary < : bool<4>") && dump.contains ("vector-all : bool"));
		assert (program.functions[0].locals[0].is_promotable ());
		program = null;
		assert (function.get () == null);
		// VEC-MEM-1 admits the formerly deferred address-taken numeric vector.
		var addressable = sample (types, 18);
		CoreVerifier.verify (addressable);
		assert (!addressable.functions[0].locals[0].is_promotable ());
		for (int variant = 1; variant <= 17; variant++) {
			bool rejected = false;
			try {
				CoreVerifier.verify (sample (types, variant));
			} catch (CoreError error) {
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

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vec/core/standalone-values-operators-reductions-addressability-17-rejections", values);
	return Test.run ();
}
}
