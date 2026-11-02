// Called inside the existing upload-user transaction. No content columns are selected.
async function historyPage(tx, userId, { limit, filter, after, ceiling }) {
  const stamp = "YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"";
  const upper = ceiling || (await tx(`SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC', '${stamp}') AS value`)).rows[0].value;
  const { rows } = await tx(`SELECT id,book_id,revision,state,is_saved,updated_at,expires_at,
      to_char(created_at AT TIME ZONE 'UTC', '${stamp}') AS created_at
    FROM reading_recaps WHERE user_id=$1 AND created_at <= $2::timestamptz
      AND ($3='all' OR ($3='saved' AND is_saved) OR ($3='preview' AND NOT is_saved))
      AND ($4::timestamptz IS NULL OR (created_at,id) < ($4::timestamptz,$5::uuid))
    ORDER BY created_at DESC,id DESC LIMIT $6`,
  [userId, upper, filter, after?.created_at ?? null, after?.id ?? null, limit + 1]);
  return { rows: rows.slice(0, limit), more: rows.length > limit, ceiling: upper };
}
module.exports = { historyPage };
