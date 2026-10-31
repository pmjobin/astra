// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "astra_async_worker_pool_close")]
handle WorkerPool;
[CCode(cname = "astra_async_worker_pool_open")]
owned WorkerPool worker_pool(int workers);
[CCode(cname = "astra_async_worker_pool_request_shutdown")]
int request_worker_pool_shutdown(borrowed WorkerPool pool);
