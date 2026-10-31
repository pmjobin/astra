// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Source;
using Astra.Foreign;

namespace Astra.Vapi {
public class VapiNormalizer : Object {
	public static GenericArray<ForeignHandleInput> normalize_handles(VapiFileSyntax file) {
		var handles = new GenericArray<ForeignHandleInput> ();
		foreach (var handle in file.handles) {
			CForeignCleanupContract? cleanup = null;
			CForeignHeader? header = null;
			string context_mode = "";
			foreach (var entry in handle.metadata.entries) {
				if (entry.key.spelling () == "destroy_function") {
					cleanup = new CForeignCleanupContract (entry.value.string_value, entry.value.span);
				} else if (entry.key.spelling () == "context") {
					context_mode = entry.value.string_value;
				} else {
					assert (entry.key.spelling () == "cheader_filename");
					header = new CForeignHeader (entry.value.string_value, entry.value.span);
				}
			}
			assert (cleanup != null);
			handles.add (new ForeignHandleInput (handle.span, handle.name.span, cleanup, header, context_mode));
		}
		return handles;
	}

	// Declaration sugar only. ForeignAbi.C plus the exact f32/f64 semantic type
	// selects C float/double later; the original span retains VAPI provenance.
	// Match only the scalar spelling: float*/double* remain unsupported.
	private static string normalize_type(string name) {
		return name == "float" ? "f32" : name == "double" ? "f64" : name;
	}

	// Preserve declaration/parameter order. Semantic collection resolves
	// these spellings in its own BuiltinTypes and validates the C subset.
	public static GenericArray<ForeignDeclarationInput> normalize(VapiFileSyntax file) {
		var declarations = new GenericArray<ForeignDeclarationInput> ();
		for (int i = 0; i < file.functions.length; i++) {
			var function = file.functions[i];
			var parameters = new GenericArray<ForeignParameterInput> ();
			for (int j = 0; j < function.parameters.length; j++) {
				var parameter = function.parameters[j];
				parameters.add (new ForeignParameterInput (parameter.span, parameter.name.span, parameter.type_name.span, normalize_type (parameter.type_name.spelling ()), parameter.borrowed_keyword == null ? PointerParameterContract.UNMANAGED : PointerParameterContract.BORROWED_NOESCAPE));
			}
			string external_symbol = function.name.spelling ();
			SourceSpan? external_symbol_span = null;
			CForeignHeader[] headers = {};
			string gobject_carrier = "";
			CForeignOwnedResultContract? owned_result = null;
			var text_abi = CTextAbi.NONE;
			SourceSpan? text_abi_span = null;
			if (function.metadata != null) {
				foreach (var entry in function.metadata.entries) {
					if (entry.key.spelling () == "cname" || entry.key.spelling () == "name") {
						external_symbol = entry.value.string_value;
						external_symbol_span = entry.value.span;
					} else if (entry.key.spelling () == "carrier") {
						gobject_carrier = entry.value.string_value;
					} else if (entry.key.spelling () == "text_abi") {
						text_abi = CTextAbi.parse (entry.value.string_value);
						text_abi_span = entry.value.span;
					} else if (entry.key.spelling () == "destroy_function") {
						owned_result = new CForeignOwnedResultContract (new CForeignCleanupContract (entry.value.string_value, entry.value.span));
					} else {
						assert (entry.key.spelling () == "cheader_filename" || entry.key.spelling () == "header");
						headers += new CForeignHeader (entry.value.string_value, entry.value.span);
					}
				}
			}
			var metadata = new CForeignMetadata (external_symbol, external_symbol_span, headers, owned_result, text_abi, text_abi_span, CBufferAbi.NONE, null, CRecordAbi.NONE, null, null, CCallbackAbi.NONE, null, CPointerAbi.NONE, null, ComImportRole.NONE, function.metadata != null && function.metadata.kind == DeclarationPolicyId.GOBJECT_IMPORT ? DeclarationPolicyId.GOBJECT_IMPORT : DeclarationPolicyId.C_IMPORT, CBoolAbi.NONE, gobject_carrier);
			declarations.add (new ForeignDeclarationInput (function.span, function.name.span, function.return_type.span, parameters, metadata, normalize_type (function.return_type.spelling ()), function.owned_keyword != null));
		}
		return declarations;
	}
}
}
