// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
public class CoreEnumScalarValue : CoreValue {
	public CoreOwnedLocal source { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }
	internal CoreEnumScalarValue (SourceSpan span, CoreOwnedLocal source) {
		base (span, source.place.semantic_type);
		this.source = source;
		this.cleanup = source.cleanup;
	}

}
public class CoreEnumBufferValue : CoreValue {
	public CoreOwnedLocal? source { get; private set; }
	public CoreValue? producer { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }
	internal CoreEnumBufferValue (SourceSpan span, CoreCleanupContract cleanup, CoreOwnedLocal? source, CoreValue? producer) {
		base (span, cleanup.buffer_type);
		this.cleanup = cleanup;
		this.source = source;
		this.producer = producer;
	}

}
public abstract class CoreEnumProducer : CoreNode {
	public EnumInstanceIdentity instance { get; private set; }
	public EnumDefinition definition { get; private set; }
	public EnumType semantic_type { get { return definition.semantic_type; } }
	protected CoreEnumProducer (SourceSpan span, EnumDefinition definition, EnumInstanceIdentity? instance = null) {
		base (span);
		this.instance = instance ?? new EnumInstanceIdentity ();
		this.definition = definition;
	}

}

public class CoreEnumSnapshot : CoreEnumProducer {
	public EnumUse mode { get; private set; }
	public CoreLocalPlace source { get; private set; }
	internal CoreEnumSnapshot (SourceSpan span, EnumDefinition definition, CoreLocalPlace source, EnumInstanceIdentity? instance = null, EnumUse mode = EnumUse.COPY) {
		base (span, definition, instance);
		this.source = source;
		this.mode = mode;
	}

}

public class CoreEnumFieldValue : CoreNode {
	public EnumField field { get; private set; }
	public CoreValue? scalar { get; private set; }
	public CoreStructProducer? record { get; private set; }
	public CoreEnumProducer? sum { get; private set; }
	internal CoreEnumFieldValue (SourceSpan span, EnumField field, CoreValue? scalar, CoreStructProducer? record, CoreEnumProducer? sum) {
		base (span);
		this.field = field;
		this.scalar = scalar;
		this.record = record;
		this.sum = sum;
	}

}

public class CoreEnumConstruct : CoreEnumProducer {
	private GenericArray<CoreEnumFieldValue> input_contract = new GenericArray<CoreEnumFieldValue> ();
	public EnumVariant variant { get; private set; }
	public GenericArray<CoreEnumFieldValue> fields { get; private set; }
	internal CoreEnumConstruct (SourceSpan span, EnumDefinition definition, EnumVariant variant, GenericArray<CoreEnumFieldValue> fields, EnumInstanceIdentity? instance = null) {
		base (span, definition, instance);
		this.variant = variant;
		this.fields = fields;
		foreach (var input in fields) {
			input_contract.add (new CoreEnumFieldValue (input.span, input.field, input.scalar, input.record, input.sum));
		}
	}

	internal bool matches_inputs() {
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

public class CoreEnumCallResult : CoreEnumProducer {
	public GenericArray<SemanticType>? type_arguments { get; internal set; }
	private WeakRef callee;
	public CoreFunction? target { owned get { return (CoreFunction?) callee.get (); } }
	public GenericArray<CoreValue> arguments { get; private set; }
	public CoreValue? receiver { get; private set; }
	internal CoreEnumCallResult (SourceSpan span, EnumDefinition definition, CoreFunction target, GenericArray<CoreValue> arguments, CoreValue? receiver, EnumInstanceIdentity? instance = null) {
		base (span, definition, instance);
		callee = WeakRef (target);
		this.arguments = arguments;
		this.receiver = receiver;
	}

}

public class CoreEnumArgument : CoreValue {
	public CoreEnumProducer producer { get; private set; }
	public CoreParameter parameter { get; private set; }
	internal CoreEnumArgument (SourceSpan span, CoreParameter parameter, CoreEnumProducer producer) {
		base (span, producer.semantic_type);
		this.parameter = parameter;
		this.producer = producer;
	}

}

public class CoreEnumStore : CoreStatement {
	public CoreLocalPlace destination { get; private set; }
	public CoreEnumProducer producer { get; private set; }
	public bool initializes_destination { get; private set; }
	internal CoreEnumStore (SourceSpan span, CoreLocalPlace destination, CoreEnumProducer producer, bool initializes_destination) {
		base (span);
		this.destination = destination;
		this.producer = producer;
		this.initializes_destination = initializes_destination;
	}

}

public class CoreEnumReturn : CoreStatement {
	public CoreEnumProducer producer { get; private set; }
	internal CoreEnumReturn (SourceSpan span, CoreEnumProducer producer) {
		base (span);
		this.producer = producer;
	}

}

public class CoreEnumBinding : CoreNode {
	public CoreOwnedLocal? acquisition { get; private set; }
	public EnumBindingIdentity contract { get; private set; }
	public EnumField field { get; private set; }
	public CoreLocalPlace destination { get; private set; }
	internal CoreEnumBinding (SourceSpan span, EnumField field, CoreLocalPlace destination, EnumBindingIdentity contract, CoreOwnedLocal? acquisition = null) {
		base (span);
		this.contract = contract;
		this.field = field;
		this.destination = destination;
		this.acquisition = acquisition;
	}

}

public class CoreEnumArm : CoreNode {
	private GenericArray<CoreEnumBinding> binding_contract = new GenericArray<CoreEnumBinding> ();
	public EnumVariant? variant { get; private set; }
	public GenericArray<CoreEnumBinding> bindings { get; private set; }
	public CoreBlock body { get; private set; }
	internal CoreEnumArm (SourceSpan span, EnumVariant? variant, GenericArray<CoreEnumBinding> bindings, CoreBlock body) {
		base (span);
		this.variant = variant;
		this.bindings = bindings;
		this.body = body;
		foreach (var binding in bindings) {
			binding_contract.add (new CoreEnumBinding (binding.span, binding.field, binding.destination, binding.contract, binding.acquisition));
		}
	}

	internal bool matches_bindings() {
		if (bindings.length != binding_contract.length) {
			return false;
		}
		for (int i = 0; i < bindings.length; i++) {
			var actual = bindings[i];
			var expected = binding_contract[i];
			if (actual.field != expected.field || actual.destination != expected.destination || actual.acquisition != expected.acquisition || actual.contract.field != actual.field.identity || actual.contract.local_ordinal != actual.destination.ordinal) {
				return false;
			}
		}
		return true;
	}

}

public class CoreEnumMatch : CoreStatement {
	public CoreEnumProducer scrutinee { get; private set; }
	public GenericArray<CoreEnumArm> arms { get; private set; }
	internal CoreEnumMatch (SourceSpan span, CoreEnumProducer scrutinee, GenericArray<CoreEnumArm> arms) {
		base (span);
		this.scrutinee = scrutinee;
		this.arms = arms;
	}

}

public class CoreEnumEquality : CoreValue {
	public CoreEnumProducer left { get; private set; }
	public CoreEnumProducer right { get; private set; }
	public bool unequal { get; private set; }
	internal CoreEnumEquality (SourceSpan span, SemanticType boolean, CoreEnumProducer left, CoreEnumProducer right, bool unequal) {
		base (span, boolean);
		this.left = left;
		this.right = right;
		this.unequal = unequal;
	}

}

public class CoreAcquireEnumParameter : CoreStatement {
	public CoreLocalPlace destination { get; private set; }
	public CoreParameter parameter { get; private set; }
	internal CoreAcquireEnumParameter (SourceSpan span, CoreLocalPlace destination, CoreParameter parameter) {
		base (span);
		this.destination = destination;
		this.parameter = parameter;
	}

}
}
