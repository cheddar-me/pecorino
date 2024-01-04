# frozen_string_literal: true

class Pecorino::Postgres < Struct.new(:model_class)
  def state(key:, capa:, leak_rate:)
    query_params = {
      key: key.to_s,
      capa: capa.to_f,
      leak_rate: leak_rate.to_f
    }
    # The `level` of the bucket is what got stored at `last_touched_at` time, and we can
    # extrapolate from it to see how many tokens have leaked out since `last_touched_at` -
    # we don't need to UPDATE the value in the bucket here
    sql = model_class.sanitize_sql_array([<<~SQL, query_params])
      SELECT
        GREATEST(
          0.0, LEAST(
            :capa,
            t.level - (EXTRACT(EPOCH FROM (clock_timestamp() - t.last_touched_at)) * :leak_rate)
          )
        )
      FROM 
        pecorino_leaky_buckets AS t
      WHERE
        key = :key
    SQL

    # If the return value of the query is a NULL it means no such bucket exists,
    # so we assume the bucket is empty
    current_level = model_class.connection.uncached { model_class.connection.select_value(sql) } || 0.0
    [current_level, capa - current_level.abs < 0.01]
  end

  def add_tokens(key:, capa:, leak_rate:, n_tokens:)
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
      fillup: n_tokens.to_f
    }

    sql = model_class.sanitize_sql_array([<<~SQL, query_params])
      INSERT INTO pecorino_leaky_buckets AS t
        (key, last_touched_at, may_be_deleted_after, level)
      VALUES
        (
          :key,
          clock_timestamp(),
          clock_timestamp() + ':delete_after_s second'::interval,
          GREATEST(0.0,
            LEAST(
              :capa,
              :fillup
            )
          )
        )
      ON CONFLICT (key) DO UPDATE SET
        last_touched_at = EXCLUDED.last_touched_at,
        may_be_deleted_after = EXCLUDED.may_be_deleted_after,
        level = GREATEST(0.0,
          LEAST(
              :capa,
              t.level + :fillup - (EXTRACT(EPOCH FROM (EXCLUDED.last_touched_at - t.last_touched_at)) * :leak_rate)
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
    upserted = model_class.connection.uncached { model_class.connection.select_one(sql) }
    capped_level_after_fillup, did_overflow = upserted.fetch("level"), upserted.fetch("did_overflow")
    [capped_level_after_fillup, did_overflow]
  end

  def set_block(key:, block_for:)
    query_params = {key: key.to_s, block_for: block_for.to_f}
    block_set_query = model_class.sanitize_sql_array([<<~SQL, query_params])
      INSERT INTO pecorino_blocks AS t
        (key, blocked_until)
      VALUES
        (:key, NOW() + ':block_for seconds'::interval)
      ON CONFLICT (key) DO UPDATE SET
        blocked_until = GREATEST(EXCLUDED.blocked_until, t.blocked_until)
      RETURNING blocked_until;
    SQL
    model_class.connection.uncached { model_class.connection.select_value(block_set_query) }
  end

  def blocked_until(key:)
    # This query is database-agnostic, so it is not in the various database modules
    block_check_query = model_class.sanitize_sql_array([<<~SQL, key])
      SELECT blocked_until FROM pecorino_blocks WHERE key = ? AND blocked_until >= NOW() LIMIT 1
    SQL
    model_class.connection.uncached { model_class.connection.select_value(block_check_query) }
  end
end
