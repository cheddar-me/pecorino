# frozen_string_literal: true

# An adapter allows Pecorino throttles, leaky buckets and other
# resources to interfact to a data storage backend - a database, usually.
class Pecorino::Adapters::BaseAdapter
  # Returns the state of a leaky bucket. The state should be a tuple of two
  # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
  #
  # @param key[String] the key of the leaky bucket
  # @param capacity[Float] the capacity of the leaky bucket to limit to
  # @param leak_rate[Float] how many tokens leak out of the bucket per second
  # @return [Array]
  def state(key:, capacity:, leak_rate:)
    [0, false]
  end

  # Adds tokens to the leaky bucket. The return value is a tuple of two
  # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
  #
  # @param key[String] the key of the leaky bucket
  # @param capacity[Float] the capacity of the leaky bucket to limit to
  # @param leak_rate[Float] how many tokens leak out of the bucket per second
  # @param n_tokens[Float] how many tokens to add
  # @return [Array]
  def add_tokens(key:, capacity:, leak_rate:, n_tokens:)
    [0, false]
  end

  # Adds tokens to the leaky bucket conditionally. If there is capacity, the tokens will
  # be added. If there isn't - the fillup will be rejected. The return value is a triplet of
  # the current level (Float), whether the bucket is now at capacity (Boolean)
  # and whether the fillup was accepted (Boolean)
  #
  # @param key[String] the key of the leaky bucket
  # @param capacity[Float] the capacity of the leaky bucket to limit to
  # @param leak_rate[Float] how many tokens leak out of the bucket per second
  # @param n_tokens[Float] how many tokens to add
  # @return [Array]
  def add_tokens_conditionally(key:, capacity:, leak_rate:, n_tokens:)
    [0, false, false]
  end

  # Sets a timed block for the given key - this is used when a throttle fires. The return value
  # is not defined - the call should always succeed.
  # @param key[String] the key of the block
  # @param block_for[#to_f, Active Support Duration] the duration of the block, in seconds
  def set_block(key:, block_for:)
  end

  # Returns the time until which a block for a given key is in effect. If there is no block in
  # effect, the method should return `nil`. The return value is either a `Time` or `nil`
  # @param key[String] the key of the block
  def blocked_until(key:)
  end

  # Deletes leaky buckets which have an expiry value prior to now and throttle blocks which have
  # now lapsed
  # @return [void]
  def prune
  end

  # Creates the database tables for Pecorino to operate, or initializes other
  # schema-like resources the adapter needs to operate
  def create_tables(active_record_schema)
  end
end
