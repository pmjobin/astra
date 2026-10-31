// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public class ComImportSyntax : SyntaxNode {
	public ClassDeclarationSyntax? declaration { get; private set; }
	public Token name { get; private set; }
	public ForeignPolicySyntax policy { get; private set; }
	internal ComImportSyntax (ForeignPolicySyntax policy, Token name, Token end, ClassDeclarationSyntax? declaration = null) {
		base (SourceSpan.cover (policy.span, end.span));
		this.name = name;
		this.policy = policy;
		this.declaration = declaration;
	}
}
// Source identity is kept alongside the parsed arguments. Only checked
// semantic C declarations grant an ABI; this syntax never generates code.
public class ForeignPolicySyntax : SyntaxNode {
	public DeclarationPolicyId kind { get; private set; }
	public Token name { get; private set; }
	public GenericArray<CCodeEntrySyntax> entries { get; private set; }
	internal ForeignPolicySyntax (Token name, GenericArray<CCodeEntrySyntax> entries) {
		base (name.span);
		this.name = name;
		this.kind = DeclarationPolicyRegistry.lookup (name.spelling ());
		this.entries = entries;
	}
}

// Bounded callable declaration metadata. No semantic or foreign ABI objects.
public class CCodeEntrySyntax : SyntaxNode {
	public Token key { get; private set; }
	public Token value { get; private set; }
	private string decoded;
	public string decoded_value { get { return decoded; } }
	public CCodeEntrySyntax (Token key, Token value, string decoded_value) {
		base (SourceSpan.cover (key.span, value.span));
		this.key = key;
		this.value = value;
		this.decoded = decoded_value;
	}
}
}
