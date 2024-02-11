# frozen_string_literal: true

require "test_helper"

class ThrottlePostgresTest < ActiveSupport::TestCase
  def setup
    create_postgres_database
  end

  def teardown
    drop_postgres_database
  end

  test "request! installs a block and then removes it and communicates the block using exceptions" do
    throttle = Pecorino::Throttle.new(key: Random.uuid, over_time: 1.0, capacity: 30)

    state_after_first_request = throttle.request!
    assert_kind_of Pecorino::Throttle::State, state_after_first_request

    # It must be possible to make exactly 30 requests without getting throttled, even if the
    # bucket does not leak out at all between the calls
    29.times do
      throttle.request!
    end

    # The 31st request must always fail, as it won't fit into the bucket anymore (even if some
    # tokens have leaked out by this point)
    err = assert_raises Pecorino::Throttle::Throttled do
      throttle.request!
    end
    assert_equal throttle, err.throttle
    assert_in_delta err.retry_after, 1, 0.1
    assert_kind_of Pecorino::Throttle::State, err.state

    # Sleep until the block gets released - the block gets for block_for, which is the time it takes the bucket
    # to leak out to 0
    sleep 1.1
    assert_nothing_raised do
      throttle.request!
    end
  end

  test "allows the block_for parameter to be omitted" do
    assert_nothing_raised do
      Pecorino::Throttle.new(key: Random.uuid, over_time: 1, capacity: 30)
    end
  end

  test "still throttles using request() without raising exceptions" do
    throttle = Pecorino::Throttle.new(key: Random.uuid, leak_rate: 30, capacity: 30, block_for: 3)

    20.times do
      state = throttle.request
      refute_predicate state, :blocked?
    end

    20.times do
      throttle.request
    end

    state = throttle.request
    assert_predicate state, :blocked?

    assert_in_delta state.blocked_until - Time.now, 3, 0.5
    sleep 0.5

    # Ensure we are still throttled
    state = throttle.request
    assert_predicate state, :blocked?
    assert_in_delta state.blocked_until - Time.now, 2.5, 0.5
    assert_kind_of Time, state.blocked_until

    sleep(3.05)
    state = throttle.request
    refute_predicate state, :blocked?
  end

  test "able_to_accept? returns the prediction whether the throttle will accept" do
    throttle = Pecorino::Throttle.new(key: Random.uuid, leak_rate: 30, capacity: 30, block_for: 2)

    assert throttle.able_to_accept?
    assert throttle.able_to_accept?(29)
    refute throttle.able_to_accept?(31)

    # Depending on timing either the 30th or the 31st request may start to throttle
    assert_raises Pecorino::Throttle::Throttled do
      loop { throttle.request! }
    end
    refute throttle.able_to_accept?

    sleep 2.5
    assert throttle.able_to_accept?
  end

  test "starts to throttle sooner with a higher fillup rate" do
    throttle = Pecorino::Throttle.new(key: Random.uuid, leak_rate: 30, capacity: 30, block_for: 3)

    15.times do
      throttle.request!(2)
    end

    # Depending on timing either the 31st or the 30th request may start to throttle
    err = assert_raises Pecorino::Throttle::Throttled do
      loop { throttle.request! }
    end

    assert_in_delta err.retry_after, 3, 0.5
  end
end
