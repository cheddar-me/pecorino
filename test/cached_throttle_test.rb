# frozen_string_literal: true

require "test_helper"

class CachedThrottleTest < ActiveSupport::TestCase
  def setup
    create_postgres_database
  end

  def teardown
    drop_postgres_database
  end

  test "caches results of request! and correctly raises Throttled until the block is lifted" do
    store = ActiveSupport::Cache::MemoryStore.new
    throttle = Pecorino::Throttle.new(key: Random.uuid, capacity: 2, over_time: 1.second, block_for: 10.seconds)
    cached_throttle = Pecorino::CachedThrottle.new(store, throttle)

    state1 = cached_throttle.request!
    state2 = cached_throttle.request!
    ex = assert_raises(Pecorino::Throttle::Throttled) do
      cached_throttle.request!
    end

    assert_kind_of Pecorino::Throttle::State, state1
    assert_kind_of Pecorino::Throttle::State, state2

    assert_equal throttle, ex.throttle

    # Delete the method on the actual throttle as it should not be called anymore until the block is lifted
    class << throttle
      undef :request!
    end
    assert_raises(Pecorino::Throttle::Throttled) do
      cached_throttle.request!
    end
  end

  test "caches results of able_to_accept? until the block is lifted" do
    store = ActiveSupport::Cache::MemoryStore.new
    throttle = Pecorino::Throttle.new(key: Random.uuid, capacity: 2, over_time: 1.second, block_for: 10.seconds)
    cached_throttle = Pecorino::CachedThrottle.new(store, throttle)

    cached_throttle.request(1)
    cached_throttle.request(1)
    cached_throttle.request(1)

    refute cached_throttle.able_to_accept?(1)

    # Delete the method on the actual throttle as it should not be called anymore until the block is lifted
    class << throttle
      undef :able_to_accept?
    end

    refute cached_throttle.able_to_accept?(1)
  end

  test "caches results of request() and correctly returns cached state until the block is lifted" do
    store = ActiveSupport::Cache::MemoryStore.new
    throttle = Pecorino::Throttle.new(key: Random.uuid, capacity: 2, over_time: 1.second, block_for: 10.seconds)
    cached_throttle = Pecorino::CachedThrottle.new(store, throttle)

    state1 = cached_throttle.request(1)
    state2 = cached_throttle.request(1)
    state3 = cached_throttle.request(3)

    assert_kind_of Pecorino::Throttle::State, state1
    assert_kind_of Pecorino::Throttle::State, state2
    assert_kind_of Pecorino::Throttle::State, state3
    assert_predicate state3, :blocked?

    # Delete the method on the actual throttle as it should not be called anymore until the block is lifted
    class << throttle
      undef :request
    end
    state_from_cache = cached_throttle.request(1)
    assert_kind_of Pecorino::Throttle::State, state_from_cache
    assert_predicate state_from_cache, :blocked?
  end

  test "returns the key of the contained throttle" do
    store = ActiveSupport::Cache::MemoryStore.new
    throttle = Pecorino::Throttle.new(key: Random.uuid, capacity: 2, over_time: 1.second, block_for: 10.seconds)
    cached_throttle = Pecorino::CachedThrottle.new(store, throttle)
    assert_equal cached_throttle.key, throttle.key
  end

  test "does not run block in throttled() until the block is lifted" do
    store = ActiveSupport::Cache::MemoryStore.new
    throttle = Pecorino::Throttle.new(key: Random.uuid, capacity: 2, over_time: 1.second, block_for: 10.seconds)
    cached_throttle = Pecorino::CachedThrottle.new(store, throttle)

    assert_equal 123, cached_throttle.throttled { 123 }
    assert_equal 234, cached_throttle.throttled { 234 }
    assert_nil cached_throttle.throttled { 345 }

    # Delete the method on the actual throttle as it should not be called anymore until the block is lifted
    class << throttle
      undef :throttled
    end

    assert_nil cached_throttle.throttled { 345 }
  end
end
