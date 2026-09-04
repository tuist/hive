# Ingestion (Context)

Owns per-table ClickHouse ingestion buffers. Ported from
`Tuist.Ingestion` in `../tuist/server` — same shape, same API, so
anything already familiar with the tuist pattern applies here.

## Responsibilities
- Buffer RowBinary inserts in memory and flush on size, time, or
  shutdown.
- Provide a GenServer interface for fire-and-forget async insert plus
  an explicit flush.
- Auto-generate a `<Schema>.Buffer` submodule when a schema declares
  `use Hive.Ingestion.Bufferable`.

## Semantics
- `Buffer.insert/2` is a `GenServer.cast` — the caller does not know
  whether the row eventually lands in ClickHouse. Flush failures are
  logged and the batch is dropped. Callers must be OK with this and
  document the acceptance semantics at their public boundary
  (e.g., `Hive.Errors` documents 200 = "accepted for ingest").
- `sync_writes` config flag flips `insert/2` to a synchronous
  `{:insert_and_flush, ...}` call — for tests that need immediate
  visibility.
- `write_through_repo` config flag bypasses the buffer entirely and
  writes through `Hive.IngestRepo.insert_all/3` — for debugging.

## Boundaries
- Not for query/read paths — `Hive.ClickHouseRepo` still owns those.
- Not for Postgres writes — those go through `Hive.Repo`.

## Wiring
Add each schema's Buffer to the application supervisor:

    Supervisor.child_spec(MySchema.Buffer, id: MySchema.Buffer)

Flush intervals and buffer size defaults live under
`config :hive, Hive.IngestRepo` in `config/runtime.exs`.
