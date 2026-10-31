// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.VectorMemoryCfg {
private CfgProgram sample(string name, int lanes = 4, int variant = 0) throws CfgError {
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
	var parameters = new GenericArray<CfgParameter> ();
	var parameter = new CfgParameter (span, span, "p", parameter_type, 0);
	parameters.add (parameter);
	var value_parameter = new CfgParameter (span, span, "value", type, 1);
	parameters.add (value_parameter);
	var locals = new GenericArray<CfgLocalPlace> ();
	var local = new CfgLocalPlace (span, span, "x", variant == 11 ? t.bool_type : type, 0, variant != 12);
	var pointer_local = new CfgLocalPlace (span, span, "q", pointer_type, 1);
	locals.add (local);
	locals.add (pointer_local);
	CfgValue one = new CfgParameterValue (span, value_parameter);
	var boolean = new CfgBooleanValue (span, t.bool_type, BooleanLiteral.TRUE);
	var origin = new DataPointerProvenance (DataPointerOrigin.LOCAL, 0, 0);
	var foreign_local = new CfgLocalPlace (span, span, "foreign", type, 0, true);
	var address = new CfgAddressOfValue (span, variant == 13 ? (SemanticType) t.raw_pointer_type : pointer_type, variant == 14 ? foreign_local : local, origin);
	var provenance = new DataPointerProvenance (DataPointerOrigin.PARAMETER, 0, variant == 18 ? 1 : 0);
	CfgValue pointer = new CfgParameterValue (span, parameter);
	if (variant == 21) {
		pointer = new CfgParameterValue (span, new CfgParameter (span, span, "foreign", pointer_type, 0));
	}
	var dereference = new CfgDereferencePlace (span, pointer, variant == 15 ? t.bool_type : type, provenance);
	var body = new CfgBlock.reserve (span, 0);
	body.instructions.add (new CfgInitialize (span, local, one));
	body.instructions.add (new CfgInitialize (span, pointer_local, address));
	body.instructions.add (variant == 16 ? (CfgInstruction) new CfgInitialize (span, dereference, one) : new CfgStore (span, dereference, variant == 17 ? (CfgValue) boolean : one));
	body.instructions.add (new CfgStore (span, local, new CfgLoadValue (span, dereference)));
	if (variant == 19) {
		body.instructions.remove_index (0);
	}
	if (variant == 22) {
		body.instructions.add (new CfgInitialize (span, local, one));
	}
	body.complete (span, new CfgReturn (span, new CfgLoadValue (span, local)));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (body);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", variant == 20 ? (SemanticType) pointer_type : type, 0, parameters, locals, blocks, body));
	return new CfgProgram (span, functions);
}

private void model() {
	try {
		foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
			for (int lanes = 2; lanes <= 16; lanes *= 2) {
				var types = new BuiltinTypes ();
				if (types.vector_of (types.resolve (name), lanes) == null) {
					continue;
				}
				CfgProgram? p = sample (name, lanes);
				CfgVerifier.verify (p);
				assert (!p.functions[0].locals[0].is_promotable () && p.functions[0].locals[1].is_promotable ());
				string dump = CfgDump.format (p);
				foreach (string word in new string[] {"address-taken", "address-of", "dereference-place", "null-traps", "(load", "(store"}) {
					assert (dump.contains (word));
				}
				var function = WeakRef (p.functions[0]);
				var type = WeakRef (p.functions[0].parameters[0].semantic_type);
				p = null;
				assert (function.get () == null && type.get () == null);
			}
		}
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 22; variant++) {
		try {
			CfgVerifier.verify (sample ("i16", 4, variant));
		} catch (CfgError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed Cfg vector memory variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/vecmem/cfg/standalone-memory-and-lifetime", model);
	Test.add_func ("/vecmem/cfg/standalone-malformed", malformed);
	return Test.run ();
}
}
