# frozen_string_literal: true

require "test_helper"

class LeakyBucketTest < ActiveSupport::TestCase
  def memory_adapter
    @adapter ||= Pecorino::Adapters::MemoryAdapter.new
  end

  # This test is performed multiple times since time is involved, and there can be fluctuations
  # between the iterations
  8.times do |n|
    test "on iteration #{n} accepts a certain number of tokens and returns the new bucket level" do
      bucket = Pecorino::LeakyBucket.new(key: Random.uuid, leak_rate: 1.1, capacity: 15, adapter: memory_adapter)
      assert_in_delta bucket.state.level, 0, 0.0001

      state = bucket.fillup(20)
      assert_predicate state, :full?
      assert_in_delta state.level, 15.0, 0.0001

      sleep 0.2
      assert_in_delta bucket.state.level, 14.77, 0.1

      sleep 0.3
      assert_in_delta bucket.state.level, 14.4, 0.1
      assert_in_delta bucket.fillup(-3).level, 11.4, 0.1

      assert_in_delta bucket.fillup(-300).level, 0, 0.1
    end
  end

  test "exposes the parameters via reader methods" do
    bucket = Pecorino::LeakyBucket.new(key: "some-bk", leak_rate: 1.1, capacity: 15, adapter: memory_adapter)
    assert_equal bucket.key, "some-bk"
    assert_equal bucket.leak_rate, 1.1
    assert_equal bucket.capacity, 15.0
  end

  test "translates over_time into an appropriate leak_rate at instantiation" do
    throttle = Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 10, capacity: 20, adapter: memory_adapter)
    assert_in_delta 2.0, throttle.leak_rate, 0.01
  end

  test "tells whether it is able to accept a value which will bring it to capacity" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, leak_rate: 1, capacity: 3, adapter: memory_adapter)
    assert bucket.able_to_accept?(3)
  end

  test "allows either of leak_rate or over_time to be used" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, leak_rate: 1.1, capacity: 15, adapter: memory_adapter)
    bucket.fillup(20)
    sleep 0.2
    assert_in_delta bucket.state.level, 14.77, 0.1

    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 13.6, capacity: 15, adapter: memory_adapter)
    bucket.fillup(20)
    sleep 0.2
    assert_in_delta bucket.state.level, 14.77, 0.1

    assert_raises(ArgumentError) do
      Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 13.6, leak_rate: 1.1, capacity: 15, adapter: memory_adapter)
    end

    assert_raises(ArgumentError) do
      Pecorino::LeakyBucket.new(key: Random.uuid, capacity: 15, adapter: memory_adapter)
    end
  end

  test "does not allow a bucket to be created with a negative value" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, leak_rate: 1.1, capacity: 15, adapter: memory_adapter)
    assert_in_delta bucket.state.level, 0, 0.0001

    state = bucket.fillup(-10)
    assert_in_delta state.level, 0, 0.1
  end

  test "allows check for the bucket leaking out" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, leak_rate: 1.1, capacity: 15, adapter: memory_adapter)
    assert_in_delta bucket.state.level, 0, 0.0001

    state = bucket.fillup(10)
    refute_predicate state, :full?

    refute bucket.able_to_accept?(6)
    assert bucket.able_to_accept?(4)
    assert_in_delta bucket.state.level, 10.0, 0.1
  end

  test "allows the bucket to leak out completely" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, leak_rate: 2, capacity: 1, adapter: memory_adapter)
    assert_predicate bucket.fillup(1), :full?

    sleep(0.25)
    assert_in_delta bucket.state.level, 0.5, 0.1

    sleep(0.25)
    assert_in_delta bucket.state.level, 0, 0.1
  end

  test "with conditional fillup, allows a freshly created bucket to be filled to capacity with one call" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 1.0, capacity: 1.0, adapter: memory_adapter)
    assert bucket.fillup_conditionally(1.0).accepted?
  end

  test "with conditional fillup, refuses a fillup that would overflow" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 1.0, capacity: 1.0, adapter: memory_adapter)
    refute bucket.fillup_conditionally(1.1).accepted?
  end

  test "with conditional fillup, allows an existing bucket to be filled to capacity on the second call (INSERT vs. UPDATE)" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 1.0, capacity: 1.0, adapter: memory_adapter)
    bucket.fillup(0.0) # Ensure the bucket row gets created
    assert bucket.fillup_conditionally(1.0).accepted?
  end

  test "with conditional fillup, allows an existing bucket to be filled to capacity in a sequence of calls" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 1.0, capacity: 1.0, adapter: memory_adapter)
    assert bucket.fillup_conditionally(0.5).accepted?
    assert bucket.fillup_conditionally(0.5).accepted?
    refute bucket.fillup_conditionally(0.1).accepted?
  end

  test "with conditional fillup, allows an existing bucket to be filled close to capacity in a sequence of calls" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 1.0, capacity: 1.0, adapter: memory_adapter)
    assert bucket.fillup_conditionally(0.5).accepted?
    assert bucket.fillup_conditionally(0.4).accepted?
    refute bucket.fillup_conditionally(0.2).accepted?
  end

  test "allows conditional fillup" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 1.0, capacity: 1.0, adapter: memory_adapter)

    counter = 0
    try_fillup = ->(fillup_by, should_have_reached_level, should_have_accepted) {
      counter += 1
      state = bucket.fillup_conditionally(fillup_by)
      assert_equal should_have_accepted, state.accepted?, "Update #{counter} did_accept should be #{should_have_accepted}"
      assert_in_delta should_have_reached_level, state.level, 0.1
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

  test "allows conditional fillup even if the bucket leaks out to 0 between calls" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 0.5, capacity: 30, adapter: memory_adapter)
    assert bucket.fillup_conditionally(29.6).accepted?
    refute bucket.fillup_conditionally(1).accepted?
    sleep 0.6 # Spend enough time to allow the bucket to leak out completely
    assert bucket.fillup_conditionally(1).accepted?, "Once the bucket has leaked out to 0 the fillup should be accepted again"
  end
end
