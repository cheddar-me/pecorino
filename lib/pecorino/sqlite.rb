# frozen_string_literal: true

Pecorino::Sqlite = Struct.new(:model_class) do
  def state(key:, capacity:, leak_rate:)
    # With a server database, it is really important to use the clock of the database itself so
    # that concurrent requests will see consistent bucket level calculations. Since SQLite is
    # actually in-process, there is no point using DB functions - and besides, SQLite reduces
    # the time precision to the nearest millisecond - and the calculations with timestamps are
    # obtuse. Therefore we can use the current time inside the Ruby VM - it doesn't matter all that
    # much but saves us on writing some gnarly SQL to have SQLite produce consistent precise timestamps.
    query_params = {
      key: key.to_s,
      capacity: capacity.to_f,
      leak_rate: leak_rate.to_f,
      now_s: Time.now.to_f
    }
    # The `level` of the bucket is what got stored at `last_touched_at` time, and we can
    # extrapolate from it to see how many tokens have leaked out since `last_touched_at` -
    # we don't need to UPDATE the value in the bucket here
    sql = model_class.sanitize_sql_array([<<~SQL, query_params])
      SELECT
        MAX(
          0.0, MIN(
            :capacity,
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
    current_level = model_class.connection.uncached { model_class.connection.select_value(sql) } || 0.0
    [current_level, capacity - current_level.abs < 0.01]
  end

  def add_tokens(key:, capacity:, leak_rate:, n_tokens:)
    # Take double the time it takes the bucket to empty under normal circumstances
    # until the bucket may be deleted.
    may_be_deleted_after_seconds = (capacity.to_f / leak_rate.to_f) * 2.0

    # Create the leaky bucket if it does not exist, and update
    # to the new level, taking the leak rate into account - if the bucket exists.
    query_params = {
      key: key.to_s,
      capacity: capacity.to_f,
      delete_after_s: may_be_deleted_after_seconds,
      leak_rate: leak_rate.to_f,
      now_s: Time.now.to_f, # See above as to why we are using a time value passed in
      fillup: n_tokens.to_f,
      id: SecureRandom.uuid # SQLite3 does not autogenerate UUIDs
    }

    sql = model_class.sanitize_sql_array([<<~SQL, query_params])
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
              :capacity,
              :fillup
            )
          )
        )
      ON CONFLICT (key) DO UPDATE SET
        last_touched_at = EXCLUDED.last_touched_at,
        may_be_deleted_after = EXCLUDED.may_be_deleted_after,
        level = MAX(0.0,
          MIN(
              :capacity,
              t.level + :fillup - ((:now_s - t.last_touched_at) * :leak_rate)
          )
        )
      RETURNING
        level,
        -- Compare level to the capacity inside the DB so that we won't have rounding issues
        level >= :capacity AS did_overflow
    SQL

    # Note the use of .uncached here. The AR query cache will actually see our
    # query as a repeat (since we use "select_one" for the RETURNING bit) and will not call into Postgres
    # correctly, thus the clock_timestamp() value would be frozen between calls. We don't want that here.
    # See https://stackoverflow.com/questions/73184531/why-would-postgres-clock-timestamp-freeze-inside-a-rails-unit-test
    upserted = model_class.connection.uncached { model_class.connection.select_one(sql) }
    capped_level_after_fillup, one_if_did_overflow = upserted.fetch("level"), upserted.fetch("did_overflow")
    [capped_level_after_fillup, one_if_did_overflow == 1]
  end

  def set_block(key:, block_for:)
    query_params = {id: SecureRandom.uuid, key: key.to_s, block_for: block_for.to_f, now_s: Time.now.to_f}
    block_set_query = model_class.sanitize_sql_array([<<~SQL, query_params])
      INSERT INTO pecorino_blocks AS t
        (id, key, blocked_until)
      VALUES
        (:id, :key, :now_s + :block_for)
      ON CONFLICT (key) DO UPDATE SET
        blocked_until = MAX(EXCLUDED.blocked_until, t.blocked_until)
      RETURNING blocked_until;
    SQL
    blocked_until_s = model_class.connection.uncached { model_class.connection.select_value(block_set_query) }
    Time.at(blocked_until_s)
  end

  def blocked_until(key:)
    now_s = Time.now.to_f
    block_check_query = model_class.sanitize_sql_array([<<~SQL, {now_s: now_s, key: key}])
      SELECT
        blocked_until
      FROM
        pecorino_blocks
      WHERE
        key = :key AND blocked_until >= :now_s LIMIT 1
    SQL
    blocked_until_s = model_class.connection.uncached { model_class.connection.select_value(block_check_query) }
    blocked_until_s && Time.at(blocked_until_s)
  end
end
