// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
namespace Astra.Semantic {
public class AsyncClosureCaptures : Object {
	public static bool valid(SemanticType type, PointerParameterContract contract, bool threaded) {
		if (type is SharedHandleType) {
			return false;
		}
		var closure = type as ClosureHandleType;
		return closure == null || contract == PointerParameterContract.OWNED_TRANSFER && !threaded && !closure.threaded && !closure.actor;
	}

}
// This opaque provider resource owns its fd and pinned byte allocation.
// Name and destructor are a joint imported protocol; stage verifiers also
// require an exact live unique owner, never a borrowed pointer or annotation.
public class AsyncPayloadTypes : Object {
	public static bool matches(SemanticType type, string cleanup) {
		return type is HandleType && ((HandleType) type).name == "LinuxPayload" && cleanup == "astra_linux_payload_close";
	}

}
public class AsyncBridgeTypes : Object {
	public static bool matches(SemanticType type, string cleanup) {
		return type.get_type () == typeof (HandleType) && ((HandleType) type).name == "WorkerPool" && ((HandleType) type).context_mode == "" && cleanup == "astra_async_worker_pool_close";
	}

	public static bool compatible(AsyncRuntimeIdentity source, AsyncRuntimeIdentity target) {
		return source.composable && target.composable && !source.threaded && target.threaded && source.error_type == target.error_type;
	}

}
// Exact opt-in identity is resolved once from a source nomination. Printed
// operation names cannot grant authority after checking.
public class AsyncRuntimeIdentity : Object {
	public bool composable { get; private set; }
	public AsyncProviderKind provider { get; private set; }
	public bool threaded { get { return provider == AsyncProviderKind.POSIX_THREADED; } }
	public bool linux { get { return provider == AsyncProviderKind.LINUX_IO_URING; } }
	public SourceSpan nomination { get; private set; }
	private string executor_identifier;
	public string executor_name { get { return executor_identifier; } }
	public ExecutorType executor_type { get; private set; }
	public ClassType error_type { get; private set; }
	public EnumType status_type { get; private set; }
	// Status facades and executor owners remain nominal. Tasks may compose only
	// when their physical provider and checked runtime error identity agree.
	public bool compatible(AsyncRuntimeIdentity other) {
		return provider == other.provider && error_type == other.error_type;
	}

	internal AsyncRuntimeIdentity (SourceSpan nomination, string name, ClassType error, EnumType status, AsyncProviderKind provider = AsyncProviderKind.VIRTUAL, bool composable = false) {
		this.composable = composable;
		this.provider = provider;
		this.nomination = nomination;
		executor_identifier = name;
		executor_type = new ExecutorType (this);
		error_type = error;
		status_type = status;
	}

}
public class AsyncBodyContract : Object {
	public TaskType task_type { get; private set; }
	public SourceSpan declaration { get; private set; }
	public SemanticType success_type { get; private set; }
	public ResultOwnershipContract success_mode { get; private set; }
	public ClassType? exception_bound { get; private set; }
	public AsyncRuntimeIdentity runtime { get; private set; }
	internal AsyncBodyContract (SourceSpan declaration, SemanticType success_type, ResultOwnershipContract success_mode, ClassType? exception_bound, AsyncRuntimeIdentity runtime) {
		this.declaration = declaration;
		this.success_type = success_type;
		this.success_mode = success_mode;
		this.exception_bound = exception_bound;
		this.runtime = runtime;
		task_type = new TaskType (success_type, success_mode, exception_bound, runtime);
	}

}
// Logical unique-task contract is separate from the exact generated body
// identity. Task has no source generic, field or parameter spelling.
public class TaskType : SemanticType {
	public TaskContractIdentity identity { get; private set; default = new TaskContractIdentity (); }
	public SemanticType success_type { get; private set; }
	public ResultOwnershipContract success_mode { get; private set; }
	public ClassType? exception_bound { get; private set; }
	public AsyncRuntimeIdentity runtime { get; private set; }
	internal TaskType (SemanticType success_type, ResultOwnershipContract success_mode, ClassType? exception_bound, AsyncRuntimeIdentity runtime) {
		base (TypeKind.TASK);
		this.success_type = success_type;
		this.success_mode = success_mode;
		this.exception_bound = exception_bound;
		this.runtime = runtime;
	}

	internal string task_display_name() {
		return "Task<%s%s%s>".printf (success_mode == ResultOwnershipContract.OWNED_TRANSFER ? "owned " : "", success_type.display_name (), exception_bound == null ? "" : " throws " + exception_bound.display_name ());
	}

	public bool same_contract(TaskType other) {
		return success_type == other.success_type && success_mode == other.success_mode && exception_bound == other.exception_bound && runtime == other.runtime;
	}

}
public class ExecutorType : SemanticType {
	public TaskContractIdentity identity { get; private set; default = new TaskContractIdentity (); }
	private WeakRef runtime_identity;
	public AsyncRuntimeIdentity? runtime { owned get { return (AsyncRuntimeIdentity?) runtime_identity.get (); } }
	internal ExecutorType (AsyncRuntimeIdentity runtime) {
		base (TypeKind.EXECUTOR);
		runtime_identity = WeakRef (runtime);
	}

	internal string executor_display_name() {
		return runtime != null && (runtime.linux || runtime.threaded) ? runtime.executor_name : "VirtualExecutor";
	}

}
public enum AsyncOperationKind {
	OPEN, START, CANCEL, PUMP, ADVANCE, BEGIN_SHUTDOWN, SHUTDOWN_COMPLETE, FINISH_SHUTDOWN, RUN, CLOSE, WAIT
}

public class AsyncOperationContract : Object {
	public AsyncRuntimeIdentity runtime { get; private set; }
	public AsyncOperationKind kind { get; private set; }
	public SemanticType result { get; private set; }
	public bool raises { get { return kind == AsyncOperationKind.WAIT || kind == AsyncOperationKind.OPEN || kind == AsyncOperationKind.START || kind == AsyncOperationKind.ADVANCE || kind == AsyncOperationKind.RUN; } }
	public bool valid_shape(SemanticType? executor, SemanticType? task, SemanticType? argument, AsyncBodyContract? body) {
		if ((kind == AsyncOperationKind.WAIT && !runtime.linux) || (kind == AsyncOperationKind.ADVANCE && (runtime.linux || runtime.threaded))) {
			return false;
		}
		if (executor != null && executor != runtime.executor_type) {
			return false;
		}
		var task_type = task as TaskType;
		if (task != null && (task_type == null || !task_type.runtime.compatible (runtime))) {
			return false;
		}
		bool task_operation = kind == AsyncOperationKind.START || kind == AsyncOperationKind.CANCEL || kind == AsyncOperationKind.RUN;
		bool argument_operation = kind == AsyncOperationKind.OPEN || kind == AsyncOperationKind.PUMP || kind == AsyncOperationKind.ADVANCE;
		if ((task != null) != task_operation || (argument != null) != argument_operation) {
			return false;
		}
		if (kind == AsyncOperationKind.OPEN) {
			return executor == null && body == null && result == runtime.executor_type && argument.kind == TypeKind.INT;
		}
		if (executor == null) {
			if (body == null || body.runtime != runtime || (kind != AsyncOperationKind.START && kind != AsyncOperationKind.CANCEL)) {
				return false;
			}
		} else if (body != null || (task_type != null && task_type.success_type.kind != TypeKind.VOID)) {
			return false;
		}
		if (argument != null && argument.kind != TypeKind.U32) {
			return false;
		}
		switch (kind) {
		case AsyncOperationKind.PUMP: return result.kind == TypeKind.U32;
		case AsyncOperationKind.RUN: case AsyncOperationKind.SHUTDOWN_COMPLETE: case AsyncOperationKind.FINISH_SHUTDOWN: return result.kind == TypeKind.BOOL;
		case AsyncOperationKind.WAIT: case AsyncOperationKind.START: case AsyncOperationKind.CANCEL: case AsyncOperationKind.ADVANCE: case AsyncOperationKind.BEGIN_SHUTDOWN:
			return result.kind == TypeKind.VOID;
		default:
			return false;
		}
	}

	internal AsyncOperationContract (AsyncRuntimeIdentity runtime, AsyncOperationKind kind, SemanticType result) {
		this.runtime = runtime;
		this.kind = kind;
		this.result = result;
	}

}

}
