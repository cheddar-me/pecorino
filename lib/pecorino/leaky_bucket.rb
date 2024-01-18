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
  def initialize(key:, capacity:, leak_rate: nil, over_time: nil)
    raise ArgumentError, "Either leak_rate: or over_time: must be specified" if leak_rate.nil? && over_time.nil?
    raise ArgumentError, "Either leak_rate: or over_time: may be specified, but not both" if leak_rate && over_time
    @leak_rate = leak_rate || (over_time.to_f / capacity)
    @key = key
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
    capped_level_after_fillup, did_overflow = Pecorino.adapter.add_tokens(capacity: @capacity, key: @key, leak_rate: @leak_rate, n_tokens: n_tokens)
    State.new(capped_level_after_fillup, did_overflow)
  end

  # Returns the current state of the bucket, containing the level and whether the bucket is full.
  # Calling this method will not perform any database writes.
  #
  # @return [State] the snapshotted state of the bucket at time of query
  def state
    current_level, is_full = Pecorino.adapter.state(key: @key, capacity: @capacity, leak_rate: @leak_rate)
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
    (state.level + n_tokens) < @capacity
  end
end
