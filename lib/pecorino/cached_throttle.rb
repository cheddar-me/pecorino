# The cached throttles can be used when you want to lift your throttle blocks into
# a higher-level cache. If you are dealing with clients which are hammering on your
# throttles a lot, it is useful to have a process-local cache of the timestamp when
# the blocks that are set are going to expire. If you are running, say, 10 web app
# containers - and someone is hammering at an endpoint which starts blocking -
# you don't really need to query your DB for every request. The first request indicated
# as "blocked" by Pecorino can write a cache entry into a shared in-memory table,
# and all subsequent calls to the same process can reuse that `blocked_until` value
# to quickly refuse the request
class Pecorino::CachedThrottle
  # @param cache_store[ActiveSupport::Cache::Store] the store for the cached blocks. We recommend a MemoryStore per-process.
  # @param throttle[Pecorino::Throttle] the throttle to cache
  def initialize(cache_store, throttle)
    @cache_store = cache_store
    @throttle = throttle
  end

  # @see Pecorino::Throttle#request!
  def request!(n = 1)
    blocked_state = cached_blocked_state
    if blocked_state&.blocked?
      raise Pecorino::Throttle::Throttled.new(@throttle, blocked_state)
    else
      begin
        @throttle.request!(n)
      rescue Pecorino::Throttle::Throttled => throttled_ex
        cache_blocked_state(throttled_ex.state) if throttled_ex.throttle == @throttle
        raise
      end
    end
  end

  # Returns cached `state` for the throttle if there is a currently active block for that throttle in the cache. Otherwise forwards to underlying throttle.
  #
  # @see Pecorino::Throttle#request
  def request(n = 1)
    blocked_state = cached_blocked_state
    return blocked_state if blocked_state&.blocked?

    @throttle.request(n).tap do |state|
      cache_blocked_state(state) if state.blocked_until
    end
  end

  # Returns `false` if there is a currently active block for that throttle in the cache. Otherwise forwards to underlying throttle.
  #
  # @see Pecorino::Throttle#able_to_accept?
  def able_to_accept?(n = 1)
    blocked_state = cached_blocked_state
    return false if blocked_state&.blocked?
    @throttle.able_to_accept?(n)
  end

  # Does not run the block  if there is a currently active block for that throttle in the cache. Otherwise forwards to underlying throttle.
  #
  # @see Pecorino::Throttle#throttled
  def throttled(&blk)
    # We can't wrap the implementation of "throttled". Or - we can, but it will be obtuse.
    return if request(1).blocked?
    yield
  end

  private

  def cache_blocked_state(state)
    @cache_store.write("pcrn-cached-throttle-#{@throttle.key}", state, expires_after: state.blocked_until)
  end

  def cached_blocked_state
    @cache_store.read("pcrn-cached-throttle-#{@throttle.key}")
  end
end
