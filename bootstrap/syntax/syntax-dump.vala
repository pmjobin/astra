// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Syntax {
// Internal debugging format; deliberately not a public serialization API.
public class SyntaxDump : Object {
	private StringBuilder output = new StringBuilder ();

	public static string format_program(SyntaxProgram program) {
		if (program.units.length == 1) {
			return format (program.units[0]);
		}
		var output = new StringBuilder ("(program\n");
		foreach (var unit in program.units) {
			output.append ("\t(source \"%s\"\n".printf (unit.span.file.path.escape ()));
			foreach (string line in format (unit).split ("\n")) {
				if (line != "") {
					output.append ("\t\t" + line + "\n");
				}
			}
			output.append ("\t)\n");
		}
		output.append (")\n");
		return output.str;
	}

	public static string format(CompilationUnitSyntax unit) {
		if (unit.com_interfaces.length == 0 && unit.namespace_name == null && unit.imports.length == 0 && unit.async_runtimes.length == 0 && unit.enums.length == 0 && unit.functions.length == 0 && unit.structs.length == 0 && unit.classes.length == 0 && unit.constants.length == 0) {
			return "(unit)\n";
		}
		var dump = new SyntaxDump ();
		dump.line (0, "(unit");
		foreach (var imported in unit.com_interfaces) {
			dump.line (1, "(COMImport " + imported.name.spelling ());
			foreach (var entry in imported.policy.entries) {
				dump.line (2, "(%s \"%s\")".printf (entry.key.spelling (), entry.decoded_value.escape ()));
			}
			if (imported.declaration != null) {
				if (imported.declaration.parent_class != null) {
					dump.line (2, "(base " + imported.declaration.parent_class.spelling () + ")");
				}
				foreach (var member in imported.declaration.members) {
					if (member is FunctionDeclarationSyntax) {
						dump.write_function ((FunctionDeclarationSyntax) member, 2, true);
					} else if (member is PropertyDeclarationSyntax) {
						dump.write_property ((PropertyDeclarationSyntax) member);
					} else {
						var field = (StructFieldDeclarationSyntax) member;
						dump.line (2, "(field (type \"%s\") (name \"%s\"))".printf (field.type_name.spelling (), field.name.spelling ()));
					}
				}
			}
			dump.line (1, ")");
		}
		if (unit.namespace_name != null) {
			dump.line (1, "(namespace " + unit.namespace_name.spelling () + ")");
		}
		foreach (var imported in unit.imports) {
			dump.line (1, "(using " + imported.spelling () + ")");
		}
		foreach (var runtime in unit.async_runtimes) {
			dump.line (1, "(async-runtime %s throws %s returns %s)".printf (runtime.name.spelling (), runtime.error.spelling (), runtime.status.spelling ()));
			if (runtime.provider != null) {
				dump.line (1, "(async-provider %s)".printf (runtime.provider.spelling ()));
			}
		}
		foreach (var definition in unit.enums) {
			if (definition.module_internal) {
				dump.line (1, "(internal-declaration " + definition.name.spelling () + ")");
			}
			dump.line (1, "(enum " + definition.name.spelling ());
			foreach (var variant in definition.variants) {
				dump.line (2, "(variant " + variant.name.spelling ());
				foreach (var field in variant.fields) {
					dump.line (3, "(payload %s %s)".printf (field.type_name.spelling (), field.name.spelling ()));
				}
				dump.line (2, ")");
			}
			dump.line (1, ")");
		}
		foreach (var constant in unit.constants) {
			if (constant.module_internal) {
				dump.line (1, "(internal-declaration " + constant.name.spelling () + ")");
			}
			dump.write_statement (constant, 1);
		}
		foreach (var declaration in unit.native_instances ()) {
			if (declaration.module_internal) {
				dump.line (1, "(internal-declaration " + declaration.name.spelling () + ")");
			}
			dump.line (1, "(%s \"%s\"".printf (declaration.keyword.kind == TokenKind.CLASS ? "class" : "struct", declaration.name.spelling ()));
			var object_class = declaration as ClassDeclarationSyntax;
			if (object_class != null && object_class.foreign_export != null) {
				var policy = object_class.foreign_export;
				dump.line (2, "(policy " + Source.DeclarationPolicyRegistry.spelling (policy.kind) + ")");
				foreach (var entry in policy.entries) {
					dump.line (2, "(foreign-class %s \"%s\")".printf (entry.key.spelling (), entry.decoded_value.escape ()));
				}
			}
			if (object_class != null && object_class.com_export != null) {
				var policy = object_class.com_export;
				dump.line (2, "(policy COMExport)");
				foreach (var entry in policy.entries) {
					dump.line (2, "(COMExport %s \"%s\")".printf (entry.key.spelling (), entry.decoded_value.escape ()));
				}
			}
			if (object_class != null && object_class.gobject_export != null) {
				var policy = object_class.gobject_export;
				dump.line (2, "(policy GObjectExport)");
				foreach (var entry in policy.entries) {
					dump.line (2, "(GObjectExport %s \"%s\")".printf (entry.key.spelling (), entry.decoded_value.escape ()));
				}
			}
			if (object_class != null && object_class.is_interface) {
				dump.line (2, "(interface-contract fieldless nonconstructible borrowed int-operations)");
			}
			if (object_class != null && object_class.type_parameters.length != 0) {
				if (object_class.exact_heap_class && object_class.type_parameters.length == 1) {
					dump.line (2, "(exact-class-parameter " + object_class.type_parameters[0].spelling () + ")");
				} else {
					var parameters = new StringBuilder ("(type-parameters");
					foreach (var parameter in object_class.type_parameters) {
						parameters.append (" " + parameter.spelling ());
					}
					parameters.append (")");
					dump.line (2, parameters.str);
				}
				foreach (var clause in object_class.where_clauses) {
					dump.line (2, format_where (clause));
				}
			}
			if (object_class != null && object_class.parent_class != null) {
				dump.line (2, "(base " + object_class.parent_class.spelling () + ")");
			}
			if (object_class != null && object_class.exception_root != null) {
				dump.line (2, "(exception-root)");
			}
			var generic = declaration as StructDeclarationSyntax;
			if (generic != null && generic.type_parameters.length != 0) {
				var parameters = new StringBuilder ("(type-parameters");
				foreach (var parameter in generic.type_parameters) {
					parameters.append (" " + parameter.spelling ());
				}
				parameters.append (")");
				dump.line (2, parameters.str);
			}
			if (generic != null) {
				foreach (var clause in generic.where_clauses) {
					dump.line (2, format_where (clause));
				}
			}
			foreach (var member in declaration.members) {
				if (member is FunctionDeclarationSyntax) {
					dump.write_function ((FunctionDeclarationSyntax) member, 2, true);
					continue;
				}
				if (member is PropertyDeclarationSyntax) {
					dump.write_property ((PropertyDeclarationSyntax) member);
					continue;
				}
				var field = (StructFieldDeclarationSyntax) member;
				if (field.private_keyword != null) {
					dump.line (2, "(private-field \"%s\" lexical-declaring-class)".printf (field.name.spelling ()));
				}
				if (field.readonly_keyword != null) {
					dump.line (2, "(readonly-field (type \"%s\") (name \"%s\"))".printf (field.type_name.spelling (), field.name.spelling ()));
					continue;
				}
				if (field.owned_keyword != null) {
					dump.line (2, "(owned-field (type \"%s\") (name \"%s\"))".printf (field.type_name.spelling (), field.name.spelling ()));
					continue;
				}
				dump.line (2, "(field (type \"%s\") (name \"%s\"))".printf (field.type_name.spelling (), field.name.spelling ()));
			}
			dump.line (1, ")");
		}
		for (int i = 0; i < unit.functions.length; i++) {
			if (unit.functions[i].module_internal) {
				dump.line (1, "(internal-declaration " + unit.functions[i].name.spelling () + ")");
			}
			dump.write_function (unit.functions[i]);
		}
		dump.line (0, ")");
		return dump.output.str;
	}

	private void line(int indentation, string text) {
		for (int i = 0; i < indentation; i++) {
			output.append_c ('\t');
		}
		output.append (text);
		output.append_c ('\n');
	}

	private void write_property(PropertyDeclarationSyntax property) {
		if (property.owned_keyword != null) {
			line (2, "(owned-lazy-factory receiver-borrow-observation)");
		}
		if (property.is_borrowed) {
			line (2, "(borrowed receiver-owned-field temporary-use)");
		}
		if (property.is_lazy) {
			line (2, "(lazy)");
		}
		if (property.throws_class != null) {
			line (2, "(throws %s)".printf (property.throws_class.spelling ()));
		}
		if (property.dispatch != MemberDispatchSyntax.DIRECT) {
			line (2, property.dispatch == MemberDispatchSyntax.VIRTUAL ? "(virtual)" : "(override)");
		}
		line (2, "(property (type \"%s\") (name \"%s\")".printf (property.type_name.spelling (), property.name.spelling ()));
		line (3, "(getter");
		write_block (property.getter.body, 4);
		line (3, ")");
		if (property.setter != null) {
			var parameter = property.setter.parameter;
			line (3, "(setter (parameter (type \"%s\") (name \"%s\"))".printf (parameter.type_name.spelling (), parameter.name.spelling ()));
			write_block (property.setter.body, 4);
			line (3, ")");
		}
		line (2, ")");
	}

	private void write_function(FunctionDeclarationSyntax function, int indentation = 1, bool method = false) {
		if (function.foreign_policy != null) {
			var policy = function.foreign_policy;
			line (indentation, "(policy %s)".printf (Source.DeclarationPolicyRegistry.spelling (policy.kind)));
			foreach (var entry in policy.entries) {
				line (indentation, "(%s %s \"%s\")".printf (Source.DeclarationPolicyRegistry.spelling (policy.kind), entry.key.spelling (), entry.decoded_value.escape ()));
			}
		}
		if (function.floating_point != null) {
			foreach (var entry in function.floating_point) {
				line (indentation, "(FloatingPoint %s %s)".printf (entry.key.spelling (), entry.decoded_value));
			}
		}
		if (function.is_async) {
			line (indentation, "(async)");
		}
		if (function.is_signal) {
			line (indentation, "(signal)");
		}
		if (function.dispatch != MemberDispatchSyntax.DIRECT) {
			line (indentation, function.dispatch == MemberDispatchSyntax.VIRTUAL ? "(virtual)" : "(override)");
		}
		if (function.throws_class != null) {
			line (indentation, "(throws " + function.throws_class.spelling () + ")");
		}
		var lifecycle = function as LifecycleDeclarationSyntax;
		if (lifecycle != null && lifecycle.base_arguments != null) {
			var args = new StringBuilder ("(base-initializer");
			foreach (var argument in lifecycle.base_arguments) {
				args.append (" " + format_expression (argument));
			}
			line (indentation, args.str + ")");
		}
		if (function.ccode != null) {
			foreach (var entry in function.ccode) {
				line (indentation, "(CCode %s \"%s\")".printf (entry.key.spelling (), entry.decoded_value.escape ()));
			}
		}
		line (indentation + 0, (function is LifecycleDeclarationSyntax) ? (((LifecycleDeclarationSyntax) function).is_constructor ? "(constructor" : "(destructor") : method ? "(method" : function.is_c_import ? "(extern-function" : "(function");
		if (function.is_c_export) {
			line (indentation + 1, "(export (abi %s))".printf (function.foreign_policy != null ? "C" : function.abi_identifier.spelling ()));
		} else if (function.abi_identifier != null || function.is_c_import) {
			line (indentation + 1, "(abi %s)".printf (function.foreign_policy != null ? "C" : function.abi_identifier.spelling ()));
		}
		if (function.type_parameters.length != 0) {
			var names = new StringBuilder ("(type-parameters");
			foreach (var parameter in function.type_parameters) {
				names.append (" " + parameter.spelling ());
			}
			names.append (")");
			line (indentation + 1, names.str);
		}
		if (function.owned_keyword != null) {
			line (indentation + 1, "(owned-result)");
		}
		if (function.return_type != null) {
			line (indentation + 1, "(type \"%s\")".printf (function.return_type.spelling ()));
		}
		line (indentation + 1, "(name \"%s\")".printf (function.name.spelling ()));
		if (function.parameters.length == 0) {
			line (indentation + 1, "(parameters)");
		} else {
			line (indentation + 1, "(parameters");
			for (int i = 0; i < function.parameters.length; i++) {
				var parameter = function.parameters[i];
				if (parameter.caller_information != null) {
					var info = parameter.caller_information;
					line (indentation + 2, "(caller-information %s%s)".printf (info.name.spelling (), info.target == null ? "" : " " + info.target.spelling ()));
				}
				line (indentation + 2, "(parameter%s (type \"%s\") (name \"%s\"))".printf (parameter.owned_keyword != null ? " (owned)" : parameter.borrowed_keyword == null ? "" : " (borrowed)", parameter.type_name.spelling (), parameter.name.spelling ()));
			}
			line (indentation + 1, ")");
		}
		foreach (var clause in function.where_clauses) {
			line (indentation + 1, format_where (clause));
		}
		if (function.body != null) {
			write_block (function.body, indentation + 1);
		}
		line (indentation + 0, ")");
	}

	private static string format_where(WhereClauseSyntax clause) {
		var text = new StringBuilder ("(where " + clause.type_parameter.spelling ());
		foreach (var capability in clause.capabilities) {
			text.append (" " + capability.spelling ());
		}
		text.append (")");
		return text.str;
	}

	private void write_block(BlockStatementSyntax block, int indentation) {
		if (block.statements.length == 0) {
			line (indentation, "(block)");
			return;
		}
		line (indentation, "(block");
		for (int i = 0; i < block.statements.length; i++) {
			write_statement (block.statements[i], indentation + 1);
		}
		line (indentation, ")");
	}

	private void write_statement(StatementSyntax statement, int indentation) {
		if (statement is AwaitStatementSyntax) {
			line (indentation, "(await-statement " + format_expression (((AwaitStatementSyntax) statement).expression) + ")");
			return;
		}
		if (statement is ThrowStatementSyntax) {
			var thrown = (ThrowStatementSyntax) statement;
			line (indentation, thrown.is_rethrow ? "(rethrow)" : "(throw " + format_expression (thrown.expression) + ")");
			return;
		}
		if (statement is TryStatementSyntax) {
			var guarded = (TryStatementSyntax) statement;
			line (indentation, "(try");
			write_block (guarded.body, indentation + 1);
			foreach (var handler in guarded.catches) {
				line (indentation + 1, "(catch " + handler.class_name.spelling () + " " + handler.binding.spelling ());
				write_block (handler.body, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		if (statement is MatchStatementSyntax) {
			var match = (MatchStatementSyntax) statement;
			line (indentation, "(match " + format_expression (match.scrutinee));
			foreach (var arm in match.arms) {
				var pattern = new StringBuilder (arm.variant == null ? "(else" : "(case %s.%s".printf (arm.qualifier.spelling (), arm.variant.spelling ()));
				foreach (var binding in arm.bindings) {
					pattern.append (" " + (binding.field == null ? "" : binding.field.spelling () + "=") + binding.binding.spelling ());
				}
				line (indentation + 1, pattern.str);
				write_block (arm.body, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		if (statement is ConstantDeclarationSyntax) {
			var declaration = (ConstantDeclarationSyntax) statement;
			line (indentation, "(const (name \"%s\")%s (initializer %s))".printf (declaration.name.spelling (), declaration.type_name == null ? "" : " (type \"%s\")".printf (declaration.type_name.spelling ()), format_expression (declaration.initializer)));
			return;
		}
		if (statement is BlockStatementSyntax) {
			write_block ((BlockStatementSyntax) statement, indentation);
			return;
		}
		if (statement is BreakStatementSyntax || statement is ContinueStatementSyntax) {
			line (indentation, (statement is BreakStatementSyntax) ? "(break)" : "(continue)");
			return;
		}
		if (statement is WithStatementSyntax) {
			var scoped = (WithStatementSyntax) statement;
			line (indentation, "(with " + scoped.receiver.spelling ());
			if (scoped.initializer != null) {
				write_statement (scoped.initializer, indentation + 1);
			}
			write_block (scoped.body, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is ForeachStatementSyntax) {
			var loop = (ForeachStatementSyntax) statement;
			line (indentation, "(foreach " + loop.binding.spelling () + " " + format_expression (loop.collection));
			write_block (loop.body, indentation + 1);
			line (indentation, ")");
			return;
		}
		if (statement is ForStatementSyntax) {
			var loop = (ForStatementSyntax) statement;
			line (indentation, "(for");
			if (loop.initializer != null) {
				line (indentation + 1, "(initializer");
				write_statement (loop.initializer, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation + 1, loop.condition == null ? "(condition true)" : "(condition " + format_expression (loop.condition) + ")");
			write_block (loop.body, indentation + 1);
			if (loop.step != null) {
				line (indentation + 1, "(step");
				write_statement (loop.step, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		var loop = statement as WhileStatementSyntax;
		if (loop != null) {
			line (indentation, "(while");
			line (indentation + 1, "(condition %s)".printf (format_expression (loop.condition)));
			line (indentation + 1, "(body");
			write_block (loop.body, indentation + 2);
			line (indentation + 1, ")");
			line (indentation, ")");
			return;
		}
		var call = statement as CallStatementSyntax;
		if (call != null) {
			line (indentation, "(call-statement %s)".printf (format_expression (call.call)));
			return;
		}
		var conditional = statement as IfStatementSyntax;
		if (conditional != null) {
			line (indentation, "(if");
			line (indentation + 1, "(condition %s)".printf (format_expression (conditional.condition)));
			line (indentation + 1, "(then");
			write_block (conditional.then_body, indentation + 2);
			line (indentation + 1, ")");
			if (conditional.else_body != null) {
				line (indentation + 1, "(else");
				write_block (conditional.else_body, indentation + 2);
				line (indentation + 1, ")");
			}
			line (indentation, ")");
			return;
		}
		var aggregate = statement as StructLocalDeclarationSyntax;
		if (aggregate != null) {
			if (aggregate.owned_keyword != null) {
				line (indentation, "(ownership transferable-owned)");
			}
			line (indentation, "(struct-local (type \"%s\") (name \"%s\")".printf (aggregate.type_name.spelling (), aggregate.name.spelling ()));
			foreach (var field in aggregate.initializer.fields) {
				write_field_initializer (field, indentation + 1);
			}
			line (indentation, ")");
			return;
		}
		var indexed = statement as IndexedAssignmentSyntax;
		if (indexed != null) {
			line (indentation, "(indexed-assignment %s %s)".printf (format_expression (indexed.target), format_expression (indexed.expression)));
			return;
		}
		var dereference = statement as DereferenceAssignmentSyntax;
		if (dereference != null) {
			line (indentation, "(assign %s %s)".printf (format_expression (dereference.target), format_expression (dereference.expression)));
			return;
		}
		var field_assignment = statement as FieldAssignmentStatementSyntax;
		if (field_assignment != null) {
			line (indentation, "(assign %s %s)".printf (format_expression (field_assignment.target), format_expression (field_assignment.expression)));
			return;
		}
		if (statement is InferredLocalDeclarationSyntax) {
			var local = (InferredLocalDeclarationSyntax) statement;
			line (indentation, "(inferred-local (name \"%s\") %s)".printf (local.name.spelling (), format_expression (local.initializer)));
			return;
		}
		if (statement is LocalDeclarationSyntax) {
			var local = (LocalDeclarationSyntax) statement;
			line (indentation, "(%s (type \"%s\") (name \"%s\") %s)".printf (local.owned_keyword == null ? "local" : "owned-local", local.type_name.spelling (), local.name.spelling (), format_expression (local.initializer)));
			return;
		}
		if (statement is AssignmentStatementSyntax) {
			var assignment = (AssignmentStatementSyntax) statement;
			line (indentation, "(assign (name \"%s\") %s)".printf (assignment.name.spelling (), format_expression (assignment.expression)));
			return;
		}
		var exchange = statement as SwapStatementSyntax;
		if (exchange != null) {
			line (indentation, "(swap %s %s)".printf (format_expression (exchange.left), format_expression (exchange.right)));
			return;
		}
		var release = statement as ReleaseStatementSyntax;
		if (release != null) {
			line (indentation, "(release (name \"%s\"))".printf (release.owner.spelling ()));
			return;
		}
		var returned = (ReturnStatementSyntax) statement;
		line (indentation, returned.expression == null ? "(return)" : "(return %s)".printf (format_expression (returned.expression)));
	}

	private void write_field_initializer(FieldInitializerSyntax field, int indentation) {
		if (field.initializer == null) {
			line (indentation, "(initialize-field \"%s\" %s)".printf (field.name.spelling (), format_expression (field.expression)));
			return;
		}
		line (indentation, "(initialize-field \"%s\"".printf (field.name.spelling ()) + " (storage-initializer");
		foreach (var child in field.initializer.fields) {
			write_field_initializer (child, indentation + 1);
		}
		line (indentation, "))");
	}

	private static string format_storage_initializer(StructInitializerSyntax initializer) {
		var text = new StringBuilder ("(storage-initializer");
		foreach (var field in initializer.fields) {
			text.append (" (initialize-field \"%s\" %s)".printf (field.name.spelling (), field.initializer == null ? format_expression (field.expression) : format_storage_initializer (field.initializer)));
		}
		return text.str + ")";
	}

	internal static string format_expression(ExpressionSyntax expression) {
		if (expression is AwaitExpressionSyntax) {
			return "(await " + format_expression (((AwaitExpressionSyntax) expression).operation) + ")";
		}
		if (expression is HeapObjectConstructionSyntax) {
			var allocation = (HeapObjectConstructionSyntax) expression;
			var text = new StringBuilder ((allocation.fallible ? "(try-new-object " : "(new-object ") + allocation.class_name.spelling ());
			if (allocation.allocation_context != null) {
				text.append (" (allocation-context " + format_expression (allocation.allocation_context) + ")");
			}
			foreach (var argument in allocation.arguments) {
				text.append (" " + format_expression (argument));
			}
			return text.str + ")";
		}
		if (expression is ArrayStructInitializerSyntax) {
			return format_storage_initializer (((ArrayStructInitializerSyntax) expression).initializer);
		}
		if (expression is Utf8FactoryExpressionSyntax) {
			return ((Utf8FactoryExpressionSyntax) expression).validates ? "(utf8-validate bytes)" : "(utf8-certified-copy-input bytes)";
		}
		if (expression is TextLiteralExpressionSyntax) {
			var payload = ((TextLiteralExpressionSyntax) expression).payload;
			return "(text (bytes %s) (hex %s))".printf (payload.byte_length.to_string (), payload.hex ());
		}
		if (expression is TextMemberExpressionSyntax) {
			var member = (TextMemberExpressionSyntax) expression;
			return "(text-member %s %s)".printf (member.member.spelling (), format_expression (member.receiver));
		}
		if (expression is BufferAllocationSyntax) {
			var allocation = (BufferAllocationSyntax) expression;
			return "(owned-buffer-allocate (element %s) (count %s)%s)".printf (allocation.element_type.spelling (), format_expression (allocation.count), allocation.failure_call == null ? "" : " (else " + format_expression (allocation.failure_call) + ")");
		}
		var dot = expression as VectorDotExpressionSyntax;
		if (dot != null) {
			var text = new StringBuilder ("(" + dot.keyword.spelling ());
			foreach (var operand in dot.operands) {
				text.append (" " + format_expression (operand));
			}
			if (dot.destination != null) {
				text.append (" (type \"" + dot.destination.spelling () + "\")");
			}
			text.append (")");
			return text.str;
		}
		var dsp = expression as DspExpressionSyntax;
		if (dsp != null) {
			return "(%s %s%s%s)".printf (dsp.keyword.spelling (), format_expression (dsp.first), dsp.second == null ? "" : " " + format_expression (dsp.second), dsp.destination == null ? "" : " (type \"" + dsp.destination.spelling () + "\")");
		}
		var conversion = expression as ConversionExpressionSyntax;
		if (conversion != null) {
			return "(as %s (type \"%s\"))".printf (format_expression (conversion.operand), conversion.destination.spelling ());
		}
		var primitive = expression as VectorPrimitiveExpressionSyntax;
		if (primitive != null) {
			var text = new StringBuilder ("(vector-%s".printf (primitive.keyword.spelling ()));
			foreach (var operand in primitive.operands) {
				text.append (" " + format_expression (operand));
			}
			if (primitive.indices.length > 0) {
				text.append (" (ordinals");
				foreach (var index in primitive.indices) {
					text.append (" " + index.spelling ());
				}
				text.append (")");
			}
			text.append (")");
			return text.str;
		}
		var extract = expression as VectorExtractExpressionSyntax;
		if (extract != null) {
			return "(vector-extract (lane %s) %s)".printf (extract.index.spelling (), format_expression (extract.vector));
		}
		var indexed = expression as IndexExpressionSyntax;
		if (indexed != null) {
			return "(index %s %s)".printf (format_expression (indexed.container), format_expression (indexed.subscript));
		}
		var array = expression as ArrayInitializerSyntax;
		if (array != null) {
			var text = new StringBuilder ("(array-init");
			foreach (var element in array.elements) {
				text.append (" " + format_expression (element));
			}
			return text.str + ")";
		}
		var vector = expression as VectorInitializerSyntax;
		if (vector != null) {
			var text = new StringBuilder ("(vector-init");
			foreach (var lane in vector.lanes) {
				text.append (" " + format_expression (lane));
			}
			text.append (")");
			return text.str;
		}
		var reduction = expression as VectorReductionExpressionSyntax;
		if (reduction != null) {
			return "(vector-%s %s)".printf (reduction.keyword.spelling (), format_expression (reduction.operand));
		}
		var dereference = expression as DereferenceExpressionSyntax;
		if (dereference != null) {
			return "(dereference %s)".printf (format_expression (dereference.pointer));
		}
		var address = expression as AddressOfExpressionSyntax;
		if (address != null) {
			return "(address-of \"%s\")".printf (address.identifier.spelling ());
		}
		var field = expression as FieldAccessExpressionSyntax;
		if (field != null) {
			if (field.aggregate != null) {
				// Keep the established syntactic spelling of this expression member.
				// Its text/record meaning is selected only by semantic checking.
				if (field.aggregate is IndexExpressionSyntax && field.field_name.spelling () == "byte_length") {
					return "(text-member byte_length %s)".printf (format_expression (field.aggregate));
				}
				return "(field-access (base %s) \"%s\")".printf (format_expression (field.aggregate), field.field_name.spelling ());
			}
			return "(%s \"%s\" \"%s\")".printf (field.indirect ? "indirect-field-access" : "field-access", field.identifier.spelling (), field.field_name.spelling ());
		}
		var call = expression as CallExpressionSyntax;
		if (call != null) {
			if (call.type_arguments.length != 0) {
				var text = new StringBuilder ("(generic-call \"%s\" (type-arguments".printf (call.identifier.spelling ()));
				foreach (var type in call.type_arguments) {
					text.append (" " + type.spelling ());
				}
				text.append (") (arguments");
				foreach (var argument in call.arguments) {
					text.append (" " + format_expression (argument));
				}
				text.append ("))");
				return text.str;
			}
			string form = (call.identifier.kind == TokenKind.SLICE || call.identifier.kind == TokenKind.LEN) ? "(%s-form (arguments" : "(call \"%s\" (arguments";
			var text = new StringBuilder ((call is ConstructorInitializerSyntax) ? "(constructor-initializer (class \"%s\") (arguments".printf (call.receiver.spelling ()) : call.receiver_place != null ? "(method-call (receiver %s) (target \"%s\") (arguments".printf (format_expression (call.receiver_place), call.identifier.spelling ()) : call.receiver == null ? form.printf (call.identifier.spelling ()) : "(method-call (receiver \"%s\") (target \"%s\") (arguments".printf (call.receiver.spelling (), call.identifier.spelling ()));
			for (int i = 0; i < call.arguments.length; i++) {
				text.append (" " + format_expression (call.arguments[i]));
			}
			text.append ("))");
			return text.str;
		}
		if (expression is NameExpressionSyntax) {
			if (((NameExpressionSyntax) expression).identifier.kind == TokenKind.THIS) {
				return "(this)";
			}
			return "(name \"%s\")".printf (((NameExpressionSyntax) expression).identifier.spelling ());
		}
		if (expression is NullPointerExpressionSyntax) {
			return "(null)";
		}
		var move = expression as MoveExpressionSyntax;
		if (move != null) {
			string name = move.source.spelling ();
			foreach (var path_field in move.fields) {
				name += "." + path_field.spelling ();
			}
			return "(move (name \"%s\"))".printf (name);
		}
		if (expression is BooleanLiteralExpressionSyntax) {
			return "(bool %s)".printf (((BooleanLiteralExpressionSyntax) expression).literal.spelling ());
		}
		if (expression is FloatLiteralExpressionSyntax) {
			return "(float \"%s\")".printf (((FloatLiteralExpressionSyntax) expression).literal.spelling ());
		}
		if (expression is IntegerLiteralExpressionSyntax) {
			return "(integer \"%s\")".printf (((IntegerLiteralExpressionSyntax) expression).literal.spelling ());
		}
		if (expression is ParenthesizedExpressionSyntax) {
			return "(parenthesized %s)".printf (format_expression (((ParenthesizedExpressionSyntax) expression).expression));
		}
		if (expression is PrefixExpressionSyntax) {
			var prefix = (PrefixExpressionSyntax) expression;
			return "(prefix \"%s\" %s)".printf (prefix.operator_token.spelling (), format_expression (prefix.operand));
		}
		var short_circuit = expression as ShortCircuitExpressionSyntax;
		if (short_circuit != null) {
			return "(short-circuit \"%s\" %s %s)".printf (short_circuit.operator_token.spelling (), format_expression (short_circuit.left), format_expression (short_circuit.right));
		}
		if (expression is ComparisonChainSyntax) {
			var chain = (ComparisonChainSyntax) expression;
			var text = new StringBuilder ("(comparison-chain");
			for (int i = 0; i < chain.operands.length; i++) {
				if (i > 0) {
					text.append (" " + chain.operators[i - 1].spelling ());
				}
				text.append (" " + format_expression (chain.operands[i]));
			}
			text.append (")");
			return text.str;
		}
		if (expression is BinaryExpressionSyntax) {
			var binary = (BinaryExpressionSyntax) expression;
			return "(binary \"%s\" %s %s)".printf (binary.operator_token.spelling (), format_expression (binary.left), format_expression (binary.right));
		}
		assert_not_reached ();
	}
}
}
