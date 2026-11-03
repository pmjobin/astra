// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;

namespace Astra.Tests.EnumShape {
internal EnumDefinition definition(BuiltinTypes types, SourceSpan span) {
	var type = new EnumType ("Pair");
	var identity = new EnumVariantIdentity (type.identity, "Data", 0);
	var fields = new GenericArray<EnumField> ();
	fields.add (new EnumField (new EnumFieldIdentity (identity, "left", 0), types.int_type, span));
	fields.add (new EnumField (new EnumFieldIdentity (identity, "right", 1), types.int_type, span));
	var variants = new GenericArray<EnumVariant> ();
	variants.add (new EnumVariant (identity, span, fields));
	variants.add (new EnumVariant (new EnumVariantIdentity (type.identity, "Empty", 1), span, new GenericArray<EnumField> ()));
	return new EnumDefinition (type, span, variants, types.i32_type);
}

}
