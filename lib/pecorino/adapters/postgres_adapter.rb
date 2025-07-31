# frozen_string_literal: true

class Pecorino::Adapters::PostgresAdapter
  def initialize(model_class)
    @model_class = model_class
  end

  def state(key:, capacity:, leak_rate:)
    query_params = {
      key: key.to_s,
      capacity: capacity.to_f,
      leak_rate: leak_rate.to_f
    }
    # The `level` of the bucket is what got stored at `last_touched_at` time, and we can
    # extrapolate from it to see how many tokens have leaked out since `last_touched_at` -
    # we don't need to UPDATE the value in the bucket here
    sql = @model_class.sanitize_sql_array([<<~SQL, query_params])
      SELECT
        GREATEST(
          0.0, LEAST(
            :capacity,
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
    current_level = @model_class.with_connection { |connection| connection.uncached { connection.select_value(sql) } } || 0.0
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
      fillup: n_tokens.to_f
    }

    sql = @model_class.sanitize_sql_array([<<~SQL, query_params])
      INSERT INTO pecorino_leaky_buckets AS t
        (key, last_touched_at, may_be_deleted_after, level)
      VALUES
        (
          :key,
          clock_timestamp(),
          clock_timestamp() + ':delete_after_s second'::interval,
          GREATEST(0.0,
            LEAST(
              :capacity,
              :fillup
            )
          )
        )
      ON CONFLICT (key) DO UPDATE SET
        last_touched_at = EXCLUDED.last_touched_at,
        may_be_deleted_after = EXCLUDED.may_be_deleted_after,
        level = GREATEST(0.0,
          LEAST(
              :capacity,
              t.level + :fillup - (EXTRACT(EPOCH FROM (EXCLUDED.last_touched_at - t.last_touched_at)) * :leak_rate)
          )
        )
      RETURNING
        level,
        -- Compare level to the capacity inside the DB so that we won't have rounding issues
        level >= :capacity AS at_capacity
    SQL

    # Note the use of .uncached here. The AR query cache will actually see our
    # query as a repeat (since we use "select_one" for the RETURNING bit) and will not call into Postgres
    # correctly, thus the clock_timestamp() value would be frozen between calls. We don't want that here.
    # See https://stackoverflow.com/questions/73184531/why-would-postgres-clock-timestamp-freeze-inside-a-rails-unit-test
    upserted = @model_class.with_connection { |connection| connection.uncached { connection.select_one(sql) } }
    capped_level_after_fillup, at_capacity = upserted.fetch("level"), upserted.fetch("at_capacity")
    [capped_level_after_fillup, at_capacity]
  end

  def add_tokens_conditionally(key:, capacity:, leak_rate:, n_tokens:)
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
      fillup: n_tokens.to_f
    }

    sql = @model_class.sanitize_sql_array([<<~SQL, query_params])
      WITH pre AS MATERIALIZED (
        SELECT
          -- Note the double clamping here. First we clamp the "current level - leak" to not go below zero,
          -- then we also clamp the above + fillup to not go below 0
          GREATEST(0.0, 
              GREATEST(0.0, level - (EXTRACT(EPOCH FROM (clock_timestamp() - last_touched_at)) * :leak_rate)) + :fillup
          ) AS level_post_with_uncapped_fillup,
          GREATEST(0.0,
              level - (EXTRACT(EPOCH FROM (clock_timestamp() - last_touched_at)) * :leak_rate)
          ) AS level_post
        FROM pecorino_leaky_buckets
        WHERE key = :key
      )
      INSERT INTO pecorino_leaky_buckets AS t
        (key, last_touched_at, may_be_deleted_after, level)
      VALUES
        (
          :key,
          clock_timestamp(),
          clock_timestamp() + ':delete_after_s second'::interval,
          GREATEST(0.0,
            (CASE WHEN :fillup > :capacity THEN 0.0 ELSE :fillup END)
          )
        )
      ON CONFLICT (key) DO UPDATE SET
        last_touched_at = EXCLUDED.last_touched_at,
        may_be_deleted_after = EXCLUDED.may_be_deleted_after,
        level = CASE WHEN (SELECT level_post_with_uncapped_fillup FROM pre) <= :capacity THEN
          (SELECT level_post_with_uncapped_fillup FROM pre)
        ELSE
          (SELECT level_post FROM pre)
        END
      RETURNING
        COALESCE((SELECT level_post FROM pre), 0.0) AS level_before,
        level AS level_after
    SQL

    upserted = @model_class.with_connection { |connection| connection.uncached { connection.select_one(sql) } }
    level_after = upserted.fetch("level_after")
    level_before = upserted.fetch("level_before")
    [level_after, level_after >= capacity, level_after != level_before]
  end

  def set_block(key:, block_for:)
    raise ArgumentError, "block_for must be positive" unless block_for > 0
    query_params = {key: key.to_s, block_for: block_for.to_f}
    block_set_query = @model_class.sanitize_sql_array([<<~SQL, query_params])
      INSERT INTO pecorino_blocks AS t
        (key, blocked_until)
      VALUES
        (:key, clock_timestamp() + ':block_for seconds'::interval)
      ON CONFLICT (key) DO UPDATE SET
        blocked_until = GREATEST(EXCLUDED.blocked_until, t.blocked_until)
      RETURNING blocked_until
    SQL
    @model_class.with_connection { |connection| connection.uncached { connection.select_value(block_set_query) } }
  end

  def blocked_until(key:)
    block_check_query = @model_class.sanitize_sql_array([<<~SQL, key])
      SELECT blocked_until FROM pecorino_blocks WHERE key = ? AND blocked_until >= clock_timestamp() LIMIT 1
    SQL
    @model_class.with_connection { |connection| connection.uncached { connection.select_value(block_check_query) } }
  end

  def prune
    @model_class.with_connection do |connection|
      connection.execute("DELETE FROM pecorino_blocks WHERE blocked_until < NOW()")
      connection.execute("DELETE FROM pecorino_leaky_buckets WHERE may_be_deleted_after < NOW()")
    end
  end

  def create_tables(active_record_schema)
    active_record_schema.create_table :pecorino_leaky_buckets, id: :uuid do |t|
      t.string :key, null: false
      t.float :level, null: false
      t.datetime :last_touched_at, null: false
      t.datetime :may_be_deleted_after, null: false
    end
    active_record_schema.add_index :pecorino_leaky_buckets, [:key], unique: true
    active_record_schema.add_index :pecorino_leaky_buckets, [:may_be_deleted_after]

    active_record_schema.create_table :pecorino_blocks, id: :uuid do |t|
      t.string :key, null: false
      t.datetime :blocked_until, null: false
    end
    active_record_schema.add_index :pecorino_blocks, [:key], unique: true
    active_record_schema.add_index :pecorino_blocks, [:blocked_until]
  end
end
