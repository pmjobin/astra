// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Vapi {
public class VapiMetadataEntrySyntax : Object {
	public VapiToken key { get; private set; }
	public VapiToken value { get; private set; }
	public SourceSpan span { get; private set; }

	internal VapiMetadataEntrySyntax (VapiToken key, VapiToken value) {
		this.key = key;
		this.value = value;
		this.span = SourceSpan.cover (key.span, value.span);
	}
}

public class VapiCCodeAttributeSyntax : Object {
	public DeclarationPolicyId kind { get; private set; }
	public SourceSpan span { get; private set; }
	public GenericArray<VapiMetadataEntrySyntax> entries { get; private set; }

	internal VapiCCodeAttributeSyntax (SourceSpan span, GenericArray<VapiMetadataEntrySyntax> entries, DeclarationPolicyId kind = DeclarationPolicyId.C_CODE) {
		this.span = span;
		this.entries = entries;
		this.kind = kind;
	}
}

public class VapiTypeNameSyntax : Object {
	public VapiToken identifier { get; private set; }
	public GenericArray<VapiToken> stars { get; private set; }
	public SourceSpan span { get; private set; }

	internal VapiTypeNameSyntax (VapiToken identifier, GenericArray<VapiToken>? stars = null) {
		this.identifier = identifier;
		this.stars = stars ?? new GenericArray<VapiToken> ();
		this.span = this.stars.length == 0 ? identifier.span : SourceSpan.cover (identifier.span, this.stars[this.stars.length - 1].span);
	}

	public string spelling() {
		return identifier.spelling () + string.nfill (stars.length, '*');
	}
}

public class VapiParameterSyntax : Object {
	public VapiTypeNameSyntax type_name { get; private set; }
	public VapiToken name { get; private set; }
	public SourceSpan span { get; private set; }
	public VapiToken? borrowed_keyword { get; private set; }

	internal VapiParameterSyntax (VapiTypeNameSyntax type_name, VapiToken name, VapiToken? borrowed_keyword = null) {
		this.span = SourceSpan.cover (borrowed_keyword == null ? type_name.span : borrowed_keyword.span, name.span);
		this.borrowed_keyword = borrowed_keyword;
		this.type_name = type_name;
		this.name = name;
	}
}

public class VapiHandleDeclarationSyntax : Object {
	public SourceSpan span { get; private set; }
	public VapiCCodeAttributeSyntax metadata { get; private set; }
	public VapiToken keyword { get; private set; }
	public VapiToken name { get; private set; }
	public VapiToken semicolon { get; private set; }

	internal VapiHandleDeclarationSyntax (VapiCCodeAttributeSyntax metadata, VapiToken keyword, VapiToken name, VapiToken semicolon) {
		this.span = SourceSpan.cover (metadata.span, semicolon.span);
		this.metadata = metadata;
		this.keyword = keyword;
		this.name = name;
		this.semicolon = semicolon;
	}
}

public class VapiFunctionDeclarationSyntax : Object {
	public VapiToken? owned_keyword { get; private set; }
	public SourceSpan span { get; private set; }
	public VapiCCodeAttributeSyntax? metadata { get; private set; }
	public VapiTypeNameSyntax return_type { get; private set; }
	public VapiToken name { get; private set; }
	public GenericArray<VapiParameterSyntax> parameters { get; private set; }

	internal VapiFunctionDeclarationSyntax (VapiTypeNameSyntax return_type, VapiToken name, GenericArray<VapiParameterSyntax> parameters, VapiToken semicolon, VapiCCodeAttributeSyntax? metadata = null, VapiToken? owned_keyword = null) {
		this.owned_keyword = owned_keyword;
		this.span = SourceSpan.cover (metadata != null ? metadata.span : owned_keyword != null ? owned_keyword.span : return_type.span, semicolon.span);
		this.metadata = metadata;
		this.return_type = return_type;
		this.name = name;
		this.parameters = parameters;
	}
}

public class VapiFileSyntax : Object {
	public GenericArray<VapiHandleDeclarationSyntax> handles { get; private set; }
	public SourceSpan span { get; private set; }
	public GenericArray<VapiFunctionDeclarationSyntax> functions { get; private set; }
	public VapiToken eof { get; private set; }

	internal VapiFileSyntax (SourceFile source, GenericArray<VapiFunctionDeclarationSyntax> functions, VapiToken eof, GenericArray<VapiHandleDeclarationSyntax>? handles = null) {
		this.handles = handles ?? new GenericArray<VapiHandleDeclarationSyntax> ();
		this.span = SourceSpan (source, 0, source.length);
		this.functions = functions;
		this.eof = eof;
	}
}
}
