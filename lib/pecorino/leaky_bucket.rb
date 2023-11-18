# frozen_string_literal: true

# This offers just the leaky bucket implementation with fill control, but without the timed lock.
# It does not raise any exceptions, it just tracks the state of a leaky bucket in Postgres.
#
# Leak rate is specified directly in tokens per second, instead of specifying the block period.
# The bucket level is stored and returned as a Float which allows for finer-grained measurement,
# but more importantly - makes testing from the outside easier.
#
# Note that this implementation has a peculiar property: the bucket is only "full" once it overflows.
# Due to a leak rate just a few microseconds after that moment the bucket is no longer going to be full
# anymore as it will have leaked some tokens by then. This means that the information about whether a
# bucket has become full or not gets returned in the bucket `State` struct right after the database
# update gets executed, and if your code needs to make decisions based on that data it has to use
# this returned state, not query the leaky bucket again. Specifically:
#
#     state = bucket.fillup(1) # Record 1 request
#     state.full? #=> true, this is timely information
#
# ...is the correct way to perform the check. This, however, is not:
#
#     bucket.fillup(1)
#     bucket.state.full? #=> false, some time has passed after the topup and some tokens have already leaked
#
# The storage use is one DB row per leaky bucket you need to manage (likely - one throttled entity such
# as a combination of an IP address + the URL you need to procect). The `key` is an arbitrary string you provide.
class Pecorino::LeakyBucket
  State = Struct.new(:level, :full) do
    # Returns the level of the bucket after the operation on the LeakyBucket
    # object has taken place. There is a guarantee that no tokens have leaked
    # from the bucket between the operation and the freezing of the State
    # struct.
    #
    # @!attribute [r] level
    #   @return [Float]

    # Tells whether the bucket was detected to be full when the operation on
    # the LeakyBucket was performed. There is a guarantee that no tokens have leaked
    # from the bucket between the operation and the freezing of the State
    # struct.
    #
    # @!attribute [r] full
    #   @return [Boolean]

    alias_method :full?, :full

    # Returns the bucket level of the bucket state as a Float
    #
    # @return [Float]
    def to_f
      level.to_f
    end

    # Returns the bucket level of the bucket state rounded to an Integer
    #
    # @return [Integer]
    def to_i
      level.to_i
    end
  end

  # Creates a new LeakyBucket. The object controls 1 row in Postgres which is
  # specific to the bucket key.
  #
  # @param key[String] the key for the bucket. The key also gets used
  #   to derive locking keys, so that operations on a particular bucket
  #   are always serialized.
  # @param leak_rate[Float] the leak rate of the bucket, in tokens per second
  # @param capacity[Numeric] how many tokens is the bucket capped at.
  #   Filling up the bucket using `fillup()` will add to that number, but
  #   the bucket contents will then be capped at this value. So with
  #   bucket_capacity set to 12 and a `fillup(14)` the bucket will reach the level
  #   of 12, and will then immediately start leaking again.
  def initialize(key:, leak_rate:, capacity:)
    @key = key
    @leak_rate = leak_rate.to_f
    @capacity = capacity.to_f
  end

  # Places `n` tokens in the bucket. Once tokens are placed, the bucket is set to expire
  # within 2 times the time it would take it to leak to 0, regardless of how many tokens
  # get put in - since the amount of tokens put in the bucket will always be capped
  # to the `capacity:` value you pass to the constructor. Calling `fillup` also deletes
  # leaky buckets which have expired.
  #
  # @param n_tokens[Float]
  # @return [State] the state of the bucket after the operation
  def fillup(n_tokens)
    add_tokens(n_tokens.to_f)
  end

  # Returns the current state of the bucket, containing the level and whether the bucket is full.
  # Calling this method will not perform any database writes.
  #
  # @return [State] the snapshotted state of the bucket at time of query
  def state
    conn = ActiveRecord::Base.connection
    query_params = {
      key: @key,
      capa: @capacity.to_f,
      leak_rate: @leak_rate.to_f
    }
    # The `level` of the bucket is what got stored at `last_touched_at` time, and we can
    # extrapolate from it to see how many tokens have leaked out since `last_touched_at` -
    # we don't need to UPDATE the value in the bucket here
    sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL, query_params])
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
    current_level = conn.uncached { conn.select_value(sql) } || 0.0

    State.new(current_level, (@capacity - current_level).abs < 0.01)
  end

  # Tells whether the bucket can accept the amount of tokens without overflowing.
  # Calling this method will not perform any database writes. Note that this call is
  # not race-safe - another caller may still overflow the bucket. Before performing
  # your action, you still need to call `fillup()` - but you can preemptively refuse
  # a request if you already know the bucket is full.
  #
  # @param n_tokens[Float]
  # @return [boolean]
  def able_to_accept?(n_tokens)
    (state.level + n_tokens) < @capacity
  end

  private

  def add_tokens(n_tokens)
    conn = ActiveRecord::Base.connection

    # Take double the time it takes the bucket to empty under normal circumstances
    # until the bucket may be deleted.
    may_be_deleted_after_seconds = (@capacity.to_f / @leak_rate.to_f) * 2.0

    # Create the leaky bucket if it does not exist, and update
    # to the new level, taking the leak rate into account - if the bucket exists.
    query_params = {
      key: @key,
      capa: @capacity.to_f,
      delete_after_s: may_be_deleted_after_seconds,
      leak_rate: @leak_rate.to_f,
      fillup: n_tokens.to_f
    }
    sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL, query_params])
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
      RETURNING level
    SQL

    # Note the use of .uncached here. The AR query cache will actually see our
    # query as a repeat (since we use "select_value" for the RETURNING bit) and will not call into Postgres
    # correctly, thus the clock_timestamp() value would be frozen between calls. We don't want that here.
    # See https://stackoverflow.com/questions/73184531/why-would-postgres-clock-timestamp-freeze-inside-a-rails-unit-test
    level_after_fillup = conn.uncached { conn.select_value(sql) }

    State.new(level_after_fillup, (@capacity - level_after_fillup).abs < 0.01)
  end
end
