# frozen_string_literal: true

# Provides a throttle with a block based on the `LeakyBucket`. Once a bucket fills up,
# a block will be installed and an exception will be raised. Once a block is set, no
# checks will be done on the leaky bucket - any further requests will be refused until
# the block is lifted. The block time can be arbitrarily higher or lower than the amount
# of time it takes for the leaky bucket to leak out
class Pecorino::Throttle
  State = Struct.new(:blocked_until) do
    # Tells whether this throttle is blocked, either due to the leaky bucket having filled up
    # or due to there being a timed block set because of an earlier event of the bucket having
    # filled up
    def blocked?
      blocked_until ? true : false
    end

    # Returns the number of seconds until the block will be lifted, rouded up to the closest
    # whole second. This value can be used in a "Retry-After" HTTP response header.
    #
    # @return [Integer]
    def retry_after
      (blocked_until - Time.now.utc).ceil
    end
  end

  class Throttled < StandardError
    # Returns the throttle which raised the exception. Can be used to disambiguiate between
    # multiple Throttled exceptions when multiple throttles are applied in a layered fashion:
    #
    # @example
    #    begin
    #      ip_addr_throttle.request!
    #      user_email_throttle.request!
    #      db_insert_throttle.request!(n_items_to_insert)
    #    rescue Pecorino::Throttled => e
    #      deliver_notification(user) if e.throttle == user_email_throttle
    #    end
    #
    # @return [Throttle]
    attr_reader :throttle

    # Returns the `retry_after` value in seconds, suitable for use in an HTTP header
    attr_reader :retry_after

    def initialize(from_throttle, state)
      @throttle = from_throttle
      @retry_after = state.retry_after
      super("Block in effect until #{state.blocked_until.iso8601}")
    end
  end

  # @param key[String] the key for both the block record and the leaky bucket
  # @param block_for[Numeric] the number of seconds to block any further requests for. Defaults to time it takes
  #   the bucket to leak out to the level of 0
  # @param leaky_bucket_options Options for `Pecorino::LeakyBucket.new`
  # @see PecorinoLeakyBucket.new
  def initialize(key:, block_for: nil, **leaky_bucket_options)
    @bucket = Pecorino::LeakyBucket.new(key: key, **leaky_bucket_options)
    @key = key.to_s
    @block_for = block_for ? block_for.to_f : (@bucket.capacity / @bucket.leak_rate)
  end

  # Tells whether the throttle will let this number of requests pass without raising
  # a Throttled. Note that this is not race-safe. Another request could overflow the bucket
  # after you call `able_to_accept?` but before you call `throttle!`. So before performing
  # the action you still need to call `throttle!`. You may still use `able_to_accept?` to
  # provide better UX to your users before they cause an action that would otherwise throttle.
  #
  # @param n_tokens[Float]
  # @return [boolean]
  def able_to_accept?(n_tokens = 1)
    Pecorino.adapter.blocked_until(key: @key).nil? && @bucket.able_to_accept?(n_tokens)
  end

  # Register that a request is being performed. Will raise Throttled
  # if there is a block in place on that key, or if the bucket has been filled up
  # and a block has been put in place as a result of this particular request.
  #
  # The exception can be rescued later to provide a 429 response. This method is better
  # to use before performing the unit of work that the throttle is guarding:
  #
  # @example
  #   begin
  #      t.request!
  #      Note.create!(note_params)
  #   rescue Pecorino::Throttle::Throttled => e
  #      [429, {"Retry-After" => e.retry_after.to_s}, []]
  #   end
  #
  # If the method call succeeds it means that the request is not getting throttled.
  #
  # @return void
  def request!(n = 1)
    state = request(n)
    raise Throttled.new(self, state) if state.blocked?
    nil
  end

  # Register that a request is being performed. Will not raise any exceptions but return
  # the time at which the block will be lifted if a block resulted from this request or
  # was already in effect. Can be used for registering actions which already took place,
  # but should result in subsequent actions being blocked.
  #
  # @example
  #   if t.able_to_accept?
  #     Entry.create!(entry_params)
  #     t.request
  #   end
  #
  # @return [State] the state of the throttle after filling up the leaky bucket / trying to pass the block
  def request(n = 1)
    existing_blocked_until = Pecorino.adapter.blocked_until(key: @key)
    return State.new(existing_blocked_until.utc) if existing_blocked_until

    # Topup the leaky bucket, and if the topup gets rejected - block the caller
    fillup = @bucket.fillup_conditionally(n)
    if fillup.accepted?
      State.new(nil)
    else
      # and set the block if the fillup was rejected
      fresh_blocked_until = Pecorino.adapter.set_block(key: @key, block_for: @block_for)
      State.new(fresh_blocked_until.utc)
    end
  end
end
