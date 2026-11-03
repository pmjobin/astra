// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Source {
public class EnumInstanceIdentity : Object {
	internal EnumInstanceIdentity () {
	}

}
public class EnumBindingIdentity : Object {
	public EnumInstanceIdentity instance { get; private set; }
	public EnumFieldIdentity field { get; private set; }
	public int local_ordinal { get; private set; }
	internal EnumBindingIdentity (EnumFieldIdentity field, int local_ordinal, EnumInstanceIdentity instance) {
		this.field = field;
		this.local_ordinal = local_ordinal;
		this.instance = instance;
	}

}
// Immutable identity tokens have no declaration, stage, type or layout backlink.
public class EnumIdentity : Object {
	private string identifier;
	public string name { get { return identifier; } }
	internal EnumIdentity (string name) {
		this.identifier = name;
	}

}

public class EnumVariantIdentity : Object {
	public EnumIdentity enumeration { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public int ordinal { get; private set; }
	internal EnumVariantIdentity (EnumIdentity enumeration, string name, int ordinal) {
		this.enumeration = enumeration;
		this.identifier = name;
		this.ordinal = ordinal;
	}

}

public class EnumFieldIdentity : Object {
	public EnumVariantIdentity variant { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public int ordinal { get; private set; }
	internal EnumFieldIdentity (EnumVariantIdentity variant, string name, int ordinal) {
		this.variant = variant;
		this.identifier = name;
		this.ordinal = ordinal;
	}

}
}
