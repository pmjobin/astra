// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
public abstract class CheckedEnumProducer : CheckedNode {
	public EnumInstanceIdentity instance { get; private set; }
	public EnumDefinition definition { get; private set; }
	public EnumType semantic_type { get { return definition.semantic_type; } }
	protected CheckedEnumProducer (SourceSpan span, EnumDefinition definition) {
		base (span);
		instance = new EnumInstanceIdentity ();
		this.definition = definition;
	}

}

public class CheckedEnumSnapshot : CheckedEnumProducer {
	public EnumUse mode { get; private set; }
	public LocalSymbol source { get; private set; }
	internal CheckedEnumSnapshot (SourceSpan span, EnumDefinition definition, LocalSymbol source, EnumUse mode = EnumUse.COPY) {
		base (span, definition);
		this.source = source;
		this.mode = mode;
	}

}

public class CheckedEnumFieldValue : CheckedNode {
	public EnumField field { get; private set; }
	public CheckedExpression? scalar { get; private set; }
	public CheckedStructProducer? record { get; private set; }
	public CheckedEnumProducer? sum { get; private set; }
	internal CheckedEnumFieldValue (SourceSpan span, EnumField field, CheckedExpression? scalar, CheckedStructProducer? record, CheckedEnumProducer? sum) {
		base (span);
		this.field = field;
		this.scalar = scalar;
		this.record = record;
		this.sum = sum;
	}

}

public class CheckedEnumConstruct : CheckedEnumProducer {
	private GenericArray<CheckedEnumFieldValue> input_contract = new GenericArray<CheckedEnumFieldValue> ();
	public EnumVariant variant { get; private set; }
	public GenericArray<CheckedEnumFieldValue> fields { get; private set; }
	internal CheckedEnumConstruct (SourceSpan span, EnumDefinition definition, EnumVariant variant, GenericArray<CheckedEnumFieldValue> fields) {
		base (span, definition);
		this.variant = variant;
		this.fields = fields;
		foreach (var input in fields) {
			input_contract.add (new CheckedEnumFieldValue (input.span, input.field, input.scalar, input.record, input.sum));
		}
	}

	public bool matches_inputs() {
		if (fields.length != input_contract.length) {
			return false;
		}
		for (int i = 0; i < fields.length; i++) {
			var actual = fields[i];
			var expected = input_contract[i];
			if (actual.field != expected.field || actual.scalar != expected.scalar || actual.record != expected.record || actual.sum != expected.sum) {
				return false;
			}
		}
		return true;
	}

}

public class CheckedEnumCallResult : CheckedEnumProducer {
	public GenericArray<SemanticType>? type_arguments { get; internal set; }
	private WeakRef callee;
	public FunctionSymbol? target { owned get { return (FunctionSymbol?) callee.get (); } }
	public GenericArray<CheckedExpression> arguments { get; private set; }
	public CheckedExpression? receiver { get; private set; }
	internal CheckedEnumCallResult (SourceSpan span, EnumDefinition definition, FunctionSymbol target, GenericArray<CheckedExpression> arguments, CheckedExpression? receiver) {
		base (span, definition);
		callee = WeakRef (target);
		this.arguments = arguments;
		this.receiver = receiver;
	}

}

public class CheckedEnumArgument : CheckedExpression {
	public CheckedEnumProducer producer { get; private set; }
	public ParameterSymbol parameter { get; private set; }
	internal CheckedEnumArgument (SourceSpan span, ParameterSymbol parameter, CheckedEnumProducer producer) {
		base (span, producer.semantic_type);
		this.parameter = parameter;
		this.producer = producer;
	}

}

public class CheckedEnumStore : CheckedStatement {
	public LocalSymbol destination { get; private set; }
	public CheckedEnumProducer producer { get; private set; }
	public bool initializes_destination { get; private set; }
	internal CheckedEnumStore (SourceSpan span, LocalSymbol destination, CheckedEnumProducer producer, bool initializes_destination) {
		base (span);
		this.destination = destination;
		this.producer = producer;
		this.initializes_destination = initializes_destination;
	}

}

public class CheckedEnumReturn : CheckedStatement {
	public CheckedEnumProducer producer { get; private set; }
	internal CheckedEnumReturn (SourceSpan span, CheckedEnumProducer producer) {
		base (span);
		this.producer = producer;
	}

}

public class CheckedEnumBinding : CheckedNode {
	public EnumBindingIdentity contract { get; private set; }
	public EnumField field { get; private set; }
	public LocalSymbol destination { get; private set; }
	internal CheckedEnumBinding (SourceSpan span, EnumField field, LocalSymbol destination, EnumInstanceIdentity instance) {
		base (span);
		contract = new EnumBindingIdentity (field.identity, destination.ordinal, instance);
		this.field = field;
		this.destination = destination;
	}

}

public class CheckedEnumArm : CheckedNode {
	private GenericArray<CheckedEnumBinding> binding_contract = new GenericArray<CheckedEnumBinding> ();
	public EnumVariant? variant { get; private set; }
	public GenericArray<CheckedEnumBinding> bindings { get; private set; }
	public CheckedBlockStatement body { get; private set; }
	internal CheckedEnumArm (SourceSpan span, EnumVariant? variant, GenericArray<CheckedEnumBinding> bindings, CheckedBlockStatement body) {
		base (span);
		this.variant = variant;
		this.bindings = bindings;
		this.body = body;
		foreach (var binding in bindings) {
			binding_contract.add (new CheckedEnumBinding (binding.span, binding.field, binding.destination, binding.contract.instance));
		}
	}

	public bool matches_bindings() {
		if (bindings.length != binding_contract.length) {
			return false;
		}
		for (int i = 0; i < bindings.length; i++) {
			var actual = bindings[i];
			var expected = binding_contract[i];
			if (actual.field != expected.field || actual.destination != expected.destination || actual.contract.field != actual.field.identity || actual.contract.local_ordinal != actual.destination.ordinal) {
				return false;
			}
		}
		return true;
	}

}

public class CheckedEnumMatch : CheckedStatement {
	public CheckedEnumProducer scrutinee { get; private set; }
	public GenericArray<CheckedEnumArm> arms { get; private set; }
	internal CheckedEnumMatch (SourceSpan span, CheckedEnumProducer scrutinee, GenericArray<CheckedEnumArm> arms) {
		base (span);
		this.scrutinee = scrutinee;
		this.arms = arms;
	}

}

public class CheckedEnumEquality : CheckedExpression {
	public CheckedEnumProducer left { get; private set; }
	public CheckedEnumProducer right { get; private set; }
	public bool unequal { get; private set; }
	internal CheckedEnumEquality (SourceSpan span, SemanticType boolean, CheckedEnumProducer left, CheckedEnumProducer right, bool unequal) {
		base (span, boolean);
		this.left = left;
		this.right = right;
		this.unequal = unequal;
	}

}
}
