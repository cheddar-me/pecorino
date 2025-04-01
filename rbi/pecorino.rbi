# typed: strong
module Pecorino
  VERSION = T.let("0.7.1", T.untyped)

  # Deletes stale leaky buckets and blocks which have expired. Run this method regularly to
  # avoid accumulating too many unused rows in your tables.
  # 
  # _@return_ — void
  sig { returns(T.untyped) }
  def self.prune!; end

  # sord warn - ActiveRecord::SchemaMigration wasn't able to be resolved to a constant in this project
  # Creates the tables and indexes needed for Pecorino. Call this from your migrations like so:
  # 
  #     class CreatePecorinoTables < ActiveRecord::Migration[7.0]
  #       def change
  #         Pecorino.create_tables(self)
  #       end
  #     end
  # 
  # _@param_ `active_record_schema` — the migration through which we will create the tables
  # 
  # _@return_ — void
  sig { params(active_record_schema: ActiveRecord::SchemaMigration).returns(T.untyped) }
  def self.create_tables(active_record_schema); end

  # Allows assignment of an adapter for storing throttles. Normally this would be a subclass of `Pecorino::Adapters::BaseAdapter`, but
  # you can assign anything you like. Set this in an initializer. By default Pecorino will use the adapter configured from your main
  # database, but you can also create a separate database for it - or use Redis or memory storage.
  # 
  # _@param_ `adapter`
  sig { params(adapter: Pecorino::Adapters::BaseAdapter).returns(Pecorino::Adapters::BaseAdapter) }
  def self.adapter=(adapter); end

  # Returns the currently configured adapter, or the default adapter from the main database
  sig { returns(Pecorino::Adapters::BaseAdapter) }
  def self.adapter; end

  # sord omit - no YARD return type given, using untyped
  # Returns the database implementation for setting the values atomically. Since the implementation
  # differs per database, this method will return a different adapter depending on which database is
  # being used
  # 
  # _@param_ `adapter`
  sig { returns(T.untyped) }
  def self.default_adapter_from_main_database; end

  module Adapters
    # An adapter allows Pecorino throttles, leaky buckets and other
    # resources to interfact to a data storage backend - a database, usually.
    class BaseAdapter
      # Returns the state of a leaky bucket. The state should be a tuple of two
      # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
      # 
      # _@param_ `key` — the key of the leaky bucket
      # 
      # _@param_ `capacity` — the capacity of the leaky bucket to limit to
      # 
      # _@param_ `leak_rate` — how many tokens leak out of the bucket per second
      sig { params(key: String, capacity: Float, leak_rate: Float).returns(T::Array[T.untyped]) }
      def state(key:, capacity:, leak_rate:); end

      # Adds tokens to the leaky bucket. The return value is a tuple of two
      # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
      # 
      # _@param_ `key` — the key of the leaky bucket
      # 
      # _@param_ `capacity` — the capacity of the leaky bucket to limit to
      # 
      # _@param_ `leak_rate` — how many tokens leak out of the bucket per second
      # 
      # _@param_ `n_tokens` — how many tokens to add
      sig do
        params(
          key: String,
          capacity: Float,
          leak_rate: Float,
          n_tokens: Float
        ).returns(T::Array[T.untyped])
      end
      def add_tokens(key:, capacity:, leak_rate:, n_tokens:); end

      # Adds tokens to the leaky bucket conditionally. If there is capacity, the tokens will
      # be added. If there isn't - the fillup will be rejected. The return value is a triplet of
      # the current level (Float), whether the bucket is now at capacity (Boolean)
      # and whether the fillup was accepted (Boolean)
      # 
      # _@param_ `key` — the key of the leaky bucket
      # 
      # _@param_ `capacity` — the capacity of the leaky bucket to limit to
      # 
      # _@param_ `leak_rate` — how many tokens leak out of the bucket per second
      # 
      # _@param_ `n_tokens` — how many tokens to add
      sig do
        params(
          key: String,
          capacity: Float,
          leak_rate: Float,
          n_tokens: Float
        ).returns(T::Array[T.untyped])
      end
      def add_tokens_conditionally(key:, capacity:, leak_rate:, n_tokens:); end

      # sord duck - #to_f looks like a duck type, replacing with untyped
      # sord warn - "Active Support Duration" does not appear to be a type
      # sord omit - no YARD return type given, using untyped
      # Sets a timed block for the given key - this is used when a throttle fires. The return value
      # is not defined - the call should always succeed.
      # 
      # _@param_ `key` — the key of the block
      # 
      # _@param_ `block_for` — the duration of the block, in seconds
      sig { params(key: String, block_for: T.any(T.untyped, SORD_ERROR_ActiveSupportDuration)).returns(T.untyped) }
      def set_block(key:, block_for:); end

      # sord omit - no YARD return type given, using untyped
      # Returns the time until which a block for a given key is in effect. If there is no block in
      # effect, the method should return `nil`. The return value is either a `Time` or `nil`
      # 
      # _@param_ `key` — the key of the block
      sig { params(key: String).returns(T.untyped) }
      def blocked_until(key:); end

      # Deletes leaky buckets which have an expiry value prior to now and throttle blocks which have
      # now lapsed
      sig { void }
      def prune; end

      # sord omit - no YARD type given for "active_record_schema", using untyped
      # sord omit - no YARD return type given, using untyped
      # Creates the database tables for Pecorino to operate, or initializes other
      # schema-like resources the adapter needs to operate
      sig { params(active_record_schema: T.untyped).returns(T.untyped) }
      def create_tables(active_record_schema); end
    end

    # An adapter for storing Pecorino leaky buckets and blocks in Redis. It uses Lua
    # to enforce atomicity for leaky bucket operations
    class RedisAdapter < Pecorino::Adapters::BaseAdapter
      ADD_TOKENS_SCRIPT = T.let(RedisScript.new("add_tokens_conditionally.lua"), T.untyped)

      # sord omit - no YARD type given for "redis_connection_or_connection_pool", using untyped
      # sord omit - no YARD type given for "key_prefix:", using untyped
      sig { params(redis_connection_or_connection_pool: T.untyped, key_prefix: T.untyped).void }
      def initialize(redis_connection_or_connection_pool, key_prefix: "pecorino"); end

      # Returns the state of a leaky bucket. The state should be a tuple of two
      # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
      sig { params(key: String, capacity: Float, leak_rate: Float).returns(T::Array[T.untyped]) }
      def state(key:, capacity:, leak_rate:); end

      # Adds tokens to the leaky bucket. The return value is a tuple of two
      # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
      sig do
        params(
          key: String,
          capacity: Float,
          leak_rate: Float,
          n_tokens: Float
        ).returns(T::Array[T.untyped])
      end
      def add_tokens(key:, capacity:, leak_rate:, n_tokens:); end

      # Adds tokens to the leaky bucket conditionally. If there is capacity, the tokens will
      # be added. If there isn't - the fillup will be rejected. The return value is a triplet of
      # the current level (Float), whether the bucket is now at capacity (Boolean)
      # and whether the fillup was accepted (Boolean)
      sig do
        params(
          key: String,
          capacity: Float,
          leak_rate: Float,
          n_tokens: Float
        ).returns(T::Array[T.untyped])
      end
      def add_tokens_conditionally(key:, capacity:, leak_rate:, n_tokens:); end

      # sord duck - #to_f looks like a duck type, replacing with untyped
      # sord warn - "Active Support Duration" does not appear to be a type
      # sord omit - no YARD return type given, using untyped
      # Sets a timed block for the given key - this is used when a throttle fires. The return value
      # is not defined - the call should always succeed.
      sig { params(key: String, block_for: T.any(T.untyped, SORD_ERROR_ActiveSupportDuration)).returns(T.untyped) }
      def set_block(key:, block_for:); end

      # sord omit - no YARD return type given, using untyped
      # Returns the time until which a block for a given key is in effect. If there is no block in
      # effect, the method should return `nil`. The return value is either a `Time` or `nil`
      sig { params(key: String).returns(T.untyped) }
      def blocked_until(key:); end

      # sord omit - no YARD return type given, using untyped
      sig { returns(T.untyped) }
      def with_redis; end

      class RedisScript
        # sord omit - no YARD type given for "script_filename", using untyped
        sig { params(script_filename: T.untyped).void }
        def initialize(script_filename); end

        # sord omit - no YARD type given for "redis", using untyped
        # sord omit - no YARD type given for "keys", using untyped
        # sord omit - no YARD type given for "argv", using untyped
        # sord omit - no YARD return type given, using untyped
        sig { params(redis: T.untyped, keys: T.untyped, argv: T.untyped).returns(T.untyped) }
        def load_and_eval(redis, keys, argv); end
      end
    end

    # A memory store for leaky buckets and blocks
    class MemoryAdapter
      sig { void }
      def initialize; end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "capacity:", using untyped
      # sord omit - no YARD type given for "leak_rate:", using untyped
      # sord omit - no YARD return type given, using untyped
      # Returns the state of a leaky bucket. The state should be a tuple of two
      # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
      sig { params(key: T.untyped, capacity: T.untyped, leak_rate: T.untyped).returns(T.untyped) }
      def state(key:, capacity:, leak_rate:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "capacity:", using untyped
      # sord omit - no YARD type given for "leak_rate:", using untyped
      # sord omit - no YARD type given for "n_tokens:", using untyped
      # sord omit - no YARD return type given, using untyped
      # Adds tokens to the leaky bucket. The return value is a tuple of two
      # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
      sig do
        params(
          key: T.untyped,
          capacity: T.untyped,
          leak_rate: T.untyped,
          n_tokens: T.untyped
        ).returns(T.untyped)
      end
      def add_tokens(key:, capacity:, leak_rate:, n_tokens:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "capacity:", using untyped
      # sord omit - no YARD type given for "leak_rate:", using untyped
      # sord omit - no YARD type given for "n_tokens:", using untyped
      # sord omit - no YARD return type given, using untyped
      # Adds tokens to the leaky bucket conditionally. If there is capacity, the tokens will
      # be added. If there isn't - the fillup will be rejected. The return value is a triplet of
      # the current level (Float), whether the bucket is now at capacity (Boolean)
      # and whether the fillup was accepted (Boolean)
      sig do
        params(
          key: T.untyped,
          capacity: T.untyped,
          leak_rate: T.untyped,
          n_tokens: T.untyped
        ).returns(T.untyped)
      end
      def add_tokens_conditionally(key:, capacity:, leak_rate:, n_tokens:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "block_for:", using untyped
      # sord omit - no YARD return type given, using untyped
      # Sets a timed block for the given key - this is used when a throttle fires. The return value
      # is not defined - the call should always succeed.
      sig { params(key: T.untyped, block_for: T.untyped).returns(T.untyped) }
      def set_block(key:, block_for:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD return type given, using untyped
      # Returns the time until which a block for a given key is in effect. If there is no block in
      # effect, the method should return `nil`. The return value is either a `Time` or `nil`
      sig { params(key: T.untyped).returns(T.untyped) }
      def blocked_until(key:); end

      # sord omit - no YARD return type given, using untyped
      # Deletes leaky buckets which have an expiry value prior to now and throttle blocks which have
      # now lapsed
      sig { returns(T.untyped) }
      def prune; end

      # sord omit - no YARD type given for "active_record_schema", using untyped
      # sord omit - no YARD return type given, using untyped
      # No-op
      sig { params(active_record_schema: T.untyped).returns(T.untyped) }
      def create_tables(active_record_schema); end

      # sord omit - no YARD type given for "key", using untyped
      # sord omit - no YARD type given for "capacity", using untyped
      # sord omit - no YARD type given for "leak_rate", using untyped
      # sord omit - no YARD type given for "n_tokens", using untyped
      # sord omit - no YARD type given for "conditionally", using untyped
      # sord omit - no YARD return type given, using untyped
      sig do
        params(
          key: T.untyped,
          capacity: T.untyped,
          leak_rate: T.untyped,
          n_tokens: T.untyped,
          conditionally: T.untyped
        ).returns(T.untyped)
      end
      def add_tokens_with_lock(key, capacity, leak_rate, n_tokens, conditionally); end

      # sord omit - no YARD return type given, using untyped
      sig { returns(T.untyped) }
      def get_mono_time; end

      # sord omit - no YARD type given for "min", using untyped
      # sord omit - no YARD type given for "value", using untyped
      # sord omit - no YARD type given for "max", using untyped
      # sord omit - no YARD return type given, using untyped
      sig { params(min: T.untyped, value: T.untyped, max: T.untyped).returns(T.untyped) }
      def clamp(min, value, max); end

      class KeyedLock
        sig { void }
        def initialize; end

        # sord omit - no YARD type given for "key", using untyped
        # sord omit - no YARD return type given, using untyped
        sig { params(key: T.untyped).returns(T.untyped) }
        def lock(key); end

        # sord omit - no YARD type given for "key", using untyped
        # sord omit - no YARD return type given, using untyped
        sig { params(key: T.untyped).returns(T.untyped) }
        def unlock(key); end

        # sord omit - no YARD type given for "key", using untyped
        # sord omit - no YARD return type given, using untyped
        sig { params(key: T.untyped).returns(T.untyped) }
        def with(key); end
      end
    end

    class SqliteAdapter
      # sord omit - no YARD type given for "model_class", using untyped
      sig { params(model_class: T.untyped).void }
      def initialize(model_class); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "capacity:", using untyped
      # sord omit - no YARD type given for "leak_rate:", using untyped
      # sord omit - no YARD return type given, using untyped
      sig { params(key: T.untyped, capacity: T.untyped, leak_rate: T.untyped).returns(T.untyped) }
      def state(key:, capacity:, leak_rate:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "capacity:", using untyped
      # sord omit - no YARD type given for "leak_rate:", using untyped
      # sord omit - no YARD type given for "n_tokens:", using untyped
      # sord omit - no YARD return type given, using untyped
      sig do
        params(
          key: T.untyped,
          capacity: T.untyped,
          leak_rate: T.untyped,
          n_tokens: T.untyped
        ).returns(T.untyped)
      end
      def add_tokens(key:, capacity:, leak_rate:, n_tokens:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "capacity:", using untyped
      # sord omit - no YARD type given for "leak_rate:", using untyped
      # sord omit - no YARD type given for "n_tokens:", using untyped
      # sord omit - no YARD return type given, using untyped
      sig do
        params(
          key: T.untyped,
          capacity: T.untyped,
          leak_rate: T.untyped,
          n_tokens: T.untyped
        ).returns(T.untyped)
      end
      def add_tokens_conditionally(key:, capacity:, leak_rate:, n_tokens:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "block_for:", using untyped
      # sord omit - no YARD return type given, using untyped
      sig { params(key: T.untyped, block_for: T.untyped).returns(T.untyped) }
      def set_block(key:, block_for:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD return type given, using untyped
      sig { params(key: T.untyped).returns(T.untyped) }
      def blocked_until(key:); end

      # sord omit - no YARD return type given, using untyped
      sig { returns(T.untyped) }
      def prune; end

      # sord omit - no YARD type given for "active_record_schema", using untyped
      # sord omit - no YARD return type given, using untyped
      sig { params(active_record_schema: T.untyped).returns(T.untyped) }
      def create_tables(active_record_schema); end
    end

    class PostgresAdapter
      # sord omit - no YARD type given for "model_class", using untyped
      sig { params(model_class: T.untyped).void }
      def initialize(model_class); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "capacity:", using untyped
      # sord omit - no YARD type given for "leak_rate:", using untyped
      # sord omit - no YARD return type given, using untyped
      sig { params(key: T.untyped, capacity: T.untyped, leak_rate: T.untyped).returns(T.untyped) }
      def state(key:, capacity:, leak_rate:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "capacity:", using untyped
      # sord omit - no YARD type given for "leak_rate:", using untyped
      # sord omit - no YARD type given for "n_tokens:", using untyped
      # sord omit - no YARD return type given, using untyped
      sig do
        params(
          key: T.untyped,
          capacity: T.untyped,
          leak_rate: T.untyped,
          n_tokens: T.untyped
        ).returns(T.untyped)
      end
      def add_tokens(key:, capacity:, leak_rate:, n_tokens:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "capacity:", using untyped
      # sord omit - no YARD type given for "leak_rate:", using untyped
      # sord omit - no YARD type given for "n_tokens:", using untyped
      # sord omit - no YARD return type given, using untyped
      sig do
        params(
          key: T.untyped,
          capacity: T.untyped,
          leak_rate: T.untyped,
          n_tokens: T.untyped
        ).returns(T.untyped)
      end
      def add_tokens_conditionally(key:, capacity:, leak_rate:, n_tokens:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD type given for "block_for:", using untyped
      # sord omit - no YARD return type given, using untyped
      sig { params(key: T.untyped, block_for: T.untyped).returns(T.untyped) }
      def set_block(key:, block_for:); end

      # sord omit - no YARD type given for "key:", using untyped
      # sord omit - no YARD return type given, using untyped
      sig { params(key: T.untyped).returns(T.untyped) }
      def blocked_until(key:); end

      # sord omit - no YARD return type given, using untyped
      sig { returns(T.untyped) }
      def prune; end

      # sord omit - no YARD type given for "active_record_schema", using untyped
      # sord omit - no YARD return type given, using untyped
      sig { params(active_record_schema: T.untyped).returns(T.untyped) }
      def create_tables(active_record_schema); end
    end
  end

  # Provides access to Pecorino blocks - same blocks which get set when a throttle triggers. The blocks
  # are just keys in the data store which have an expiry value. This can be useful if you want to restrict
  # access to a resource for an arbitrary timespan.
  class Block
    # Sets a block for the given key. The block will also be seen by the Pecorino::Throttle with the same key
    # 
    # _@param_ `key` — the key to set the block for
    # 
    # _@param_ `block_for` — the number of seconds or a time interval to block for
    # 
    # _@param_ `adapter` — the adapter to set the value in.
    # 
    # _@return_ — the time when the block will be released
    sig { params(key: String, block_for: Float, adapter: Pecorino::Adapters::BaseAdapter).returns(Time) }
    def self.set!(key:, block_for:, adapter: Pecorino.adapter); end

    # Returns the time until a certain block is in effect
    # 
    # _@param_ `key` — the key to get the expiry time for
    # 
    # _@param_ `adapter` — the adapter to get the value from
    # 
    # _@return_ — the time when the block will be released
    sig { params(key: String, adapter: Pecorino::Adapters::BaseAdapter).returns(T.nilable(Time)) }
    def self.blocked_until(key:, adapter: Pecorino.adapter); end
  end

  class Railtie < Rails::Railtie
  end

  # Provides a throttle with a block based on the `LeakyBucket`. Once a bucket fills up,
  # a block will be installed and an exception will be raised. Once a block is set, no
  # checks will be done on the leaky bucket - any further requests will be refused until
  # the block is lifted. The block time can be arbitrarily higher or lower than the amount
  # of time it takes for the leaky bucket to leak out
  class Throttle
    # _@param_ `key` — the key for both the block record and the leaky bucket
    # 
    # _@param_ `block_for` — the number of seconds to block any further requests for. Defaults to time it takes the bucket to leak out to the level of 0
    # 
    # _@param_ `adapter` — a compatible adapter
    # 
    # _@param_ `leaky_bucket_options` — Options for `Pecorino::LeakyBucket.new`
    # 
    # _@see_ `PecorinoLeakyBucket.new`
    sig do
      params(
        key: String,
        block_for: T.nilable(Numeric),
        adapter: Pecorino::Adapters::BaseAdapter,
        leaky_bucket_options: T.untyped
      ).void
    end
    def initialize(key:, block_for: nil, adapter: Pecorino.adapter, **leaky_bucket_options); end

    # Tells whether the throttle will let this number of requests pass without raising
    # a Throttled. Note that this is not race-safe. Another request could overflow the bucket
    # after you call `able_to_accept?` but before you call `throttle!`. So before performing
    # the action you still need to call `throttle!`. You may still use `able_to_accept?` to
    # provide better UX to your users before they cause an action that would otherwise throttle.
    # 
    # _@param_ `n_tokens`
    sig { params(n_tokens: Float).returns(T::Boolean) }
    def able_to_accept?(n_tokens = 1); end

    # sord omit - no YARD type given for "n", using untyped
    # Register that a request is being performed. Will raise Throttled
    # if there is a block in place for that throttle, or if the bucket cannot accept
    # this fillup and the block has just been installed as a result of this particular request.
    # 
    # The exception can be rescued later to provide a 429 response. This method is better
    # to use before performing the unit of work that the throttle is guarding:
    # 
    # If the method call succeeds it means that the request is not getting throttled.
    # 
    # _@return_ — the state of the throttle after filling up the leaky bucket / trying to pass the block
    # 
    # ```ruby
    # begin
    #    t.request!
    #    Note.create!(note_params)
    # rescue Pecorino::Throttle::Throttled => e
    #    [429, {"Retry-After" => e.retry_after.to_s}, []]
    # end
    # ```
    sig { params(n: T.untyped).returns(State) }
    def request!(n = 1); end

    # sord omit - no YARD type given for "n", using untyped
    # Register that a request is being performed. Will not raise any exceptions but return
    # the time at which the block will be lifted if a block resulted from this request or
    # was already in effect. Can be used for registering actions which already took place,
    # but should result in subsequent actions being blocked.
    # 
    # _@return_ — the state of the throttle after filling up the leaky bucket / trying to pass the block
    # 
    # ```ruby
    # if t.able_to_accept?
    #   Entry.create!(entry_params)
    #   t.request
    # end
    # ```
    sig { params(n: T.untyped).returns(State) }
    def request(n = 1); end

    # Fillup the throttle with 1 request and then perform the passed block. This is useful to perform actions which should
    # be rate-limited - alerts, calls to external services and the like. If the call is allowed to proceed,
    # the passed block will be executed. If the throttle is in the blocked state or if the call puts the throttle in
    # the blocked state the block will not be executed
    # 
    # _@return_ — the return value of the block if the block gets executed, or `nil` if the call got throttled
    # 
    # ```ruby
    # t.throttled { Slack.alert("Things are going wrong") }
    # ```
    sig { params(blk: T.untyped).returns(Object) }
    def throttled(&blk); end

    # The key for that throttle. Each key defines a unique throttle based on either a given name or
    # discriminators. If there is a component you want to key your throttle by, include it in the
    # `key` keyword argument to the constructor, like `"t-ip-#{request.ip}"`
    sig { returns(String) }
    attr_reader :key

    # The state represents a snapshot of the throttle state in time
    class State
      # sord omit - no YARD type given for "blocked_until", using untyped
      sig { params(blocked_until: T.untyped).void }
      def initialize(blocked_until); end

      # Tells whether this throttle still is in the blocked state.
      # If the `blocked_until` value lies in the past, the method will
      # return `false` - this is done so that the `State` can be cached.
      sig { returns(T::Boolean) }
      def blocked?; end

      sig { returns(Time) }
      attr_reader :blocked_until
    end

    # {Pecorino::Throttle} will raise this exception from `request!`. The exception can be used
    # to do matching, for setting appropriate response headers, and for distinguishing between
    # multiple different throttles.
    class Throttled < StandardError
      # sord omit - no YARD type given for "from_throttle", using untyped
      # sord omit - no YARD type given for "state", using untyped
      sig { params(from_throttle: T.untyped, state: T.untyped).void }
      def initialize(from_throttle, state); end

      # Returns the `retry_after` value in seconds, suitable for use in an HTTP header
      sig { returns(Integer) }
      def retry_after; end

      # Returns the throttle which raised the exception. Can be used to disambiguiate between
      # multiple Throttled exceptions when multiple throttles are applied in a layered fashion:
      # 
      # ```ruby
      # begin
      #   ip_addr_throttle.request!
      #   user_email_throttle.request!
      #   db_insert_throttle.request!(n_items_to_insert)
      # rescue Pecorino::Throttled => e
      #   deliver_notification(user) if e.throttle == user_email_throttle
      #   firewall.ban_ip(ip) if e.throttle == ip_addr_throttle
      # end
      # ```
      sig { returns(Throttle) }
      attr_reader :throttle

      # Returns the throttle state based on which the exception is getting raised. This can
      # be used for caching the exception, because the state can tell when the block will be
      # lifted. This can be used to shift the throttle verification into a faster layer of the
      # system (like a blocklist in a firewall) or caching the state in an upstream cache. A block
      # in Pecorino is set once and is active until expiry. If your service is under an attack
      # and you know that the call is blocked until a certain future time, the block can be
      # lifted up into a faster/cheaper storage destination, like Rails cache:
      # 
      # ```ruby
      # begin
      #   ip_addr_throttle.request!
      # rescue Pecorino::Throttled => e
      #   firewall.ban_ip(request.ip, ttl_seconds: e.state.retry_after)
      #   render :rate_limit_exceeded
      # end
      # ```
      # 
      # ```ruby
      # state = Rails.cache.read(ip_addr_throttle.key)
      # return render :rate_limit_exceeded if state && state.blocked? # No need to call Pecorino for this
      # 
      # begin
      #   ip_addr_throttle.request!
      # rescue Pecorino::Throttled => e
      #   Rails.cache.write(ip_addr_throttle.key, e.state, expires_in: (e.state.blocked_until - Time.now))
      #   render :rate_limit_exceeded
      # end
      # ```
      sig { returns(Throttle::State) }
      attr_reader :state
    end
  end

  # This offers just the leaky bucket implementation with fill control, but without the timed lock.
  # It does not raise any exceptions, it just tracks the state of a leaky bucket in the database.
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
  class LeakyBucket
    # sord duck - #to_f looks like a duck type, replacing with untyped
    # Creates a new LeakyBucket. The object controls 1 row in the database is
    # specific to the bucket key.
    # 
    # _@param_ `key` — the key for the bucket. The key also gets used to derive locking keys, so that operations on a particular bucket are always serialized.
    # 
    # _@param_ `leak_rate` — the leak rate of the bucket, in tokens per second. Either `leak_rate` or `over_time` can be used, but not both.
    # 
    # _@param_ `over_time` — over how many seconds the bucket will leak out to 0 tokens. The value is assumed to be the number of seconds - or a duration which returns the number of seconds from `to_f`. Either `leak_rate` or `over_time` can be used, but not both.
    # 
    # _@param_ `capacity` — how many tokens is the bucket capped at. Filling up the bucket using `fillup()` will add to that number, but the bucket contents will then be capped at this value. So with bucket_capacity set to 12 and a `fillup(14)` the bucket will reach the level of 12, and will then immediately start leaking again.
    # 
    # _@param_ `adapter` — a compatible adapter
    sig do
      params(
        key: String,
        capacity: Numeric,
        adapter: Pecorino::Adapters::BaseAdapter,
        leak_rate: T.nilable(Float),
        over_time: T.untyped
      ).void
    end
    def initialize(key:, capacity:, adapter: Pecorino.adapter, leak_rate: nil, over_time: nil); end

    # Places `n` tokens in the bucket. If the bucket has less capacity than `n` tokens, the bucket will be filled to capacity.
    # If the bucket has less capacity than `n` tokens, it will be filled to capacity. If the bucket is already full
    # when the fillup is requested, the bucket stays at capacity.
    # 
    # Once tokens are placed, the bucket is set to expire within 2 times the time it would take it to leak to 0,
    # regardless of how many tokens get put in - since the amount of tokens put in the bucket will always be capped
    # to the `capacity:` value you pass to the constructor.
    # 
    # _@param_ `n_tokens` — How many tokens to fillup by
    # 
    # _@return_ — the state of the bucket after the operation
    sig { params(n_tokens: Float).returns(State) }
    def fillup(n_tokens); end

    # Places `n` tokens in the bucket. If the bucket has less capacity than `n` tokens, the fillup will be rejected.
    # This can be used for "exactly once" semantics or just more precise rate limiting. Note that if the bucket has
    # _exactly_ `n` tokens of capacity the fillup will be accepted.
    # 
    # Once tokens are placed, the bucket is set to expire within 2 times the time it would take it to leak to 0,
    # regardless of how many tokens get put in - since the amount of tokens put in the bucket will always be capped
    # to the `capacity:` value you pass to the constructor.
    # 
    # _@param_ `n_tokens` — How many tokens to fillup by
    # 
    # _@return_ — the state of the bucket after the operation and whether the operation succeeded
    # 
    # ```ruby
    # withdrawals = LeakyBuket.new(key: "wallet-#{user.id}", capacity: 200, over_time: 1.day)
    # if withdrawals.fillup_conditionally(amount_to_withdraw).accepted?
    #   user.wallet.withdraw(amount_to_withdraw)
    # else
    #   raise "You need to wait a bit before withdrawing more"
    # end
    # ```
    sig { params(n_tokens: Float).returns(ConditionalFillupResult) }
    def fillup_conditionally(n_tokens); end

    # Returns the current state of the bucket, containing the level and whether the bucket is full.
    # Calling this method will not perform any database writes.
    # 
    # _@return_ — the snapshotted state of the bucket at time of query
    sig { returns(State) }
    def state; end

    # Tells whether the bucket can accept the amount of tokens without overflowing.
    # Calling this method will not perform any database writes. Note that this call is
    # not race-safe - another caller may still overflow the bucket. Before performing
    # your action, you still need to call `fillup()` - but you can preemptively refuse
    # a request if you already know the bucket is full.
    # 
    # _@param_ `n_tokens`
    sig { params(n_tokens: Float).returns(T::Boolean) }
    def able_to_accept?(n_tokens); end

    # sord omit - no YARD type given for :key, using untyped
    # The key (name) of the leaky bucket
    #   @return [String]
    sig { returns(T.untyped) }
    attr_reader :key

    # sord omit - no YARD type given for :leak_rate, using untyped
    # The leak rate (tokens per second) of the bucket
    #   @return [Float]
    sig { returns(T.untyped) }
    attr_reader :leak_rate

    # sord omit - no YARD type given for :capacity, using untyped
    # The capacity of the bucket in tokens
    #   @return [Float]
    sig { returns(T.untyped) }
    attr_reader :capacity

    # Returned from `.state` and `.fillup`
    class State
      # sord omit - no YARD type given for "level", using untyped
      # sord omit - no YARD type given for "is_full", using untyped
      sig { params(level: T.untyped, is_full: T.untyped).void }
      def initialize(level, is_full); end

      # Tells whether the bucket was detected to be full when the operation on
      # the LeakyBucket was performed.
      sig { returns(T::Boolean) }
      def full?; end

      # Returns the level of the bucket
      sig { returns(Float) }
      attr_reader :level
    end

    # Same as `State` but also communicates whether the write has been permitted or not. A conditional fillup
    # may refuse a write if it would make the bucket overflow
    class ConditionalFillupResult < Pecorino::LeakyBucket::State
      # sord omit - no YARD type given for "level", using untyped
      # sord omit - no YARD type given for "is_full", using untyped
      # sord omit - no YARD type given for "accepted", using untyped
      sig { params(level: T.untyped, is_full: T.untyped, accepted: T.untyped).void }
      def initialize(level, is_full, accepted); end

      # Tells whether the bucket did accept the requested fillup
      sig { returns(T::Boolean) }
      def accepted?; end
    end
  end

  # The cached throttles can be used when you want to lift your throttle blocks into
  # a higher-level cache. If you are dealing with clients which are hammering on your
  # throttles a lot, it is useful to have a process-local cache of the timestamp when
  # the blocks that are set are going to expire. If you are running, say, 10 web app
  # containers - and someone is hammering at an endpoint which starts blocking -
  # you don't really need to query your DB for every request. The first request indicated
  # as "blocked" by Pecorino can write a cache entry into a shared in-memory table,
  # and all subsequent calls to the same process can reuse that `blocked_until` value
  # to quickly refuse the request
  class CachedThrottle
    # sord warn - ActiveSupport::Cache::Store wasn't able to be resolved to a constant in this project
    # _@param_ `cache_store` — the store for the cached blocks. We recommend a MemoryStore per-process.
    # 
    # _@param_ `throttle` — the throttle to cache
    sig { params(cache_store: ActiveSupport::Cache::Store, throttle: Pecorino::Throttle).void }
    def initialize(cache_store, throttle); end

    # sord omit - no YARD type given for "n", using untyped
    # sord omit - no YARD return type given, using untyped
    # 
    # _@see_ `Pecorino::Throttle#request!`
    sig { params(n: T.untyped).returns(T.untyped) }
    def request!(n = 1); end

    # sord omit - no YARD type given for "n", using untyped
    # sord omit - no YARD return type given, using untyped
    # Returns cached `state` for the throttle if there is a currently active block for that throttle in the cache. Otherwise forwards to underlying throttle.
    # 
    # _@see_ `Pecorino::Throttle#request`
    sig { params(n: T.untyped).returns(T.untyped) }
    def request(n = 1); end

    # sord omit - no YARD type given for "n", using untyped
    # Returns `false` if there is a currently active block for that throttle in the cache. Otherwise forwards to underlying throttle.
    # 
    # _@see_ `Pecorino::Throttle#able_to_accept?`
    sig { params(n: T.untyped).returns(T::Boolean) }
    def able_to_accept?(n = 1); end

    # sord omit - no YARD return type given, using untyped
    # Does not run the block  if there is a currently active block for that throttle in the cache. Otherwise forwards to underlying throttle.
    # 
    # _@see_ `Pecorino::Throttle#throttled`
    sig { params(blk: T.untyped).returns(T.untyped) }
    def throttled(&blk); end

    # sord omit - no YARD return type given, using untyped
    # Returns the key of the throttle
    # 
    # _@see_ `Pecorino::Throttle#key`
    sig { returns(T.untyped) }
    def key; end

    # sord omit - no YARD return type given, using untyped
    # Returns `false` if there is a currently active block for that throttle in the cache. Otherwise forwards to underlying throttle.
    # 
    # _@see_ `Pecorino::Throttle#able_to_accept?`
    sig { returns(T.untyped) }
    def state; end

    # sord omit - no YARD type given for "state", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(state: T.untyped).returns(T.untyped) }
    def write_cache_blocked_state(state); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def read_cached_blocked_state; end
  end

  # 
  # Rails generator used for setting up Pecorino in a Rails application.
  # Run it with +bin/rails g pecorino:install+ in your console.
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration
    TEMPLATES = T.let(File.join(File.dirname(__FILE__)), T.untyped)

    # sord omit - no YARD return type given, using untyped
    # Generates monolithic migration file that contains all database changes.
    sig { returns(T.untyped) }
    def create_migration_file; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def migration_version; end
  end
end
