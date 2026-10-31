// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.VectorLaneCore {
private CoreProgram sample(int variant = 0) throws CoreError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("synthetic", "lane metadata"), 0, 13);
	var type = types.vector_of (types.i16_type, 4);
	var unsigned_type = types.vector_of (types.u16_type, 4);
	var mask_type = types.vector_of (types.bool_type, 4);
	var statements = new GenericArray<CoreStatement> ();
	var scalar = new CoreIntegerValue.typed (span, types.i16_type, AstraIntegerValue.from_int64 (types.i16_type, 7));
	var unsigned_scalar = new CoreIntegerValue.typed (span, types.u16_type, AstraIntegerValue.from_int64 (types.u16_type, 7));
	var yes = new CoreBooleanValue (span, types.bool_type, BooleanLiteral.TRUE);
	SemanticType splat_type = variant == 2 ? new VectorType (types.i16_type, 16) : variant == 26 ? new VectorType (types.i16_type, 4) : type;
	var splat = new CoreVectorSplatValue (span, splat_type, variant == 1 ? unsigned_scalar : scalar, variant == 3 ? 3 : 4, span);
	var index = new VectorLaneIndex (span, variant == 5 ? -1 : variant == 6 ? 4 : 2);
	var extract = new CoreVectorExtractValue (span, variant == 7 ? types.u16_type : types.i16_type, variant == 4 ? (CoreValue) scalar : splat, index);
	var insertion_index = new VectorLaneIndex (span, variant == 11 ? -1 : variant == 12 ? 4 : 1);
	var insert = new CoreVectorInsertValue (span, variant == 10 ? unsigned_type : type, variant == 8 ? (CoreValue) scalar : splat, insertion_index, variant == 9 ? (CoreValue) unsigned_scalar : extract);
	var indices = new GenericArray<VectorLaneIndex> ();
	for (int i = 0; i < (variant == 14 ? 3 : variant == 15 ? 5 : 4); i++) {
		indices.add (new VectorLaneIndex (span, i == 0 && variant == 16 ? -1 : i == 0 && variant == 17 ? 4 : (3 - i + 4) % 4));
	}
	var selectors = new VectorLaneSelectors (indices);
	indices[0] = new VectorLaneIndex (span, 99);
	assert (selectors.at (0).ordinal != 99);
	var shuffle = new CoreVectorShuffleValue (span, variant == 18 ? types.vector_of (types.i16_type, 2) : type, variant == 13 ? (CoreValue) scalar : insert, selectors);
	var mask = new CoreVectorSplatValue (span, variant == 21 ? types.vector_of (types.bool_type, 2) : mask_type, yes, variant == 21 ? 2 : 4, span);
	var other = new CoreVectorSplatValue (span, unsigned_type, unsigned_scalar, 4, span);
	var select = new CoreVectorSelectValue (span, variant == 23 ? unsigned_type : type, variant == 19 ? (CoreValue) yes : variant == 20 ? (CoreValue) splat : mask, variant == 24 ? (CoreValue) scalar : shuffle, variant == 22 ? other : splat);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (new CoreLocalPlace (span, span, "other", unsigned_type, 0));
	statements.add (new CoreInitialize (span, locals[0], other));
	statements.add (new CoreReturn (span, select));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", type, new GenericArray<CoreParameter> (), locals, new CoreBlock (span, statements)));
	return new CoreProgram (span, functions);
}

private void values() {
	try {
		CoreProgram? program = sample ();
		var weak_function = WeakRef (program.functions[0]);
		CoreVerifier.verify (program);
		string dump = CoreDump.format (program);
		foreach (string name in new string[] {"splat", "extract", "insert", "shuffle", "select"}) {
			assert (dump.contains ("vector-" + name));
		}
		program = null;
		assert (weak_function.get () == null);
		for (int variant = 1; variant <= 26; variant++) {
			if (variant == 25) {
				continue;
			}
			bool rejected = false;
			try {
				CoreVerifier.verify (sample (variant));
			} catch (CoreError error) {
				rejected = true;
			}
			if (!rejected) {
				GLib.error ("Accepted malformed Core vector primitive variant %d", variant);
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vec-lane/core/standalone-values-and-verifier", values);
	return Test.run ();
}
}
