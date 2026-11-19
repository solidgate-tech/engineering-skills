# `sql` — sweep

Facts used: `sql.exec_sites`, `sql.tables_with_updated_at`.

Seeds: the driver methods and query builders in `sql.exec_sites`, SQL string literals, and `.sql` files embedded by your packages. Read every branch that contributes to a built statement.

## Types

**`sql_updated_at_missing`** · Medium — An `UPDATE` (including `ON CONFLICT … DO UPDATE`) or `INSERT` on a table listed in `sql.tables_with_updated_at` that does not set the column, when nothing in the database sets it for that statement either. For a built statement: at least one builder branch produces a statement without it.
*Not a defect:* the table lacks the column; the database sets it for this kind of statement (cite the fact) — a trigger, `ON UPDATE CURRENT_TIMESTAMP`, or the column default for a plain `INSERT`.
*Verify:* read the SQL literal / all builder branches and cross-check the table against the fact.
*Fix:* set `updated_at` in every INSERT/UPDATE branch, or let the database do it.

```go
// sql_updated_at_missing
r.db.ExecContext(ctx, "UPDATE sessions SET revoked_at=$1 WHERE id=$2", now, id)
// NOT a defect
r.db.ExecContext(ctx, "UPDATE sessions SET revoked_at=$1, updated_at=$1 WHERE id=$2", now, id)
```

**`sql_from_in_modify`** · Low · **review note, not a defect** — `UPDATE … FROM` / `DELETE … USING`: a join inside a modifying statement. This is valid SQL. It is flagged because such a statement is more complex than it reads: which rows are touched depends on the join, and in an `UPDATE`, when the join matches more than one row per target row, which one is applied is unspecified.
*Verify:* read the SQL literal / all builder branches.
*Emit:* one entry per statement, `severity: Low`, `confidence: high`. `description` says what a reviewer should check — not that the statement is wrong: for `UPDATE`, that the join yields at most one row per target row; for both, that the join and predicate touch only the intended rows. `fix_hint`: "none required if the join is intended; a sub-select may read simpler".

```sql
-- flagged for a look
UPDATE sessions s SET status = 'off' FROM users u WHERE u.id = s.user_id AND u.deleted_at IS NOT NULL;
DELETE FROM sessions s USING users u WHERE u.id = s.user_id AND u.deleted_at IS NOT NULL;
-- sub-select form of the first statement
UPDATE sessions SET status = 'off' WHERE user_id IN (SELECT id FROM users WHERE deleted_at IS NOT NULL);
```
