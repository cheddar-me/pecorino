# frozen_string_literal: true

require "test_helper"

class PecorinoThrottleTest < ActiveSupport::TestCase
  def random_leaky_bucket_name(random: Random.new)
    (1..32).map do
      # bytes 97 to 122 are printable lowercase a-z
      random.rand(97..122)
    end.pack("C*")
  end

  setup do
    seed_db_name = Random.new(Minitest.seed).hex(4)
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: "postgres")
    ActiveRecord::Base.connection.create_database("pecorino_tests_%s" % seed_db_name, charset: :unicode)
    ActiveRecord::Base.connection.close
    ActiveRecord::Base.establish_connection(adapter: "postgresql", encoding: "unicode", database: "pecorino_tests_%s" % seed_db_name)

    ActiveRecord::Schema.define(version: 1) do |via_definer|
      Pecorino.create_tables(via_definer)
    end
  end

  teardown do
    seed_db_name = Random.new(Minitest.seed).hex(4)
    ActiveRecord::Base.connection.close
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: "postgres")
    ActiveRecord::Base.connection.drop_database("pecorino_tests_%s" % seed_db_name)
  end

  test "throttles using request!() and blocks" do
    throttle = Pecorino::Throttle.new(key: random_leaky_bucket_name, leak_rate: 30, capacity: 30, block_for: 3)

    29.times do
      throttle.request!
    end

    # Depending on timing either the 31st or the 30th request may start to throttle
    err = assert_raises Pecorino::Throttle::Throttled do
      loop { throttle.request! }
    end

    assert_in_delta err.retry_after, 3, 0.5
    sleep 0.5

    # Ensure we are still throttled
    err = assert_raises Pecorino::Throttle::Throttled do
      throttle.request!
    end
    assert_equal throttle, err.throttle
    assert_in_delta err.retry_after, 2.5, 0.5

    sleep(3.05)
    assert_nothing_raised do
      throttle.request!
    end
  end

  test "still throttles using request() without raising exceptions" do
    throttle = Pecorino::Throttle.new(key: random_leaky_bucket_name, leak_rate: 30, capacity: 30, block_for: 3)

    20.times do
      state = throttle.request
      refute_predicate state, :blocked?
    end

    20.times do
      throttle.request
    end

    state = throttle.request
    assert_predicate state, :blocked?

    assert_in_delta state.retry_after, 3, 0.5
    sleep 0.5

    # Ensure we are still throttled
    state = throttle.request
    assert_predicate state, :blocked?
    assert_in_delta state.retry_after, 2.5, 0.5
    assert_kind_of Time, state.blocked_until

    sleep(3.05)
    state = throttle.request
    refute_predicate state, :blocked?
  end

  test "able_to_accept? returns the prediction whether the throttle will accept" do
    throttle = Pecorino::Throttle.new(key: random_leaky_bucket_name, leak_rate: 30, capacity: 30, block_for: 2)

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
    throttle = Pecorino::Throttle.new(key: random_leaky_bucket_name, leak_rate: 30, capacity: 30, block_for: 3)

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
