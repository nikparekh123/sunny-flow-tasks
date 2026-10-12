/**
 * Read every row of a query, 1,000 at a time.
 *
 * ⚠ PostgREST returns at most 1,000 rows a request, silently. option_trades
 * crossed 1,000 on 9 Oct 2026 and every page that read it in one request lost
 * its newest legs. `make` must build the query with a deterministic order
 * (end it on a unique column such as id) so pages neither overlap nor skip.
 */
export async function fetchAll<T>(
  make: () => { range: (from: number, to: number) => PromiseLike<{ data: unknown; error: unknown }> },
  pageSize = 1000,
): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; from < 200_000; from += pageSize) {
    const { data, error } = await make().range(from, from + pageSize - 1);
    if (error) throw error;
    const rows = (data ?? []) as T[];
    out.push(...rows);
    if (rows.length < pageSize) break;
  }
  return out;
}
