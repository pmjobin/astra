// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Tests.OwningShape {
internal EnumDefinition definition(BuiltinTypes types, SourceSpan span) {
	var type = new EnumType ("Owner");
	var ready = new EnumVariantIdentity (type.identity, "Ready", 0);
	var fields = new GenericArray<EnumField> ();
	fields.add (new EnumField (new EnumFieldIdentity (ready, "left", 0), types.slice_of (types.int_type), span, true));
	fields.add (new EnumField (new EnumFieldIdentity (ready, "right", 1), types.slice_of (types.int_type), span, true));
	var variants = new GenericArray<EnumVariant> ();
	variants.add (new EnumVariant (ready, span, fields));
	variants.add (new EnumVariant (new EnumVariantIdentity (type.identity, "Empty", 1), span, new GenericArray<EnumField> ()));
	return new EnumDefinition (type, span, variants, types.i32_type);
}
}
