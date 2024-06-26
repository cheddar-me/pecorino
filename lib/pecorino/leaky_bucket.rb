# frozen_string_literal: true

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
class Pecorino::LeakyBucket
  # Returned from `.state` and `.fillup`
  class State
    def initialize(level, is_full)
      @level = level.to_f
      @full = !!is_full
    end

    # Returns the level of the bucket
    # @return [Float]
    attr_reader :level

    # Tells whether the bucket was detected to be full when the operation on
    # the LeakyBucket was performed.
    # @return [Boolean]
    def full?
      @full
    end

    alias_method :full, :full?
  end

  # Same as `State` but also communicates whether the write has been permitted or not. A conditional fillup
  # may refuse a write if it would make the bucket overflow
  class ConditionalFillupResult < State
    def initialize(level, is_full, accepted)
      super(level, is_full)
      @accepted = !!accepted
    end

    # Tells whether the bucket did accept the requested fillup
    # @return [Boolean]
    def accepted?
      @accepted
    end
  end

  # The key (name) of the leaky bucket
  #   @return [String]
  attr_reader :key

  # The leak rate (tokens per second) of the bucket
  #   @return [Float]
  attr_reader :leak_rate

  # The capacity of the bucket in tokens
  #   @return [Float]
  attr_reader :capacity

  # Creates a new LeakyBucket. The object controls 1 row in the database is
  # specific to the bucket key.
  #
  # @param key[String] the key for the bucket. The key also gets used
  #   to derive locking keys, so that operations on a particular bucket
  #   are always serialized.
  # @param leak_rate[Float] the leak rate of the bucket, in tokens per second.
  #   Either `leak_rate` or `over_time` can be used, but not both.
  # @param over_time[#to_f] over how many seconds the bucket will leak out to 0 tokens.
  #   The value is assumed to be the number of seconds
  #   - or a duration which returns the number of seconds from `to_f`.
  #   Either `leak_rate` or `over_time` can be used, but not both.
  # @param capacity[Numeric] how many tokens is the bucket capped at.
  #   Filling up the bucket using `fillup()` will add to that number, but
  #   the bucket contents will then be capped at this value. So with
  #   bucket_capacity set to 12 and a `fillup(14)` the bucket will reach the level
  #   of 12, and will then immediately start leaking again.
  # @param adapter[Pecorino::Adapters::BaseAdapter] a compatible adapter
  def initialize(key:, capacity:, adapter: Pecorino.adapter, leak_rate: nil, over_time: nil)
    raise ArgumentError, "Either leak_rate: or over_time: must be specified" if leak_rate.nil? && over_time.nil?
    raise ArgumentError, "Either leak_rate: or over_time: may be specified, but not both" if leak_rate && over_time
    @leak_rate = leak_rate || (capacity / over_time.to_f)
    @key = key
    @capacity = capacity.to_f
    @adapter = adapter
  end

  # Places `n` tokens in the bucket. If the bucket has less capacity than `n` tokens, the bucket will be filled to capacity.
  # If the bucket has less capacity than `n` tokens, it will be filled to capacity. If the bucket is already full
  # when the fillup is requested, the bucket stays at capacity.
  #
  # Once tokens are placed, the bucket is set to expire within 2 times the time it would take it to leak to 0,
  # regardless of how many tokens get put in - since the amount of tokens put in the bucket will always be capped
  # to the `capacity:` value you pass to the constructor.
  #
  # @param n_tokens[Float] How many tokens to fillup by
  # @return [State] the state of the bucket after the operation
  def fillup(n_tokens)
    capped_level_after_fillup, is_full = @adapter.add_tokens(capacity: @capacity, key: @key, leak_rate: @leak_rate, n_tokens: n_tokens)
    State.new(capped_level_after_fillup, is_full)
  end

  # Places `n` tokens in the bucket. If the bucket has less capacity than `n` tokens, the fillup will be rejected.
  # This can be used for "exactly once" semantics or just more precise rate limiting. Note that if the bucket has
  # _exactly_ `n` tokens of capacity the fillup will be accepted.
  #
  # Once tokens are placed, the bucket is set to expire within 2 times the time it would take it to leak to 0,
  # regardless of how many tokens get put in - since the amount of tokens put in the bucket will always be capped
  # to the `capacity:` value you pass to the constructor.
  #
  # @example
  #    withdrawals = LeakyBuket.new(key: "wallet-#{user.id}", capacity: 200, over_time: 1.day)
  #    if withdrawals.fillup_conditionally(amount_to_withdraw).accepted?
  #      user.wallet.withdraw(amount_to_withdraw)
  #    else
  #      raise "You need to wait a bit before withdrawing more"
  #    end
  # @param n_tokens[Float] How many tokens to fillup by
  # @return [ConditionalFillupResult] the state of the bucket after the operation and whether the operation succeeded
  def fillup_conditionally(n_tokens)
    capped_level_after_fillup, is_full, did_accept = @adapter.add_tokens_conditionally(capacity: @capacity, key: @key, leak_rate: @leak_rate, n_tokens: n_tokens)
    ConditionalFillupResult.new(capped_level_after_fillup, is_full, did_accept)
  end

  # Returns the current state of the bucket, containing the level and whether the bucket is full.
  # Calling this method will not perform any database writes.
  #
  # @return [State] the snapshotted state of the bucket at time of query
  def state
    current_level, is_full = @adapter.state(key: @key, capacity: @capacity, leak_rate: @leak_rate)
    State.new(current_level, is_full)
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
    (state.level + n_tokens) <= @capacity
  end
end
