# frozen_string_literal: true

require_relative "base_adapter"
require "digest"
require "redis"

# An adapter for storing Pecorino leaky buckets and blocks in Redis. It uses Lua
# to enforce atomicity for leaky bucket operations
class Pecorino::Adapters::RedisAdapter < Pecorino::Adapters::BaseAdapter
  class RedisScript
    def initialize(script_filename)
      @script_body = File.read(File.dirname(__FILE__) + "/redis_adapter/" + script_filename)
      @sha = Digest::SHA1.hexdigest(@script_body)
    end

    def load_and_eval(redis, keys, argv)
      redis.evalsha(@sha, keys: keys, argv: argv)
    rescue Redis::CommandError => e
      if e.message.include? "NOSCRIPT"
        redis.script(:load, @script_body)
        retry
      else
        raise e
      end
    end
  end

  ADD_TOKENS_SCRIPT = RedisScript.new("add_tokens_conditionally.lua")

  def initialize(redis_connection_or_connection_pool, key_prefix: "pecorino")
    @redis_pool = redis_connection_or_connection_pool
    @key_prefix = key_prefix
  end

  # Returns the state of a leaky bucket. The state should be a tuple of two
  # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
  def state(key:, capacity:, leak_rate:)
    add_tokens(key: key, capacity: capacity, leak_rate: leak_rate, n_tokens: 0)
  end

  # Adds tokens to the leaky bucket. The return value is a tuple of two
  # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
  def add_tokens(key:, capacity:, leak_rate:, n_tokens:)
    keys = ["#{@key_prefix}:leaky_bucket:#{key}:level", "#{@key_prefix}:leaky_bucket:#{key}:last_touched"]
    argv = [leak_rate, n_tokens, capacity, _conditional = 0]
    decimal_float_level, at_capacity_int, _ = with_redis do |redis|
      ADD_TOKENS_SCRIPT.load_and_eval(redis, keys, argv)
    end
    [decimal_float_level.to_f, at_capacity_int == 1]
  end

  # Adds tokens to the leaky bucket conditionally. If there is capacity, the tokens will
  # be added. If there isn't - the fillup will be rejected. The return value is a triplet of
  # the current level (Float), whether the bucket is now at capacity (Boolean)
  # and whether the fillup was accepted (Boolean)
  def add_tokens_conditionally(key:, capacity:, leak_rate:, n_tokens:)
    keys = ["#{@key_prefix}:leaky_bucket:#{key}:level", "#{@key_prefix}:leaky_bucket:#{key}:last_touched"]
    argv = [leak_rate, n_tokens, capacity, _conditional = 1]
    decimal_float_level, at_capacity_int, did_accept_int = with_redis do |redis|
      ADD_TOKENS_SCRIPT.load_and_eval(redis, keys, argv)
    end
    [decimal_float_level.to_f, at_capacity_int == 1, did_accept_int == 1]
  end

  # Sets a timed block for the given key - this is used when a throttle fires. The return value
  # is not defined - the call should always succeed.
  def set_block(key:, block_for:)
    raise ArgumentError, "block_for must be positive" unless block_for > 0
    blocked_until = Time.now + block_for
    with_redis do |r|
      r.setex("#{@key_prefix}:leaky_bucket:#{key}:block", block_for.to_f.ceil, blocked_until.to_f)
    end
    blocked_until
  end

  # Returns the time until which a block for a given key is in effect. If there is no block in
  # effect, the method should return `nil`. The return value is either a `Time` or `nil`
  def blocked_until(key:)
    seconds_from_epoch = with_redis do |r|
      r.get("#{@key_prefix}:leaky_bucket:#{key}:block")
    end
    return unless seconds_from_epoch
    Time.at(seconds_from_epoch.to_f).utc
  end

  private

  def with_redis
    if @redis_pool.respond_to?(:with)
      @redis_pool.with {|conn| yield(conn) }
    else
      yield @redis_pool
    end
  end
end
