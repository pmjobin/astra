// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.VectorMemoryCore {
private CoreProgram sample(string name, int lanes = 4, int variant = 0) {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("standalone-vecmem", "pointer"), 0, 7);
	var type = t.vector_of (t.resolve (name), lanes);
	var pointer_type = t.pointer_to (type);
	SemanticType parameter_type = pointer_type;
	switch (variant) {
	case 1:
		parameter_type = new TypedPointerType (t.bool_type);
		break;
	case 2:
		parameter_type = new TypedPointerType (t.vector_of (t.bool_type, 8));
		break;
	case 3:
		parameter_type = new TypedPointerType (new HandleType ("Resource"));
		break;
	case 4:
		parameter_type = new TypedPointerType (pointer_type);
		break;
	case 5:
		parameter_type = new TypedPointerType (t.void_type);
		break;
	case 6:
		parameter_type = t.raw_pointer_type;
		break;
	case 7:
		parameter_type = new RawPointerType (type);
		break;
	case 8:
		parameter_type = new SemanticType (TypeKind.TYPED_POINTER);
		break;
	case 9:
		parameter_type = new TypedPointerType (new VectorType (new BuiltinTypes ().resolve (name), lanes));
		break;
	case 10:
		parameter_type = new TypedPointerType (type);
		break;
	}
	var parameters = new GenericArray<CoreParameter> ();
	var parameter = new CoreParameter (span, span, "p", parameter_type, 0);
	parameters.add (parameter);
	var value_parameter = new CoreParameter (span, span, "value", type, 1);
	parameters.add (value_parameter);
	var locals = new GenericArray<CoreLocalPlace> ();
	var local = new CoreLocalPlace (span, span, "x", variant == 11 ? t.bool_type : type, 0, variant != 12);
	var pointer_local = new CoreLocalPlace (span, span, "q", pointer_type, 1);
	locals.add (local);
	locals.add (pointer_local);
	CoreValue one = new CoreParameterValue (span, value_parameter);
	var boolean = new CoreBooleanValue (span, t.bool_type, BooleanLiteral.TRUE);
	var origin = new DataPointerProvenance (DataPointerOrigin.LOCAL, 0, 0);
	var foreign_local = new CoreLocalPlace (span, span, "foreign", type, 0, true);
	var address = new CoreAddressOfValue (span, variant == 13 ? (SemanticType) t.raw_pointer_type : pointer_type, variant == 14 ? foreign_local : local, origin);
	var provenance = new DataPointerProvenance (DataPointerOrigin.PARAMETER, 0, variant == 18 ? 1 : 0);
	CoreValue pointer = new CoreParameterValue (span, parameter);
	if (variant == 21) {
		pointer = new CoreParameterValue (span, new CoreParameter (span, span, "foreign", pointer_type, 0));
	}
	var dereference = new CoreDereferencePlace (span, pointer, variant == 15 ? t.bool_type : type, provenance);
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreInitialize (span, local, one));
	body.statements.add (new CoreInitialize (span, pointer_local, address));
	body.statements.add (variant == 16 ? (CoreStatement) new CoreInitialize (span, dereference, one) : new CoreStore (span, dereference, variant == 17 ? (CoreValue) boolean : one));
	body.statements.add (new CoreStore (span, local, new CoreLoadValue (span, dereference)));
	if (variant == 19) {
		body.statements[0] = new CoreInitialize (span, local, new CoreLoadValue (span, local));
	}
	if (variant == 22) {
		body.statements.add (new CoreInitialize (span, local, one));
	}
	body.statements.add (new CoreReturn (span, new CoreLoadValue (span, local)));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", variant == 20 ? (SemanticType) pointer_type : type, parameters, locals, body));
	return new CoreProgram (span, functions);
}

private void model() {
	try {
		foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
			for (int lanes = 2; lanes <= 16; lanes *= 2) {
				var types = new BuiltinTypes ();
				if (types.vector_of (types.resolve (name), lanes) == null) {
					continue;
				}
				CoreProgram? p = sample (name, lanes);
				CoreVerifier.verify (p);
				assert (!p.functions[0].locals[0].is_promotable () && p.functions[0].locals[1].is_promotable ());
				string dump = CoreDump.format (p);
				foreach (string word in new string[] {"address-taken", "address-of", "dereference-place", "null-traps", "(load", "(store"}) {
					assert (dump.contains (word));
				}
				var function = WeakRef (p.functions[0]);
				var type = WeakRef (p.functions[0].parameters[0].semantic_type);
				p = null;
				assert (function.get () == null && type.get () == null);
			}
		}
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 22; variant++) {
		try {
			CoreVerifier.verify (sample ("i16", 4, variant));
		} catch (CoreError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed Core vector memory variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vecmem/core/standalone-memory-and-lifetime", model);
	Test.add_func ("/vecmem/core/standalone-malformed", malformed);
	return Test.run ();
}
}
