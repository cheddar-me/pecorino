# frozen_string_literal: true

# A memory store for leaky buckets and blocks
class Pecorino::Adapters::MemoryAdapter
  class KeyedLock
    def initialize
      @locked_keys = Set.new
      @lock_mutex = Mutex.new
    end

    def lock(key)
      loop do
        @lock_mutex.synchronize do
          next if @locked_keys.include?(key)
          @locked_keys << key
          return
        end
      end
    end

    def unlock(key)
      @lock_mutex.synchronize do
        @locked_keys.delete(key)
      end
    end

    def with(key)
      lock(key)
      yield
    ensure
      unlock(key)
    end
  end

  def initialize
    @buckets = {}
    @blocks = {}
    @lock = KeyedLock.new
  end

  # Returns the state of a leaky bucket. The state should be a tuple of two
  # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
  def state(key:, capacity:, leak_rate:)
    @lock.lock(key)
    level, ts = @buckets[key]
    @lock.unlock(key)

    return [0, false] unless level

    dt = get_mono_time - ts
    level_after_leak = [0, level - (leak_rate * dt)].max
    [level_after_leak.to_f, (level_after_leak - capacity) >= 0]
  end

  # Adds tokens to the leaky bucket. The return value is a tuple of two
  # values: the current level (Float) and whether the bucket is now at capacity (Boolean)
  def add_tokens(key:, capacity:, leak_rate:, n_tokens:)
    add_tokens_with_lock(key, capacity, leak_rate, n_tokens, _conditionally  = false)
  end

  # Adds tokens to the leaky bucket conditionally. If there is capacity, the tokens will
  # be added. If there isn't - the fillup will be rejected. The return value is a triplet of
  # the current level (Float), whether the bucket is now at capacity (Boolean)
  # and whether the fillup was accepted (Boolean)
  def add_tokens_conditionally(key:, capacity:, leak_rate:, n_tokens:)
    add_tokens_with_lock(key, capacity, leak_rate, n_tokens, _conditionally  = true)
  end

  # Sets a timed block for the given key - this is used when a throttle fires. The return value
  # is not defined - the call should always succeed.
  def set_block(key:, block_for:)
    raise ArgumentError, "block_for must be positive" unless block_for > 0
    @lock.lock(key)
    @blocks[key] = get_mono_time + block_for.to_f
    Time.now + block_for.to_f
  ensure
    @lock.unlock(key)
  end

  # Returns the time until which a block for a given key is in effect. If there is no block in
  # effect, the method should return `nil`. The return value is either a `Time` or `nil`
  def blocked_until(key:)
    blocked_until_monotonic = @blocks[key]
    return unless blocked_until_monotonic

    now_monotonic = get_mono_time
    return unless blocked_until_monotonic > now_monotonic

    Time.now + (blocked_until_monotonic - now_monotonic)
  end

  # Deletes leaky buckets which have an expiry value prior to now and throttle blocks which have
  # now lapsed
  def prune
    now_monotonic = get_mono_time

    @blocks.delete_if do |key, blocked_until_monotonic|
      @lock.with(key) do
        blocked_until_monotonic < now_monotonic
      end
    end

    @buckets.delete_if do |key, (_level, expire_at_monotonic)|
      @lock.with(key) do
        expire_at_monotonic < now_monotonic
      end
    end
  end

  # No-op
  def create_tables(active_record_schema)
  end

  private

  def add_tokens_with_lock(key, capacity, leak_rate, n_tokens, conditionally)
    @lock.lock(key)
    now = get_mono_time
    level, ts, _ = @buckets[key] || [0.0, now]

    dt = now - ts
    level_after_leak = clamp(0, level - (leak_rate * dt), capacity)
    level_after_fillup = level_after_leak + n_tokens
    if level_after_fillup > capacity && conditionally
      return [level_after_leak, level_after_leak >= capacity, _did_accept = false]
    end

    clamped_level_after_fillup = clamp(0, level_after_fillup, capacity)
    expire_after = now + (level_after_fillup / leak_rate)
    @buckets[key] = [clamped_level_after_fillup, now, expire_after]

    [clamped_level_after_fillup, clamped_level_after_fillup == capacity, _did_accept = true]
  ensure
    @lock.unlock(key)
  end

  def get_mono_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def clamp(min, value, max)
    return min if value < min
    return max if value > max
    value
  end
end
