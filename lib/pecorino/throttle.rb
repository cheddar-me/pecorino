# frozen_string_literal: true

# Provides a throttle with a block based on the `LeakyBucket`. Once a bucket fills up,
# a block will be installed and an exception will be raised. Once a block is set, no
# checks will be done on the leaky bucket - any further requests will be refused until
# the block is lifted. The block time can be arbitrarily higher or lower than the amount
# of time it takes for the leaky bucket to leak out
class Pecorino::Throttle
  # The state represents a snapshot of the throttle state in time
  class State
    # @return [Time]
    attr_reader :blocked_until

    def initialize(blocked_until)
      @blocked_until = blocked_until
    end

    # Tells whether this throttle still is in the blocked state.
    # If the `blocked_until` value lies in the past, the method will
    # return `false` - this is done so that the `State` can be cached.
    #
    # @return [Boolean]
    def blocked?
      !!(@blocked_until && @blocked_until > Time.now)
    end
  end

  # {Pecorino::Throttle} will raise this exception from `request!`. The exception can be used
  # to do matching, for setting appropriate response headers, and for distinguishing between
  # multiple different throttles.
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
    #      firewall.ban_ip(ip) if e.throttle == ip_addr_throttle
    #    end
    #
    # @return [Throttle]
    attr_reader :throttle

    # Returns the throttle state based on which the exception is getting raised. This can
    # be used for caching the exception, because the state can tell when the block will be
    # lifted. This can be used to shift the throttle verification into a faster layer of the
    # system (like a blocklist in a firewall) or caching the state in an upstream cache. A block
    # in Pecorino is set once and is active until expiry. If your service is under an attack
    # and you know that the call is blocked until a certain future time, the block can be
    # lifted up into a faster/cheaper storage destination, like Rails cache:
    #
    # @example
    #    begin
    #      ip_addr_throttle.request!
    #    rescue Pecorino::Throttled => e
    #      firewall.ban_ip(request.ip, ttl_seconds: e.state.retry_after)
    #      render :rate_limit_exceeded
    #    end
    #
    # @example
    #    state = Rails.cache.read(ip_addr_throttle.key)
    #    return render :rate_limit_exceeded if state && state.blocked? # No need to call Pecorino for this
    #
    #    begin
    #      ip_addr_throttle.request!
    #    rescue Pecorino::Throttled => e
    #      Rails.cache.write(ip_addr_throttle.key, e.state, expires_in: (e.state.blocked_until - Time.now))
    #      render :rate_limit_exceeded
    #    end
    #
    # @return [Throttle::State]
    attr_reader :state

    def initialize(from_throttle, state)
      @throttle = from_throttle
      @state = state
      super("Block in effect until #{state.blocked_until.iso8601}")
    end

    # Returns the `retry_after` value in seconds, suitable for use in an HTTP header
    #
    # @return [Integer]
    def retry_after
      (@state.blocked_until - Time.now).ceil
    end
  end

  # The key for that throttle. Each key defines a unique throttle based on either a given name or
  # discriminators. If there is a component you want to key your throttle by, include it in the
  # `key` keyword argument to the constructor, like `"t-ip-#{request.ip}"`
  #
  # @return [String]
  attr_reader :key

  # @param key[String] the key for both the block record and the leaky bucket
  # @param block_for[Numeric] the number of seconds to block any further requests for. Defaults to time it takes
  #   the bucket to leak out to the level of 0
  # @param adapter[Pecorino::Adapters::BaseAdapter] a compatible adapter
  # @param leaky_bucket_options Options for `Pecorino::LeakyBucket.new`
  # @see PecorinoLeakyBucket.new
  def initialize(key:, block_for: nil, adapter: Pecorino.adapter, **leaky_bucket_options)
    @adapter = adapter
    leaky_bucket_options.delete(:adapter)
    @bucket = Pecorino::LeakyBucket.new(key: key, adapter: @adapter, **leaky_bucket_options)
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
    @adapter.blocked_until(key: @key).nil? && @bucket.able_to_accept?(n_tokens)
  end

  # Register that a request is being performed. Will raise Throttled
  # if there is a block in place for that throttle, or if the bucket cannot accept
  # this fillup and the block has just been installed as a result of this particular request.
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
  # @return [State] the state of the throttle after filling up the leaky bucket / trying to pass the block
  def request!(n = 1)
    request(n).tap do |state_after|
      raise Throttled.new(self, state_after) if state_after.blocked?
    end
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
    existing_blocked_until = Pecorino::Block.blocked_until(key: @key, adapter: @adapter)
    return State.new(existing_blocked_until.utc) if existing_blocked_until

    # Topup the leaky bucket, and if the topup gets rejected - block the caller
    fillup = @bucket.fillup_conditionally(n)
    if fillup.accepted?
      State.new(nil)
    else
      # and set the block if the fillup was rejected
      fresh_blocked_until = Pecorino::Block.set!(key: @key, block_for: @block_for, adapter: @adapter)
      State.new(fresh_blocked_until.utc)
    end
  end

  # Fillup the throttle with 1 request and then perform the passed block. This is useful to perform actions which should
  # be rate-limited - alerts, calls to external services and the like. If the call is allowed to proceed,
  # the passed block will be executed. If the throttle is in the blocked state or if the call puts the throttle in
  # the blocked state the block will not be executed
  #
  # @example
  #   t.throttled { Slack.alert("Things are going wrong") }
  #
  # @return [Object] the return value of the block if the block gets executed, or `nil` if the call got throttled
  def throttled(&blk)
    return if request(1).blocked?
    yield
  end
end
