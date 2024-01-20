# frozen_string_literal: true

require "test_helper"

class LeakyBucketPostgresTest < ActiveSupport::TestCase
  def setup
    create_postgres_database
  end

  def teardown
    drop_postgres_database
  end

  # This test is performed multiple times since time is involved, and there can be fluctuations
  # between the iterations
  8.times do |n|
    test "on iteration #{n} accepts a certain number of tokens and returns the new bucket level" do
      bucket = Pecorino::LeakyBucket.new(key: Random.uuid, leak_rate: 1.1, capacity: 15)
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
    bucket = Pecorino::LeakyBucket.new(key: "some-bk", leak_rate: 1.1, capacity: 15)
    assert_equal bucket.key, "some-bk"
    assert_equal bucket.leak_rate, 1.1
    assert_equal bucket.capacity, 15.0
  end

  test "allows either of leak_rate or over_time to be used" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, leak_rate: 1.1, capacity: 15)
    bucket.fillup(20)
    sleep 0.2
    assert_in_delta bucket.state.level, 14.77, 0.1

    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 13.6, capacity: 15)
    bucket.fillup(20)
    sleep 0.2
    assert_in_delta bucket.state.level, 14.77, 0.1

    assert_raises(ArgumentError) do
      Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 13.6, leak_rate: 1.1, capacity: 15)
    end

    assert_raises(ArgumentError) do
      Pecorino::LeakyBucket.new(key: Random.uuid, capacity: 15)
    end
  end

  test "does not allow a bucket to be created with a negative value" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, leak_rate: 1.1, capacity: 15)
    assert_in_delta bucket.state.level, 0, 0.0001

    state = bucket.fillup(-10)
    assert_in_delta state.level, 0, 0.1
  end

  test "allows check for the bucket leaking out" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, leak_rate: 1.1, capacity: 15)
    assert_in_delta bucket.state.level, 0, 0.0001

    state = bucket.fillup(10)
    refute_predicate state, :full?

    refute bucket.able_to_accept?(6)
    assert bucket.able_to_accept?(4)
    assert_in_delta bucket.state.level, 10.0, 0.1
  end

  test "allows the bucket to leak out completely" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, leak_rate: 2, capacity: 1)
    assert_predicate bucket.fillup(1), :full?

    sleep(0.25)
    assert_in_delta bucket.state.level, 0.5, 0.1

    sleep(0.25)
    assert_in_delta bucket.state.level, 0, 0.1
  end

  test "allows conditional fillup using fillup_if_able" do
    bucket = Pecorino::LeakyBucket.new(key: Random.uuid, over_time: 0.2, capacity: 1.0)

    state_after_first_fillup = bucket.fillup_if_able(0.6)
    assert_in_delta state_after_first_fillup.level, 0.6, 0.1
    assert_predicate state_after_first_fillup, :did_accept?

    state_after_second_fillup = bucket.fillup_if_able(0.3)
    assert_in_delta state_after_second_fillup.level, 0.9, 0.1
    assert_predicate state_after_second_fillup, :did_accept?

    state_after_third_fillup = bucket.fillup_if_able(0.3) # Would take the bucket to 1.2, so must be refused
    assert_in_delta state_after_third_fillup.level, 0.9, 0.1
    refute_predicate state_after_third_fillup, :did_accept?
  end
end
