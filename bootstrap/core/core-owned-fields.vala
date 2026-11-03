// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
// Capture/consume the incoming responsibility before any old-handle cleanup.
public class CoreOwnedFieldTransfer : CoreStatement {
	public CoreIndirectFieldPlace destination { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }
	public CoreOwnedLocal? source { get; private set; }
	public CoreValue? producer { get; private set; }
	public bool initializes { get; private set; }
	internal CoreOwnedFieldTransfer (SourceSpan span, CoreIndirectFieldPlace destination, CoreCleanupContract cleanup, CoreOwnedLocal? source, CoreValue? producer, bool initializes) {
		base (span);
		this.destination = destination;
		this.cleanup = cleanup;
		this.source = source;
		this.producer = producer;
		this.initializes = initializes;
	}

}

public class CoreOwnedFieldBorrow : CoreValue {
	public CoreIndirectFieldPlace source { get; private set; }
	public CoreParameter? parameter { get; private set; }
	internal CoreOwnedFieldBorrow (SourceSpan span, CoreIndirectFieldPlace source, CoreParameter? parameter) {
		base (span, source.semantic_type);
		this.source = source;
		this.parameter = parameter;
	}

}

// Destructor epilogue actions run only after normal user-body completion.
public class CoreOwnedFieldCleanup : CoreNode {
	public CoreStructField field { get; private set; }
	public CoreCleanupContract? cleanup { get; private set; }
	internal CoreOwnedFieldCleanup.snapshot (SourceSpan span, CoreStructField field) {
		base (span);
		this.field = field;
	}
	internal CoreOwnedFieldCleanup (SourceSpan span, CoreStructField field, CoreCleanupContract cleanup) {
		base (span);
		this.field = field;
		this.cleanup = cleanup;
	}

}
}
