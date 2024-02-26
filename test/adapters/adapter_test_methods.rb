# The module contains the conformance tests for a storage adapter for Pecorino. A well-behaved adapter
# should pass all of these tests. When creating a new adapter include this module in your test case
# and overload the `create_adapter` method
module AdapterTestMethods
  LEVEL_DELTA = 0.1

  def adapter
    @adapter ||= create_adapter
  end

  def create_adapter
    raise "Adapter test subclass needs to return an adapter implementation from here."
  end

  def random_key
    Random.new(Minitest.seed).hex(4)
  end

  def test_state_returns_zero_for_nonexistent_bucket
    k = random_key
    leak_rate = 2
    capacity = 3

    level, is_full = adapter.state(key: k, capacity: capacity, leak_rate: leak_rate)
    assert_equal 0, level
    assert_equal is_full, false
  end

  def test_bucket_lifecycle_with_unbounded_fillups
    k = random_key
    leak_rate = 2
    capacity = 1

    level, is_full = adapter.add_tokens(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: 0.3)
    assert_in_delta level, 0.3, LEVEL_DELTA
    assert_equal false, is_full

    level, is_full = adapter.add_tokens(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: 0.35)
    assert_in_delta level, 0.65, LEVEL_DELTA
    assert_equal false, is_full

    level, is_full = adapter.add_tokens(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: 0.4)
    assert_in_delta level, 1.0, LEVEL_DELTA
    assert_equal true, is_full

    level, _ = adapter.state(key: k, capacity: capacity, leak_rate: leak_rate)
    assert_in_delta level, 1.0, LEVEL_DELTA

    sleep(0.25)
    level, _ = adapter.state(key: k, capacity: capacity, leak_rate: leak_rate)
    assert_in_delta level, 0.5, LEVEL_DELTA

    sleep(0.25)
    level, _ = adapter.state(key: k, capacity: capacity, leak_rate: leak_rate)
    assert_in_delta level, 0.0, LEVEL_DELTA

    sleep(0.25)
    level, _ = adapter.state(key: k, capacity: capacity, leak_rate: leak_rate)
    assert_in_delta level, 0.0, LEVEL_DELTA
  end

  def test_clamps_fillup_with_negative_value
    k = random_key
    leak_rate = 1.1
    capacity = 15

    level, _, _ = adapter.state(key: k, leak_rate: leak_rate, capacity: capacity)
    assert_in_delta level, 0, 0.0001

    level, _, _ = adapter.add_tokens(key: k, leak_rate: leak_rate, capacity: capacity, n_tokens: -10)
    assert_in_delta level, 0, 0.1
  end

  def test_bucket_lifecycle_with_negative_fillups
    k = random_key
    leak_rate = 2
    capacity = 1

    level, is_full = adapter.add_tokens(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: 1)
    assert_in_delta level, 1.0, LEVEL_DELTA
    assert_equal true, is_full

    level, is_full = adapter.add_tokens(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: -0.35)
    assert_in_delta level, 0.65, LEVEL_DELTA
    assert_equal false, is_full

    level, is_full = adapter.add_tokens(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: -0.4)
    assert_in_delta level, 0.25, LEVEL_DELTA
    assert_equal false, is_full

    level, is_full = adapter.add_tokens(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: -0.4)
    assert_in_delta level, 0.0, LEVEL_DELTA
    assert_equal false, is_full
  end

  def test_bucket_add_tokens_conditionally_accepts_single_fillup_to_capacity
    k = random_key
    leak_rate = 2
    capacity = 1

    level, is_full, did_accept = adapter.add_tokens_conditionally(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: 1)
    assert_in_delta level, 1.0, LEVEL_DELTA
    assert_equal is_full, true
    assert_equal did_accept, true
  end

  def test_bucket_add_tokens_conditionally_accepts_multiple_fillups_to_capacity
    k = random_key
    leak_rate = 2
    capacity = 1

    level, _, did_accept = adapter.add_tokens_conditionally(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: 0.5)
    assert_in_delta level, 0.5, LEVEL_DELTA
    assert_equal did_accept, true

    level, _, did_accept = adapter.add_tokens_conditionally(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: 0.5)
    assert_in_delta level, 1.0, LEVEL_DELTA
    assert_equal did_accept, true
  end

  def test_bucket_lifecycle_rejects_single_fillup_above_capacity
    k = random_key
    leak_rate = 2
    capacity = 1

    level, is_full, did_accept = adapter.add_tokens_conditionally(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: 1.2)
    assert_in_delta level, 0.0, LEVEL_DELTA
    assert_equal is_full, false
    assert_equal did_accept, false
  end

  def test_bucket_lifecycle_rejects_conditional_fillup_that_would_overflow
    k = random_key
    leak_rate = 2
    capacity = 1

    3.times do
      _level, is_full, did_accept = adapter.add_tokens_conditionally(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: 0.3)
      assert_equal is_full, false
      assert_equal did_accept, true
    end

    level, is_full, did_accept = adapter.add_tokens_conditionally(key: k, capacity: capacity, leak_rate: leak_rate, n_tokens: 0.3)
    assert_in_delta level, 0.9, LEVEL_DELTA
    assert_equal is_full, false
    assert_equal did_accept, false
  end

  def test_bucket_lifecycle_handles_conditional_fillup_in_steps
    key = random_key
    leak_rate = 1.0
    capacity = 1.0

    counter = 0
    try_fillup = ->(fillup_by, should_have_reached_level, should_have_accepted) {
      counter += 1
      level, _, did_accept = adapter.add_tokens_conditionally(key: key, capacity: capacity, leak_rate: leak_rate, n_tokens: fillup_by)
      assert_equal did_accept, should_have_accepted, "Update #{counter} did_accept should be #{should_have_accepted}"
      assert_in_delta should_have_reached_level, level, 0.1
    }

    try_fillup.call(1.1, 0.0, false) # Oversized fillup must be refused outright
    try_fillup.call(0.3, 0.3, true)
    try_fillup.call(0.3, 0.6, true)
    try_fillup.call(0.3, 0.9, true)
    try_fillup.call(0.3, 0.9, false) # Would take the bucket to 1.2, so must be rejected

    sleep(0.2) # Leak out 0.2 tokens

    try_fillup.call(0.3, 1.0, true)
    try_fillup.call(-2, 0.0, true) # A negative fillup is permitted since it will never take the bucket above capacity
    try_fillup.call(1.0, 1.0, true) # Filling up in one step should be permitted
  end

  def test_bucket_lifecycle_allows_conditional_fillup_after_leaking_out
    key = random_key
    capacity = 30
    leak_rate = capacity / 0.5

    _, _, did_accept = adapter.add_tokens_conditionally(key: key, capacity: capacity, leak_rate: leak_rate, n_tokens: 29.6)
    assert did_accept

    _, _, did_accept = adapter.add_tokens_conditionally(key: key, capacity: capacity, leak_rate: leak_rate, n_tokens: 1)
    refute did_accept

    sleep 0.6 # Spend enough time to allow the bucket to leak out completely
    _, _, did_accept = adapter.add_tokens_conditionally(key: key, capacity: capacity, leak_rate: leak_rate, n_tokens: 1)
    assert did_accept, "Once the bucket has leaked out to 0 the fillup should be accepted again"
  end

  def test_set_block_sets_a_block
    key = random_key
    now = Time.now.utc
    block_duration_s = 2.2

    assert_nil adapter.blocked_until(key: key)

    set_block_result = adapter.set_block(key: key, block_for: block_duration_s)
    assert_kind_of Time, set_block_result
    assert_in_delta now + block_duration_s, set_block_result, 0.1

    blocked_until = adapter.blocked_until(key: key)
    assert_in_delta blocked_until, set_block_result, 0.1
  end

  def test_set_block_does_not_set_block_in_the_past
    key = random_key
    assert_nil adapter.blocked_until(key: key)
    assert_raise(ArgumentError) {  adapter.set_block(key: key, block_for: -20) }
    assert_nil adapter.blocked_until(key: key)
  end

  def test_set_block_does_not_set_block_which_would_expire_immediately
    key = random_key
    assert_nil adapter.blocked_until(key: key)
    assert_raise(ArgumentError) {  adapter.set_block(key: key, block_for: 0) }
    assert_nil adapter.blocked_until(key: key)
  end

  def test_prune
    key = random_key
    capacity = 30
    leak_rate = capacity / 0.5

    adapter.add_tokens_conditionally(key: key, capacity: capacity, leak_rate: leak_rate, n_tokens: 29.6)
    adapter.set_block(key: key, block_for: 0.5)

    sleep 0.65

    # Both the leaky bucket and the block should have expired by now, and `prune` should not raise
    adapter.prune
  end

  def test_create_tables
    adapter = create_adapter # Has to be in local scope
    ActiveRecord::Schema.define(version: 1) do |via_definer|
      adapter.create_tables(via_definer)
    end
  rescue ActiveRecord::ConnectionNotEstablished
    # This adapter does not require a connection
  end

  def xtest_should_accept_threadsafe_conditional_fillups
    k = random_key
    capacity = 30
    leak_rate = capacity / 0.5

    threads = 3.times.map do
      Thread.new do
        9.times do
          adapter.add_tokens_conditionally(key: k, leak_rate: leak_rate, capacity: capacity, n_tokens: 1)
        end
      end
    end
    threads.map(&:join)

    level, _ = adapter.state(key: k, capacity: capacity, leak_rate: leak_rate)
    assert_in_delta level, (3 * 9), LEVEL_DELTA
  end
end
