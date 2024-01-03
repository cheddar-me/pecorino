# frozen_string_literal: true

module Pecorino::Sqlite
  class Sanitizer < Struct.new(:connection)
    include ActiveRecord::Sanitization::ClassMethods
  end

  def state(conn:, key:, capa:, leak_rate:)
    query_params = {
      key: key.to_s,
      capa: capa.to_f,
      leak_rate: leak_rate.to_f,
      now_s: Time.now.to_f # SQLite is in-process, so having a consistent time between servers is impossible
    }
    # The `level` of the bucket is what got stored at `last_touched_at` time, and we can
    # extrapolate from it to see how many tokens have leaked out since `last_touched_at` -
    # we don't need to UPDATE the value in the bucket here
    sql = Sanitizer.new(conn).sanitize_sql_array([<<~SQL, query_params])
      SELECT
        MAX(
          0.0, MIN(
            :capa,
            t.level - ((:now_s - t.last_touched_at) * :leak_rate)
          )
        )
      FROM 
        pecorino_leaky_buckets AS t
      WHERE
        key = :key
    SQL

    # If the return value of the query is a NULL it means no such bucket exists,
    # so we assume the bucket is empty
    current_level = conn.uncached { conn.select_value(sql) } || 0.0
    [current_level, capa - current_level.abs < 0.01]
  end

  def add_tokens(conn:, key:, capa:, leak_rate:, n_tokens:)
    # Take double the time it takes the bucket to empty under normal circumstances
    # until the bucket may be deleted.
    may_be_deleted_after_seconds = (capa.to_f / leak_rate.to_f) * 2.0

    # Create the leaky bucket if it does not exist, and update
    # to the new level, taking the leak rate into account - if the bucket exists.
    query_params = {
      key: key.to_s,
      capa: capa.to_f,
      delete_after_s: may_be_deleted_after_seconds,
      leak_rate: leak_rate.to_f,
      now_s: Time.now.to_f,
      fillup: n_tokens.to_f,
      id: SecureRandom.uuid # SQLite3 does not autogenerate UUIDs
    }

    sql = Sanitizer.new(conn).sanitize_sql_array([<<~SQL, query_params])
      INSERT INTO pecorino_leaky_buckets AS t
        (id, key, last_touched_at, may_be_deleted_after, level)
      VALUES
        (
          :id,
          :key,
          :now_s, -- Precision loss must be avoided here as it is used for calculations
          DATETIME('now', '+:delete_after_s seconds'), -- Precision loss is acceptable here
          MAX(0.0,
            MIN(
              :capa,
              :fillup
            )
          )
        )
      ON CONFLICT (key) DO UPDATE SET
        last_touched_at = EXCLUDED.last_touched_at,
        may_be_deleted_after = EXCLUDED.may_be_deleted_after,
        level = MAX(0.0,
          MIN(
              :capa,
              t.level + :fillup - ((:now_s - t.last_touched_at) * :leak_rate)
          )
        )
      RETURNING
        level,
        -- Compare level to the capacity inside the DB so that we won't have rounding issues
        level >= :capa AS did_overflow
    SQL

    # Note the use of .uncached here. The AR query cache will actually see our
    # query as a repeat (since we use "select_one" for the RETURNING bit) and will not call into Postgres
    # correctly, thus the clock_timestamp() value would be frozen between calls. We don't want that here.
    # See https://stackoverflow.com/questions/73184531/why-would-postgres-clock-timestamp-freeze-inside-a-rails-unit-test
    upserted = conn.uncached { conn.select_one(sql) }
    capped_level_after_fillup, did_overflow = upserted.fetch("level"), upserted.fetch("did_overflow")
    [capped_level_after_fillup, did_overflow]
  end

  def set_block(conn:, key:, block_for:)
    query_params = {key: key.to_s, block_for: block_for.to_f}
    block_set_query = Sanitizer.new(conn).sanitize_sql_array([<<~SQL, query_params])
      INSERT INTO pecorino_blocks AS t
        (key, blocked_until)
      VALUES
        (:key, DATETIME() + ':block_for seconds'::interval)
      ON CONFLICT (key) DO UPDATE SET
        blocked_until = MAX(EXCLUDED.blocked_until, t.blocked_until)
      RETURNING blocked_until;
    SQL
    conn.uncached { conn.select_value(block_set_query) }
  end

  extend self
end
