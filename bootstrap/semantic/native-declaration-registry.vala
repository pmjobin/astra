// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Semantic {
// A construction-local demand, resolved by ordinary type and member lookup.
// Only its canonical key survives interface construction.
public class NativeMethodRequest : Object {
	private string requested_selector;
	private string? resolved_key;
	public TypeNameSyntax owner { get; private set; }
	public GenericTypeApplicationSyntax member { get; private set; }
	public bool is_export { get; private set; }
	public string selector { get { return requested_selector; } }
	public string? key { get { return resolved_key; } internal set { resolved_key = value; } }
	public NativeMethodRequest (string selector, TypeNameSyntax owner, GenericTypeApplicationSyntax member, bool is_export = false) {
		this.requested_selector = selector;
		this.owner = owner;
		this.member = member;
		this.is_export = is_export;
	}
}
// Construction-local correspondence. Only copied declaration facts survive
// source analysis; this table never enters Core or a native plan.
public class NativeDeclarationRegistry : Object {
	public GenericArray<NativeMethodRequest> method_requests { get; private set; default = new GenericArray<NativeMethodRequest> (); }
	private HashTable<SourceFile, HashTable<string, NativeDeclarationIdentity>> files = new HashTable<SourceFile, HashTable<string, NativeDeclarationIdentity>> (direct_hash, direct_equal);
	private HashTable<SourceFile, GenericArray<string>> closed_types = new HashTable<SourceFile, GenericArray<string>> (direct_hash, direct_equal);

	internal void add_types(SourceFile source, GenericArray<string> names) {
		var copy = new GenericArray<string> ();
		foreach (string name in names) {
			copy.add (name);
		}
		closed_types.insert (source, copy);
	}

	internal GenericArray<string>? record_applications(SourceFile source) {
		return closed_types.lookup (source);
	}

	internal void add(SourceFile source, NativeDeclarationIdentity declaration) {
		var bindings = files.lookup (source);
		if (bindings == null) {
			bindings = new HashTable<string, NativeDeclarationIdentity> (str_hash, str_equal);
			files.insert (source, bindings);
		}
		bindings.insert (declaration.key, declaration);
	}

	internal static string function_key(FunctionSymbol function) {
		string member = function.name_span.text ();
		if (function is ConstructorSymbol) {
			member = "init";
		} else if (function is DestructorSymbol) {
			member = "deinit";
		} else if (function is PropertyGetterSymbol) {
			member = "get:" + ((PropertyGetterSymbol) function).property_symbol.name;
		} else if (function is PropertySetterSymbol) {
			member = "set:" + ((PropertySetterSymbol) function).property_symbol.name;
		}
		var method = function as MethodSymbol;
		if (method != null && method.generic_method_instance != null) {
			member += method.generic_method_instance.arguments.display_suffix (true);
		}
		var receiver = function.implicit_receiver;
		return receiver == null ? "F:" + function.name : "C:" + receiver.semantic_type.instance_type.display_name () + "::" + member;
	}

	internal NativeDeclarationIdentity? lookup(FunctionSymbol function) {
		var lifecycle = function as LifecycleSymbol;
		var source = lifecycle == null ? function.name_span.file : lifecycle.declaring_class.name_span.file;
		return lookup_key (source, function_key (function));
	}

	internal NativeDeclarationIdentity? lookup_key(SourceFile source, string key) {
		var bindings = files.lookup (source);
		return bindings == null ? null : bindings.lookup (key);
	}

	internal static NativeDeclarationSignature signature(NativeDeclarationIdentity identity, FunctionSymbol function) {
		var types = new GenericArray<SemanticType> ();
		var contracts = new GenericArray<PointerParameterContract> ();
		var heaps = new bool[function.parameters.length];
		var nonnull = new bool[function.parameters.length];
		var records = new int[function.parameters.length];
		for (int p = 0; p < function.parameters.length; p++) {
			var parameter = function.parameters[p];
			types.add (parameter.semantic_type);
			contracts.add (parameter.pointer_contract);
			heaps[p] = parameter.heap_object;
			nonnull[p] = parameter.requires_nonnull;
			records[p] = parameter.struct_value_contract == null ? -1 : (int) parameter.struct_value_contract.mode;
		}
		var receiver = function.implicit_receiver;
		return new NativeDeclarationSignature (identity, function.return_type, function.result_contract,
			function.heap_result, function.nonnull_result, receiver == null ? null : receiver.semantic_type.instance_type,
			function.throws_type, types, contracts, heaps, nonnull, records,
			function.struct_result_contract == null ? -1 : (int) function.struct_result_contract.mode, null, function.async_body);
	}
}
}
