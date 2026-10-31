// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;

namespace Astra.Semantic {
public class ForeignHandleInput : Object {
	public SourceSpan span { get; private set; }
	public SourceSpan name_span { get; private set; }
	public CForeignCleanupContract cleanup { get; private set; }
	public CForeignHeader? header { get; private set; }
	private string context_contract;
	public string context_mode { get { return context_contract; } }

	public ForeignHandleInput (SourceSpan span, SourceSpan name_span, CForeignCleanupContract cleanup, CForeignHeader? header = null, string context_mode = "") {
		this.span = span;
		this.name_span = name_span;
		this.cleanup = cleanup;
		this.header = header;
		this.context_contract = context_mode;
	}
}

// Declaration input only: spans own spelling/provenance, never syntax trees.
// Local callable spelling and physical C identity have separate authorities.
// Normalized type spelling excludes lexical trivia; spans retain the complete
// original type, including comments between its identifier and star.
public class ForeignDeclarationInput : Object {
	private string callable_name;
	public string name { get { return callable_name; } }
	public bool owned_result { get; private set; }
	public SourceSpan span { get; private set; }
	public SourceSpan name_span { get; private set; }
	public CForeignMetadata metadata { get; private set; }
	public SourceSpan return_type_span { get; private set; }
	private string return_type_spelling;
	public string return_type_name { get { return return_type_spelling; } }
	public GenericArray<ForeignParameterInput> parameters { get; private set; }

	public ForeignDeclarationInput (SourceSpan span, SourceSpan name_span, SourceSpan return_type_span, GenericArray<ForeignParameterInput> parameters, CForeignMetadata? metadata = null, string? return_type_name = null, bool owned_result = false, string? name = null) {
		callable_name = name ?? name_span.text ();
		this.owned_result = owned_result;
		this.span = span;
		this.name_span = name_span;
		this.metadata = metadata ?? new CForeignMetadata (name_span.text ());
		this.return_type_span = return_type_span;
		this.return_type_spelling = return_type_name ?? return_type_span.text ();
		this.parameters = parameters;
	}
}

public class ForeignParameterInput : Object {
	private string parameter_name;
	public string name { get { return parameter_name; } }
	public PointerParameterContract pointer_contract { get; private set; }
	public SourceSpan span { get; private set; }
	public SourceSpan name_span { get; private set; }
	public SourceSpan type_span { get; private set; }
	private string type_spelling;
	public string type_name { get { return type_spelling; } }

	public ForeignParameterInput (SourceSpan span, SourceSpan name_span, SourceSpan type_span, string? type_name = null, PointerParameterContract pointer_contract = PointerParameterContract.UNMANAGED, string? name = null) {
		parameter_name = name ?? name_span.text ();
		this.pointer_contract = pointer_contract;
		this.span = span;
		this.name_span = name_span;
		this.type_span = type_span;
		this.type_spelling = type_name ?? type_span.text ();
	}
}
}
