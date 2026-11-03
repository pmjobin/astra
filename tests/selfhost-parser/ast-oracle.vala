// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
class AstOracle : Object {
	GenericArray<SyntaxNode> queue = new GenericArray<SyntaxNode>();
	GenericArray<SourceFile> sources = new GenericArray<SourceFile>();
	HashTable<SyntaxNode, int> numbers = new HashTable<SyntaxNode, int>(direct_hash, direct_equal);
	public StringBuilder output = new StringBuilder();
	int reference(SyntaxNode? node) {
		if (node == null)
			return 0;
		int ordinal = numbers.lookup(node);
		if (ordinal == 0) {
			queue.add(node);
			ordinal = queue.length;
			numbers.insert(node, ordinal);
		}
		return ordinal;
	}

	void source_line(SourceFile source, int ordinal) {
		output.append_printf("S %d %s %d %d\n", ordinal, hex(source.path), source.length, source.native_interface?1:0);
	}

	int source_number(SourceFile source) {
		for (int i = 0; i < sources.length; i++) {
			if (sources[i] == source)
				return i + 1;
		}
		sources.add(source);
		source_line(source, sources.length);
		return sources.length;
	}

	void edge(string name, string expected, SyntaxNode? node) {
		output.append_printf("E %s %s %d\n", name, expected, reference(node));
	}

	void boolean(string name, bool value) {
		output.append_printf("B %s %d\n", name, value?1:0);
	}

	void integer(string name, int value) {
		output.append_printf("I %s %d\n", name, value);
	}

	void text(string name, string value) {
		output.append_printf("X %s %s\n", name, hex(value));
	}

	void concurrency(string name, ConcurrencyPolicy? policy) {
		if (policy == null) {
			output.append_printf("C %s -\n", name);
			return;
		}
		output.append_printf("C %s %d %d\n", name, (int)policy.kinds, (int)policy.identity);
	}

	void token(string name, Token? token) {
		if (token == null) {
			output.append_printf("T %s -\n", name);
			return;
		}
		int source = source_number(token.span.file);
		output.append_printf("T %s %s %d %d %d %s %s\n", name, token.kind.to_string().substring("ASTRA_SYNTAX_TOKEN_KIND_".length), source, token.span.start, token.span.end, hex(token.spelling()), token.text_payload == null?"":token.text_payload.hex());
	}

	void fields(SyntaxNode node) {
		if (node is ConstructorInitializerSyntax) {
			var value = (ConstructorInitializerSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			boolean("signal_emission", value.signal_emission);
			output.append_printf("L qualifier_arguments %d\n", value.qualifier_arguments.length);
			foreach (var entry in value.qualifier_arguments) {
				edge("qualifier_arguments", "TypeNameSyntax", entry);
			}
			output.append_printf("L type_arguments %d\n", value.type_arguments.length);
			foreach (var entry in value.type_arguments) {
				edge("type_arguments", "TypeNameSyntax", entry);
			}
			edge("receiver_place", "ExpressionSyntax", value.receiver_place);
			token("receiver", value.receiver);
			token("member_operator", value.member_operator);
			token("identifier", value.identifier);
			token("open_paren", value.open_paren);
			output.append_printf("L arguments %d\n", value.arguments.length);
			foreach (var entry in value.arguments) {
				edge("arguments", "ExpressionSyntax", entry);
			}
			output.append_printf("L commas %d\n", value.commas.length);
			foreach (var entry in value.commas) {
				token("commas", entry);
			}
			token("close_paren", value.close_paren);
			return;
		}
		if (node is VectorExtractExpressionSyntax) {
			var value = (VectorExtractExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("container", "ExpressionSyntax", value.container);
			edge("subscript", "ExpressionSyntax", value.subscript);
			token("close", value.close);
			edge("vector", "ExpressionSyntax", value.vector);
			token("open_bracket", value.open_bracket);
			token("index", value.index);
			token("close_bracket", value.close_bracket);
			return;
		}
		if (node is AddressOfExpressionSyntax) {
			var value = (AddressOfExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("ampersand", value.ampersand);
			token("identifier", value.identifier);
			return;
		}
		if (node is ArrayInitializerSyntax) {
			var value = (ArrayInitializerSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			output.append_printf("L elements %d\n", value.elements.length);
			foreach (var entry in value.elements) {
				edge("elements", "ExpressionSyntax", entry);
			}
			return;
		}
		if (node is ArrayStructInitializerSyntax) {
			var value = (ArrayStructInitializerSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("initializer", "StructInitializerSyntax", value.initializer);
			return;
		}
		if (node is ArrayTypeSyntax) {
			var value = (ArrayTypeSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("namespace_qualifier", value.namespace_qualifier);
			token("identifier", value.identifier);
			output.append_printf("L stars %d\n", value.stars.length);
			foreach (var entry in value.stars) {
				token("stars", entry);
			}
			edge("element_type", "TypeNameSyntax", value.element_type);
			edge("extent", "ExpressionSyntax", value.extent);
			return;
		}
		if (node is AssignmentStatementSyntax) {
			var value = (AssignmentStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("name", value.name);
			token("equals_token", value.equals_token);
			edge("expression", "ExpressionSyntax", value.expression);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is AwaitExpressionSyntax) {
			var value = (AwaitExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			edge("operation", "ExpressionSyntax", value.operation);
			return;
		}
		if (node is AwaitStatementSyntax) {
			var value = (AwaitStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("expression", "AwaitExpressionSyntax", value.expression);
			return;
		}
		if (node is BinaryExpressionSyntax) {
			var value = (BinaryExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("left", "ExpressionSyntax", value.left);
			token("operator_token", value.operator_token);
			edge("right", "ExpressionSyntax", value.right);
			return;
		}
		if (node is BlockStatementSyntax) {
			var value = (BlockStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("open_brace", value.open_brace);
			output.append_printf("L statements %d\n", value.statements.length);
			foreach (var entry in value.statements) {
				edge("statements", "StatementSyntax", entry);
			}
			token("close_brace", value.close_brace);
			return;
		}
		if (node is BooleanLiteralExpressionSyntax) {
			var value = (BooleanLiteralExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("literal", value.literal);
			return;
		}
		if (node is BreakStatementSyntax) {
			var value = (BreakStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is BufferAllocationSyntax) {
			var value = (BufferAllocationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("allocation_context", "ExpressionSyntax", value.allocation_context);
			edge("element_type", "TypeNameSyntax", value.element_type);
			edge("count", "ExpressionSyntax", value.count);
			edge("failure_call", "ExpressionSyntax", value.failure_call);
			return;
		}
		if (node is CallExpressionSyntax) {
			var value = (CallExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			boolean("signal_emission", value.signal_emission);
			output.append_printf("L qualifier_arguments %d\n", value.qualifier_arguments.length);
			foreach (var entry in value.qualifier_arguments) {
				edge("qualifier_arguments", "TypeNameSyntax", entry);
			}
			output.append_printf("L type_arguments %d\n", value.type_arguments.length);
			foreach (var entry in value.type_arguments) {
				edge("type_arguments", "TypeNameSyntax", entry);
			}
			edge("receiver_place", "ExpressionSyntax", value.receiver_place);
			token("receiver", value.receiver);
			token("member_operator", value.member_operator);
			token("identifier", value.identifier);
			token("open_paren", value.open_paren);
			output.append_printf("L arguments %d\n", value.arguments.length);
			foreach (var entry in value.arguments) {
				edge("arguments", "ExpressionSyntax", entry);
			}
			output.append_printf("L commas %d\n", value.commas.length);
			foreach (var entry in value.commas) {
				token("commas", entry);
			}
			token("close_paren", value.close_paren);
			return;
		}
		if (node is CallStatementSyntax) {
			var value = (CallStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("call", "CallExpressionSyntax", value.call);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is CallableChannelTypeSyntax) {
			var value = (CallableChannelTypeSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("namespace_qualifier", value.namespace_qualifier);
			token("identifier", value.identifier);
			output.append_printf("L stars %d\n", value.stars.length);
			foreach (var entry in value.stars) {
				token("stars", entry);
			}
			token("keyword", value.keyword);
			edge("underlying", "TypeNameSyntax", value.underlying);
			return;
		}
		if (node is ClassDeclarationSyntax) {
			var value = (ClassDeclarationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			concurrency("concurrency_policy", value.concurrency_policy);
			if (value.allocator == null) {
				output.append("L allocator -1\n");
			} else{
				output.append_printf("L allocator %d\n", value.allocator.length);
				foreach (var entry in value.allocator) {
					edge("allocator", "CCodeEntrySyntax", entry);
				}
			}
			if (value.alignment == null) {
				output.append("L alignment -1\n");
			} else{
				output.append_printf("L alignment %d\n", value.alignment.length);
				foreach (var entry in value.alignment) {
					edge("alignment", "CCodeEntrySyntax", entry);
				}
			}
			if (value.representation == null) {
				output.append("L representation -1\n");
			} else{
				output.append_printf("L representation %d\n", value.representation.length);
				foreach (var entry in value.representation) {
					edge("representation", "CCodeEntrySyntax", entry);
				}
			}
			output.append_printf("L members %d\n", value.members.length);
			foreach (var entry in value.members) {
				edge("members", "SyntaxNode", entry);
			}
			output.append_printf("L methods %d\n", value.methods.length);
			foreach (var entry in value.methods) {
				edge("methods", "FunctionDeclarationSyntax", entry);
			}
			token("keyword", value.keyword);
			token("name", value.name);
			token("open_brace", value.open_brace);
			output.append_printf("L fields %d\n", value.fields.length);
			foreach (var entry in value.fields) {
				edge("fields", "StructFieldDeclarationSyntax", entry);
			}
			token("close_brace", value.close_brace);
			output.append_printf("L where_clauses %d\n", value.where_clauses.length);
			foreach (var entry in value.where_clauses) {
				edge("where_clauses", "WhereClauseSyntax", entry);
			}
			edge("foreign_import", "ForeignPolicySyntax", value.foreign_import);
			edge("foreign_export", "ForeignPolicySyntax", value.foreign_export);
			edge("com_export", "ForeignPolicySyntax", value.com_export);
			edge("gobject_export", "ForeignPolicySyntax", value.gobject_export);
			boolean("is_interface", value.is_interface);
			output.append_printf("L type_parameters %d\n", value.type_parameters.length);
			foreach (var entry in value.type_parameters) {
				token("type_parameters", entry);
			}
			boolean("exact_heap_class", value.exact_heap_class);
			edge("parent_class", "TypeNameSyntax", value.parent_class);
			token("exception_root", value.exception_root);
			return;
		}
		if (node is ComparisonChainSyntax) {
			var value = (ComparisonChainSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			output.append_printf("L operands %d\n", value.operands.length);
			foreach (var entry in value.operands) {
				edge("operands", "ExpressionSyntax", entry);
			}
			output.append_printf("L operators %d\n", value.operators.length);
			foreach (var entry in value.operators) {
				token("operators", entry);
			}
			return;
		}
		if (node is ConstantDeclarationSyntax) {
			var value = (ConstantDeclarationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("type_name", "TypeNameSyntax", value.type_name);
			token("name", value.name);
			edge("initializer", "ExpressionSyntax", value.initializer);
			return;
		}
		if (node is ContinueStatementSyntax) {
			var value = (ContinueStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is ConversionExpressionSyntax) {
			var value = (ConversionExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("operand", "ExpressionSyntax", value.operand);
			token("keyword", value.keyword);
			edge("destination", "TypeNameSyntax", value.destination);
			return;
		}
		if (node is DereferenceAssignmentSyntax) {
			var value = (DereferenceAssignmentSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("target", "DereferenceExpressionSyntax", value.target);
			edge("expression", "ExpressionSyntax", value.expression);
			return;
		}
		if (node is DereferenceExpressionSyntax) {
			var value = (DereferenceExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("star", value.star);
			edge("pointer", "ExpressionSyntax", value.pointer);
			return;
		}
		if (node is DspExpressionSyntax) {
			var value = (DspExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("open_paren", value.open_paren);
			edge("first", "ExpressionSyntax", value.first);
			edge("second", "ExpressionSyntax", value.second);
			edge("destination", "TypeNameSyntax", value.destination);
			output.append_printf("L commas %d\n", value.commas.length);
			foreach (var entry in value.commas) {
				token("commas", entry);
			}
			token("close_paren", value.close_paren);
			return;
		}
		if (node is FieldAccessExpressionSyntax) {
			var value = (FieldAccessExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("identifier", value.identifier);
			token("dot", value.dot);
			token("field_name", value.field_name);
			edge("aggregate", "ExpressionSyntax", value.aggregate);
			return;
		}
		if (node is FieldAssignmentStatementSyntax) {
			var value = (FieldAssignmentStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("target", "FieldAccessExpressionSyntax", value.target);
			token("equals_token", value.equals_token);
			edge("expression", "ExpressionSyntax", value.expression);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is FloatLiteralExpressionSyntax) {
			var value = (FloatLiteralExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("literal", value.literal);
			return;
		}
		if (node is ForStatementSyntax) {
			var value = (ForStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			edge("initializer", "StatementSyntax", value.initializer);
			edge("condition", "ExpressionSyntax", value.condition);
			edge("step", "StatementSyntax", value.step);
			edge("body", "BlockStatementSyntax", value.body);
			return;
		}
		if (node is ForeachStatementSyntax) {
			var value = (ForeachStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("binding", value.binding);
			edge("collection", "ExpressionSyntax", value.collection);
			edge("body", "BlockStatementSyntax", value.body);
			return;
		}
		if (node is GenericTypeApplicationSyntax) {
			var value = (GenericTypeApplicationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("namespace_qualifier", value.namespace_qualifier);
			token("identifier", value.identifier);
			output.append_printf("L stars %d\n", value.stars.length);
			foreach (var entry in value.stars) {
				token("stars", entry);
			}
			output.append_printf("L type_arguments %d\n", value.type_arguments.length);
			foreach (var entry in value.type_arguments) {
				edge("type_arguments", "TypeNameSyntax", entry);
			}
			return;
		}
		if (node is HeapObjectConstructionSyntax) {
			var value = (HeapObjectConstructionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("allocation_context", "ExpressionSyntax", value.allocation_context);
			boolean("fallible", value.fallible);
			edge("class_name", "TypeNameSyntax", value.class_name);
			output.append_printf("L arguments %d\n", value.arguments.length);
			foreach (var entry in value.arguments) {
				edge("arguments", "ExpressionSyntax", entry);
			}
			return;
		}
		if (node is IfStatementSyntax) {
			var value = (IfStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("open_paren", value.open_paren);
			edge("condition", "ExpressionSyntax", value.condition);
			token("close_paren", value.close_paren);
			edge("then_body", "BlockStatementSyntax", value.then_body);
			token("else_keyword", value.else_keyword);
			edge("else_body", "BlockStatementSyntax", value.else_body);
			return;
		}
		if (node is IndexExpressionSyntax) {
			var value = (IndexExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("container", "ExpressionSyntax", value.container);
			edge("subscript", "ExpressionSyntax", value.subscript);
			token("close", value.close);
			return;
		}
		if (node is IndexedAssignmentSyntax) {
			var value = (IndexedAssignmentSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("target", "IndexExpressionSyntax", value.target);
			edge("expression", "ExpressionSyntax", value.expression);
			return;
		}
		if (node is InferredLocalDeclarationSyntax) {
			var value = (InferredLocalDeclarationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("name", value.name);
			token("equals_token", value.equals_token);
			edge("initializer", "ExpressionSyntax", value.initializer);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is IntegerLiteralExpressionSyntax) {
			var value = (IntegerLiteralExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("literal", value.literal);
			return;
		}
		if (node is LifecycleDeclarationSyntax) {
			var value = (LifecycleDeclarationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			boolean("is_signal", value.is_signal);
			edge("foreign_policy", "ForeignPolicySyntax", value.foreign_policy);
			boolean("utf8_factory", value.utf8_factory);
			token("async_keyword", value.async_keyword);
			integer("dispatch", (int)value.dispatch);
			edge("throws_class", "TypeNameSyntax", value.throws_class);
			if (value.ccode == null) {
				output.append("L ccode -1\n");
			} else{
				output.append_printf("L ccode %d\n", value.ccode.length);
				foreach (var entry in value.ccode) {
					edge("ccode", "CCodeEntrySyntax", entry);
				}
			}
			if (value.floating_point == null) {
				output.append("L floating_point -1\n");
			} else{
				output.append_printf("L floating_point %d\n", value.floating_point.length);
				foreach (var entry in value.floating_point) {
					edge("floating_point", "CCodeEntrySyntax", entry);
				}
			}
			output.append_printf("L where_clauses %d\n", value.where_clauses.length);
			foreach (var entry in value.where_clauses) {
				edge("where_clauses", "WhereClauseSyntax", entry);
			}
			output.append_printf("L type_parameters %d\n", value.type_parameters.length);
			foreach (var entry in value.type_parameters) {
				token("type_parameters", entry);
			}
			token("owned_keyword", value.owned_keyword);
			edge("return_type", "TypeNameSyntax", value.return_type);
			token("name", value.name);
			token("open_paren", value.open_paren);
			output.append_printf("L parameters %d\n", value.parameters.length);
			foreach (var entry in value.parameters) {
				edge("parameters", "ParameterSyntax", entry);
			}
			output.append_printf("L commas %d\n", value.commas.length);
			foreach (var entry in value.commas) {
				token("commas", entry);
			}
			token("close_paren", value.close_paren);
			edge("body", "BlockStatementSyntax", value.body);
			token("extern_keyword", value.extern_keyword);
			token("export_keyword", value.export_keyword);
			token("abi_identifier", value.abi_identifier);
			token("semicolon", value.semicolon);
			if (value.base_arguments == null) {
				output.append("L base_arguments -1\n");
			} else{
				output.append_printf("L base_arguments %d\n", value.base_arguments.length);
				foreach (var entry in value.base_arguments) {
					edge("base_arguments", "ExpressionSyntax", entry);
				}
			}
			return;
		}
		if (node is LocalDeclarationSyntax) {
			var value = (LocalDeclarationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("owned_keyword", value.owned_keyword);
			edge("type_name", "TypeNameSyntax", value.type_name);
			token("name", value.name);
			token("equals_token", value.equals_token);
			edge("initializer", "ExpressionSyntax", value.initializer);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is MatchStatementSyntax) {
			var value = (MatchStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("scrutinee", "ExpressionSyntax", value.scrutinee);
			output.append_printf("L arms %d\n", value.arms.length);
			foreach (var entry in value.arms) {
				edge("arms", "EnumArmSyntax", entry);
			}
			return;
		}
		if (node is MoveExpressionSyntax) {
			var value = (MoveExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("source", value.source);
			output.append_printf("L fields %d\n", value.fields.length);
			foreach (var entry in value.fields) {
				token("fields", entry);
			}
			return;
		}
		if (node is NameExpressionSyntax) {
			var value = (NameExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("identifier", value.identifier);
			return;
		}
		if (node is NonNullTypeSyntax) {
			var value = (NonNullTypeSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("namespace_qualifier", value.namespace_qualifier);
			token("identifier", value.identifier);
			output.append_printf("L stars %d\n", value.stars.length);
			foreach (var entry in value.stars) {
				token("stars", entry);
			}
			token("keyword", value.keyword);
			edge("underlying", "TypeNameSyntax", value.underlying);
			return;
		}
		if (node is NullPointerExpressionSyntax) {
			var value = (NullPointerExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			return;
		}
		if (node is OwnerSlotsTypeSyntax) {
			var value = (OwnerSlotsTypeSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("namespace_qualifier", value.namespace_qualifier);
			token("identifier", value.identifier);
			output.append_printf("L stars %d\n", value.stars.length);
			foreach (var entry in value.stars) {
				token("stars", entry);
			}
			edge("element", "TypeNameSyntax", value.element);
			token("marker", value.marker);
			token("close", value.close);
			return;
		}
		if (node is ParenthesizedExpressionSyntax) {
			var value = (ParenthesizedExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("open_paren", value.open_paren);
			edge("expression", "ExpressionSyntax", value.expression);
			token("close_paren", value.close_paren);
			return;
		}
		if (node is PointerTypeSyntax) {
			var value = (PointerTypeSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("namespace_qualifier", value.namespace_qualifier);
			token("identifier", value.identifier);
			output.append_printf("L stars %d\n", value.stars.length);
			foreach (var entry in value.stars) {
				token("stars", entry);
			}
			edge("pointee", "TypeNameSyntax", value.pointee);
			token("star", value.star);
			return;
		}
		if (node is PrefixExpressionSyntax) {
			var value = (PrefixExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("operator_token", value.operator_token);
			edge("operand", "ExpressionSyntax", value.operand);
			return;
		}
		if (node is ReleaseStatementSyntax) {
			var value = (ReleaseStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("owner", value.owner);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is ReturnStatementSyntax) {
			var value = (ReturnStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			edge("expression", "ExpressionSyntax", value.expression);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is SharedTypeSyntax) {
			var value = (SharedTypeSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("namespace_qualifier", value.namespace_qualifier);
			token("identifier", value.identifier);
			output.append_printf("L stars %d\n", value.stars.length);
			foreach (var entry in value.stars) {
				token("stars", entry);
			}
			token("keyword", value.keyword);
			edge("payload", "TypeNameSyntax", value.payload);
			return;
		}
		if (node is ShortCircuitExpressionSyntax) {
			var value = (ShortCircuitExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("left", "ExpressionSyntax", value.left);
			token("operator_token", value.operator_token);
			edge("right", "ExpressionSyntax", value.right);
			return;
		}
		if (node is SliceTypeSyntax) {
			var value = (SliceTypeSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("namespace_qualifier", value.namespace_qualifier);
			token("identifier", value.identifier);
			output.append_printf("L stars %d\n", value.stars.length);
			foreach (var entry in value.stars) {
				token("stars", entry);
			}
			edge("element_type", "TypeNameSyntax", value.element_type);
			return;
		}
		if (node is StructDeclarationSyntax) {
			var value = (StructDeclarationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			concurrency("concurrency_policy", value.concurrency_policy);
			if (value.allocator == null) {
				output.append("L allocator -1\n");
			} else{
				output.append_printf("L allocator %d\n", value.allocator.length);
				foreach (var entry in value.allocator) {
					edge("allocator", "CCodeEntrySyntax", entry);
				}
			}
			if (value.alignment == null) {
				output.append("L alignment -1\n");
			} else{
				output.append_printf("L alignment %d\n", value.alignment.length);
				foreach (var entry in value.alignment) {
					edge("alignment", "CCodeEntrySyntax", entry);
				}
			}
			if (value.representation == null) {
				output.append("L representation -1\n");
			} else{
				output.append_printf("L representation %d\n", value.representation.length);
				foreach (var entry in value.representation) {
					edge("representation", "CCodeEntrySyntax", entry);
				}
			}
			output.append_printf("L members %d\n", value.members.length);
			foreach (var entry in value.members) {
				edge("members", "SyntaxNode", entry);
			}
			output.append_printf("L methods %d\n", value.methods.length);
			foreach (var entry in value.methods) {
				edge("methods", "FunctionDeclarationSyntax", entry);
			}
			token("keyword", value.keyword);
			token("name", value.name);
			token("open_brace", value.open_brace);
			output.append_printf("L fields %d\n", value.fields.length);
			foreach (var entry in value.fields) {
				edge("fields", "StructFieldDeclarationSyntax", entry);
			}
			token("close_brace", value.close_brace);
			output.append_printf("L where_clauses %d\n", value.where_clauses.length);
			foreach (var entry in value.where_clauses) {
				edge("where_clauses", "WhereClauseSyntax", entry);
			}
			output.append_printf("L type_parameters %d\n", value.type_parameters.length);
			foreach (var entry in value.type_parameters) {
				token("type_parameters", entry);
			}
			return;
		}
		if (node is StructLocalDeclarationSyntax) {
			var value = (StructLocalDeclarationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("owned_keyword", value.owned_keyword);
			edge("type_name", "TypeNameSyntax", value.type_name);
			token("name", value.name);
			token("equals_token", value.equals_token);
			edge("initializer", "StructInitializerSyntax", value.initializer);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is SwapStatementSyntax) {
			var value = (SwapStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("left", "ExpressionSyntax", value.left);
			edge("right", "ExpressionSyntax", value.right);
			return;
		}
		if (node is TextLiteralExpressionSyntax) {
			var value = (TextLiteralExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("token", value.token);
			return;
		}
		if (node is TextMemberExpressionSyntax) {
			var value = (TextMemberExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("receiver", "ExpressionSyntax", value.receiver);
			token("member", value.member);
			return;
		}
		if (node is ThrowStatementSyntax) {
			var value = (ThrowStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("expression", "ExpressionSyntax", value.expression);
			return;
		}
		if (node is TryStatementSyntax) {
			var value = (TryStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("body", "BlockStatementSyntax", value.body);
			output.append_printf("L catches %d\n", value.catches.length);
			foreach (var entry in value.catches) {
				edge("catches", "CatchClauseSyntax", entry);
			}
			return;
		}
		if (node is Utf8FactoryExpressionSyntax) {
			var value = (Utf8FactoryExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			boolean("validates", value.validates);
			token("input", value.input);
			return;
		}
		if (node is VectorDotExpressionSyntax) {
			var value = (VectorDotExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("open_paren", value.open_paren);
			output.append_printf("L operands %d\n", value.operands.length);
			foreach (var entry in value.operands) {
				edge("operands", "ExpressionSyntax", entry);
			}
			edge("destination", "TypeNameSyntax", value.destination);
			output.append_printf("L commas %d\n", value.commas.length);
			foreach (var entry in value.commas) {
				token("commas", entry);
			}
			token("close_paren", value.close_paren);
			return;
		}
		if (node is VectorInitializerSyntax) {
			var value = (VectorInitializerSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("open_brace", value.open_brace);
			output.append_printf("L lanes %d\n", value.lanes.length);
			foreach (var entry in value.lanes) {
				edge("lanes", "ExpressionSyntax", entry);
			}
			output.append_printf("L commas %d\n", value.commas.length);
			foreach (var entry in value.commas) {
				token("commas", entry);
			}
			token("close_brace", value.close_brace);
			return;
		}
		if (node is VectorPrimitiveExpressionSyntax) {
			var value = (VectorPrimitiveExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("open_paren", value.open_paren);
			output.append_printf("L operands %d\n", value.operands.length);
			foreach (var entry in value.operands) {
				edge("operands", "ExpressionSyntax", entry);
			}
			output.append_printf("L indices %d\n", value.indices.length);
			foreach (var entry in value.indices) {
				token("indices", entry);
			}
			output.append_printf("L commas %d\n", value.commas.length);
			foreach (var entry in value.commas) {
				token("commas", entry);
			}
			token("close_paren", value.close_paren);
			return;
		}
		if (node is VectorReductionExpressionSyntax) {
			var value = (VectorReductionExpressionSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("open_paren", value.open_paren);
			edge("operand", "ExpressionSyntax", value.operand);
			token("close_paren", value.close_paren);
			return;
		}
		if (node is VectorTypeSyntax) {
			var value = (VectorTypeSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("namespace_qualifier", value.namespace_qualifier);
			token("identifier", value.identifier);
			output.append_printf("L stars %d\n", value.stars.length);
			foreach (var entry in value.stars) {
				token("stars", entry);
			}
			edge("element_type", "TypeNameSyntax", value.element_type);
			token("open_angle", value.open_angle);
			token("lane_count", value.lane_count);
			token("close_angle", value.close_angle);
			return;
		}
		if (node is WhileStatementSyntax) {
			var value = (WhileStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("open_paren", value.open_paren);
			edge("condition", "ExpressionSyntax", value.condition);
			token("close_paren", value.close_paren);
			edge("body", "BlockStatementSyntax", value.body);
			return;
		}
		if (node is WithStatementSyntax) {
			var value = (WithStatementSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("receiver", value.receiver);
			edge("initializer", "InferredLocalDeclarationSyntax", value.initializer);
			edge("body", "BlockStatementSyntax", value.body);
			return;
		}
		if (node is AsyncRuntimeSyntax) {
			var value = (AsyncRuntimeSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("provider", value.provider);
			token("name", value.name);
			edge("error", "TypeNameSyntax", value.error);
			edge("status", "TypeNameSyntax", value.status);
			return;
		}
		if (node is CCodeEntrySyntax) {
			var value = (CCodeEntrySyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("key", value.key);
			token("value", value.value);
			text("decoded_value", value.decoded_value);
			return;
		}
		if (node is CallerInformationSyntax) {
			var value = (CallerInformationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("name", value.name);
			token("target", value.target);
			return;
		}
		if (node is CatchClauseSyntax) {
			var value = (CatchClauseSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("class_name", "TypeNameSyntax", value.class_name);
			token("binding", value.binding);
			edge("body", "BlockStatementSyntax", value.body);
			return;
		}
		if (node is ComImportSyntax) {
			var value = (ComImportSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("declaration", "ClassDeclarationSyntax", value.declaration);
			token("name", value.name);
			edge("policy", "ForeignPolicySyntax", value.policy);
			return;
		}
		if (node is CompilationUnitSyntax) {
			var value = (CompilationUnitSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			output.append_printf("L c_classes %d\n", value.c_classes.length);
			foreach (var entry in value.c_classes) {
				edge("c_classes", "ClassDeclarationSyntax", entry);
			}
			output.append_printf("L com_interfaces %d\n", value.com_interfaces.length);
			foreach (var entry in value.com_interfaces) {
				edge("com_interfaces", "ComImportSyntax", entry);
			}
			token("namespace_name", value.namespace_name);
			output.append_printf("L imports %d\n", value.imports.length);
			foreach (var entry in value.imports) {
				token("imports", entry);
			}
			output.append_printf("L type_applications %d\n", value.type_applications.length);
			foreach (var entry in value.type_applications) {
				edge("type_applications", "GenericTypeApplicationSyntax", entry);
			}
			output.append_printf("L async_runtimes %d\n", value.async_runtimes.length);
			foreach (var entry in value.async_runtimes) {
				edge("async_runtimes", "AsyncRuntimeSyntax", entry);
			}
			output.append_printf("L enums %d\n", value.enums.length);
			foreach (var entry in value.enums) {
				edge("enums", "EnumDeclarationSyntax", entry);
			}
			output.append_printf("L constants %d\n", value.constants.length);
			foreach (var entry in value.constants) {
				edge("constants", "ConstantDeclarationSyntax", entry);
			}
			output.append_printf("L classes %d\n", value.classes.length);
			foreach (var entry in value.classes) {
				edge("classes", "ClassDeclarationSyntax", entry);
			}
			output.append_printf("L functions %d\n", value.functions.length);
			foreach (var entry in value.functions) {
				edge("functions", "FunctionDeclarationSyntax", entry);
			}
			output.append_printf("L structs %d\n", value.structs.length);
			foreach (var entry in value.structs) {
				edge("structs", "StructDeclarationSyntax", entry);
			}
			token("end_of_file", value.end_of_file);
			return;
		}
		if (node is EnumArmSyntax) {
			var value = (EnumArmSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			output.append_printf("L type_arguments %d\n", value.type_arguments.length);
			foreach (var entry in value.type_arguments) {
				edge("type_arguments", "TypeNameSyntax", entry);
			}
			token("qualifier", value.qualifier);
			token("variant", value.variant);
			output.append_printf("L bindings %d\n", value.bindings.length);
			foreach (var entry in value.bindings) {
				edge("bindings", "EnumBindingSyntax", entry);
			}
			edge("body", "BlockStatementSyntax", value.body);
			return;
		}
		if (node is EnumBindingSyntax) {
			var value = (EnumBindingSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("field", value.field);
			token("binding", value.binding);
			return;
		}
		if (node is EnumDeclarationSyntax) {
			var value = (EnumDeclarationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			output.append_printf("L type_parameters %d\n", value.type_parameters.length);
			foreach (var entry in value.type_parameters) {
				token("type_parameters", entry);
			}
			token("name", value.name);
			output.append_printf("L variants %d\n", value.variants.length);
			foreach (var entry in value.variants) {
				edge("variants", "EnumVariantSyntax", entry);
			}
			return;
		}
		if (node is EnumPayloadSyntax) {
			var value = (EnumPayloadSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("owned_keyword", value.owned_keyword);
			edge("type_name", "TypeNameSyntax", value.type_name);
			token("name", value.name);
			return;
		}
		if (node is EnumVariantSyntax) {
			var value = (EnumVariantSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("name", value.name);
			output.append_printf("L fields %d\n", value.fields.length);
			foreach (var entry in value.fields) {
				edge("fields", "EnumPayloadSyntax", entry);
			}
			return;
		}
		if (node is FieldInitializerSyntax) {
			var value = (FieldInitializerSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("name", value.name);
			token("equals_token", value.equals_token);
			edge("expression", "ExpressionSyntax", value.expression);
			edge("initializer", "StructInitializerSyntax", value.initializer);
			return;
		}
		if (node is ForeignPolicySyntax) {
			var value = (ForeignPolicySyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			integer("kind", (int)value.kind);
			token("name", value.name);
			output.append_printf("L entries %d\n", value.entries.length);
			foreach (var entry in value.entries) {
				edge("entries", "CCodeEntrySyntax", entry);
			}
			return;
		}
		if (node is FunctionDeclarationSyntax) {
			var value = (FunctionDeclarationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			boolean("is_signal", value.is_signal);
			edge("foreign_policy", "ForeignPolicySyntax", value.foreign_policy);
			boolean("utf8_factory", value.utf8_factory);
			token("async_keyword", value.async_keyword);
			integer("dispatch", (int)value.dispatch);
			edge("throws_class", "TypeNameSyntax", value.throws_class);
			if (value.ccode == null) {
				output.append("L ccode -1\n");
			} else{
				output.append_printf("L ccode %d\n", value.ccode.length);
				foreach (var entry in value.ccode) {
					edge("ccode", "CCodeEntrySyntax", entry);
				}
			}
			if (value.floating_point == null) {
				output.append("L floating_point -1\n");
			} else{
				output.append_printf("L floating_point %d\n", value.floating_point.length);
				foreach (var entry in value.floating_point) {
					edge("floating_point", "CCodeEntrySyntax", entry);
				}
			}
			output.append_printf("L where_clauses %d\n", value.where_clauses.length);
			foreach (var entry in value.where_clauses) {
				edge("where_clauses", "WhereClauseSyntax", entry);
			}
			output.append_printf("L type_parameters %d\n", value.type_parameters.length);
			foreach (var entry in value.type_parameters) {
				token("type_parameters", entry);
			}
			token("owned_keyword", value.owned_keyword);
			edge("return_type", "TypeNameSyntax", value.return_type);
			token("name", value.name);
			token("open_paren", value.open_paren);
			output.append_printf("L parameters %d\n", value.parameters.length);
			foreach (var entry in value.parameters) {
				edge("parameters", "ParameterSyntax", entry);
			}
			output.append_printf("L commas %d\n", value.commas.length);
			foreach (var entry in value.commas) {
				token("commas", entry);
			}
			token("close_paren", value.close_paren);
			edge("body", "BlockStatementSyntax", value.body);
			token("extern_keyword", value.extern_keyword);
			token("export_keyword", value.export_keyword);
			token("abi_identifier", value.abi_identifier);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is ParameterSyntax) {
			var value = (ParameterSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			edge("caller_information", "CallerInformationSyntax", value.caller_information);
			edge("type_name", "TypeNameSyntax", value.type_name);
			token("name", value.name);
			token("borrowed_keyword", value.borrowed_keyword);
			token("owned_keyword", value.owned_keyword);
			return;
		}
		if (node is PropertyAccessorSyntax) {
			var value = (PropertyAccessorSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			edge("parameter", "ParameterSyntax", value.parameter);
			edge("body", "BlockStatementSyntax", value.body);
			return;
		}
		if (node is PropertyDeclarationSyntax) {
			var value = (PropertyDeclarationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("owned_keyword", value.owned_keyword);
			edge("factory_syntax", "FunctionDeclarationSyntax", value.factory_syntax);
			boolean("is_borrowed", value.is_borrowed);
			token("lazy_keyword", value.lazy_keyword);
			edge("throws_class", "TypeNameSyntax", value.throws_class);
			integer("dispatch", (int)value.dispatch);
			token("keyword", value.keyword);
			edge("type_name", "TypeNameSyntax", value.type_name);
			token("name", value.name);
			edge("getter", "PropertyAccessorSyntax", value.getter);
			edge("setter", "PropertyAccessorSyntax", value.setter);
			return;
		}
		if (node is StructFieldDeclarationSyntax) {
			var value = (StructFieldDeclarationSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("private_keyword", value.private_keyword);
			token("readonly_keyword", value.readonly_keyword);
			token("owned_keyword", value.owned_keyword);
			edge("type_name", "TypeNameSyntax", value.type_name);
			token("name", value.name);
			token("semicolon", value.semicolon);
			return;
		}
		if (node is StructInitializerSyntax) {
			var value = (StructInitializerSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("open_brace", value.open_brace);
			output.append_printf("L fields %d\n", value.fields.length);
			foreach (var entry in value.fields) {
				edge("fields", "FieldInitializerSyntax", entry);
			}
			output.append_printf("L commas %d\n", value.commas.length);
			foreach (var entry in value.commas) {
				token("commas", entry);
			}
			token("close_brace", value.close_brace);
			return;
		}
		if (node is TypeNameSyntax) {
			var value = (TypeNameSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("namespace_qualifier", value.namespace_qualifier);
			token("identifier", value.identifier);
			output.append_printf("L stars %d\n", value.stars.length);
			foreach (var entry in value.stars) {
				token("stars", entry);
			}
			return;
		}
		if (node is WhereClauseSyntax) {
			var value = (WhereClauseSyntax)node;
			edge("foreign_member", "ForeignPolicySyntax", value.foreign_member);
			boolean("module_internal", value.module_internal);
			output.append_printf("L foreign_channels %d\n", value.foreign_channels.length);
			foreach (var entry in value.foreign_channels) {
				edge("foreign_channels", "ForeignPolicySyntax", entry);
			}
			token("keyword", value.keyword);
			token("type_parameter", value.type_parameter);
			token("colon", value.colon);
			output.append_printf("L capabilities %d\n", value.capabilities.length);
			foreach (var entry in value.capabilities) {
				token("capabilities", entry);
			}
			output.append_printf("L commas %d\n", value.commas.length);
			foreach (var entry in value.commas) {
				token("commas", entry);
			}
			return;
		}
		assert_not_reached();
	}

	public string format(SyntaxProgram program) {
		output.append("astra-ast-projection/1\n");
		foreach (var source in program.sources.files) {
			sources.add(source);
			source_line(source, sources.length);
		}
		foreach (var unit in program.units) {
			edge("unit", "CompilationUnitSyntax", unit);
		}
		for (int i = 0; i < queue.length; i++) {
			var node = queue[i];
			int source = source_number(node.span.file);
			int depth = (node is ExpressionSyntax) ? ((ExpressionSyntax)node).tree_depth : 0;
			output.append_printf("N %d %s %d %d %d %d\n", i + 1, kind_name(node), source, node.span.start, node.span.end, depth);
			fields(node);
		}
		return output.str;
	}

	string kind_name(SyntaxNode node) {
		if (node is ConstructorInitializerSyntax)
			return "ConstructorInitializerSyntax";
		if (node is VectorExtractExpressionSyntax)
			return "VectorExtractExpressionSyntax";
		if (node is AddressOfExpressionSyntax)
			return "AddressOfExpressionSyntax";
		if (node is ArrayInitializerSyntax)
			return "ArrayInitializerSyntax";
		if (node is ArrayStructInitializerSyntax)
			return "ArrayStructInitializerSyntax";
		if (node is ArrayTypeSyntax)
			return "ArrayTypeSyntax";
		if (node is AssignmentStatementSyntax)
			return "AssignmentStatementSyntax";
		if (node is AwaitExpressionSyntax)
			return "AwaitExpressionSyntax";
		if (node is AwaitStatementSyntax)
			return "AwaitStatementSyntax";
		if (node is BinaryExpressionSyntax)
			return "BinaryExpressionSyntax";
		if (node is BlockStatementSyntax)
			return "BlockStatementSyntax";
		if (node is BooleanLiteralExpressionSyntax)
			return "BooleanLiteralExpressionSyntax";
		if (node is BreakStatementSyntax)
			return "BreakStatementSyntax";
		if (node is BufferAllocationSyntax)
			return "BufferAllocationSyntax";
		if (node is CallExpressionSyntax)
			return "CallExpressionSyntax";
		if (node is CallStatementSyntax)
			return "CallStatementSyntax";
		if (node is CallableChannelTypeSyntax)
			return "CallableChannelTypeSyntax";
		if (node is ClassDeclarationSyntax)
			return "ClassDeclarationSyntax";
		if (node is ComparisonChainSyntax)
			return "ComparisonChainSyntax";
		if (node is ConstantDeclarationSyntax)
			return "ConstantDeclarationSyntax";
		if (node is ContinueStatementSyntax)
			return "ContinueStatementSyntax";
		if (node is ConversionExpressionSyntax)
			return "ConversionExpressionSyntax";
		if (node is DereferenceAssignmentSyntax)
			return "DereferenceAssignmentSyntax";
		if (node is DereferenceExpressionSyntax)
			return "DereferenceExpressionSyntax";
		if (node is DspExpressionSyntax)
			return "DspExpressionSyntax";
		if (node is FieldAccessExpressionSyntax)
			return "FieldAccessExpressionSyntax";
		if (node is FieldAssignmentStatementSyntax)
			return "FieldAssignmentStatementSyntax";
		if (node is FloatLiteralExpressionSyntax)
			return "FloatLiteralExpressionSyntax";
		if (node is ForStatementSyntax)
			return "ForStatementSyntax";
		if (node is ForeachStatementSyntax)
			return "ForeachStatementSyntax";
		if (node is GenericTypeApplicationSyntax)
			return "GenericTypeApplicationSyntax";
		if (node is HeapObjectConstructionSyntax)
			return "HeapObjectConstructionSyntax";
		if (node is IfStatementSyntax)
			return "IfStatementSyntax";
		if (node is IndexExpressionSyntax)
			return "IndexExpressionSyntax";
		if (node is IndexedAssignmentSyntax)
			return "IndexedAssignmentSyntax";
		if (node is InferredLocalDeclarationSyntax)
			return "InferredLocalDeclarationSyntax";
		if (node is IntegerLiteralExpressionSyntax)
			return "IntegerLiteralExpressionSyntax";
		if (node is LifecycleDeclarationSyntax)
			return "LifecycleDeclarationSyntax";
		if (node is LocalDeclarationSyntax)
			return "LocalDeclarationSyntax";
		if (node is MatchStatementSyntax)
			return "MatchStatementSyntax";
		if (node is MoveExpressionSyntax)
			return "MoveExpressionSyntax";
		if (node is NameExpressionSyntax)
			return "NameExpressionSyntax";
		if (node is NonNullTypeSyntax)
			return "NonNullTypeSyntax";
		if (node is NullPointerExpressionSyntax)
			return "NullPointerExpressionSyntax";
		if (node is OwnerSlotsTypeSyntax)
			return "OwnerSlotsTypeSyntax";
		if (node is ParenthesizedExpressionSyntax)
			return "ParenthesizedExpressionSyntax";
		if (node is PointerTypeSyntax)
			return "PointerTypeSyntax";
		if (node is PrefixExpressionSyntax)
			return "PrefixExpressionSyntax";
		if (node is ReleaseStatementSyntax)
			return "ReleaseStatementSyntax";
		if (node is ReturnStatementSyntax)
			return "ReturnStatementSyntax";
		if (node is SharedTypeSyntax)
			return "SharedTypeSyntax";
		if (node is ShortCircuitExpressionSyntax)
			return "ShortCircuitExpressionSyntax";
		if (node is SliceTypeSyntax)
			return "SliceTypeSyntax";
		if (node is StructDeclarationSyntax)
			return "StructDeclarationSyntax";
		if (node is StructLocalDeclarationSyntax)
			return "StructLocalDeclarationSyntax";
		if (node is SwapStatementSyntax)
			return "SwapStatementSyntax";
		if (node is TextLiteralExpressionSyntax)
			return "TextLiteralExpressionSyntax";
		if (node is TextMemberExpressionSyntax)
			return "TextMemberExpressionSyntax";
		if (node is ThrowStatementSyntax)
			return "ThrowStatementSyntax";
		if (node is TryStatementSyntax)
			return "TryStatementSyntax";
		if (node is Utf8FactoryExpressionSyntax)
			return "Utf8FactoryExpressionSyntax";
		if (node is VectorDotExpressionSyntax)
			return "VectorDotExpressionSyntax";
		if (node is VectorInitializerSyntax)
			return "VectorInitializerSyntax";
		if (node is VectorPrimitiveExpressionSyntax)
			return "VectorPrimitiveExpressionSyntax";
		if (node is VectorReductionExpressionSyntax)
			return "VectorReductionExpressionSyntax";
		if (node is VectorTypeSyntax)
			return "VectorTypeSyntax";
		if (node is WhileStatementSyntax)
			return "WhileStatementSyntax";
		if (node is WithStatementSyntax)
			return "WithStatementSyntax";
		if (node is AsyncRuntimeSyntax)
			return "AsyncRuntimeSyntax";
		if (node is CCodeEntrySyntax)
			return "CCodeEntrySyntax";
		if (node is CallerInformationSyntax)
			return "CallerInformationSyntax";
		if (node is CatchClauseSyntax)
			return "CatchClauseSyntax";
		if (node is ComImportSyntax)
			return "ComImportSyntax";
		if (node is CompilationUnitSyntax)
			return "CompilationUnitSyntax";
		if (node is EnumArmSyntax)
			return "EnumArmSyntax";
		if (node is EnumBindingSyntax)
			return "EnumBindingSyntax";
		if (node is EnumDeclarationSyntax)
			return "EnumDeclarationSyntax";
		if (node is EnumPayloadSyntax)
			return "EnumPayloadSyntax";
		if (node is EnumVariantSyntax)
			return "EnumVariantSyntax";
		if (node is FieldInitializerSyntax)
			return "FieldInitializerSyntax";
		if (node is ForeignPolicySyntax)
			return "ForeignPolicySyntax";
		if (node is FunctionDeclarationSyntax)
			return "FunctionDeclarationSyntax";
		if (node is ParameterSyntax)
			return "ParameterSyntax";
		if (node is PropertyAccessorSyntax)
			return "PropertyAccessorSyntax";
		if (node is PropertyDeclarationSyntax)
			return "PropertyDeclarationSyntax";
		if (node is StructFieldDeclarationSyntax)
			return "StructFieldDeclarationSyntax";
		if (node is StructInitializerSyntax)
			return "StructInitializerSyntax";
		if (node is TypeNameSyntax)
			return "TypeNameSyntax";
		if (node is WhereClauseSyntax)
			return "WhereClauseSyntax";
		assert_not_reached();
	}

}
