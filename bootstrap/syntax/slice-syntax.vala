// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public class SliceTypeSyntax : TypeNameSyntax {
	public TypeNameSyntax element_type { get; private set; }

	public SliceTypeSyntax (TypeNameSyntax element_type, Token close) {
		base.shaped (SourceSpan.cover (element_type.span, close.span), element_type.identifier);
		this.element_type = element_type;
	}

	public override string spelling() {
		return element_type.spelling () + "[]";
	}

}
}
