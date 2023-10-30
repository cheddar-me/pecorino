require "test_helper"

class LeakyBucketTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  # This test is performed multiple times since time is involved, and there can be fluctuations
  # between the iterations
  8.times do |n|
    test "on iteration #{n} accepts a certain number of tokens and returns the new bucket level" do
      slow_test!

      bucket = Raclette::LeakyBucket.new(key: Random.uuid, leak_rate: 1.1, capacity: 15)
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

  test "does not allow a bucket to be created with a negative value" do
    slow_test!

    bucket = Raclette::LeakyBucket.new(key: Random.uuid, leak_rate: 1.1, capacity: 15)
    assert_in_delta bucket.state.level, 0, 0.0001

    state = bucket.fillup(-10)
    assert_in_delta state.level, 0, 0.1
  end

  test "allows check for the bucket leaking out" do
    slow_test!

    bucket = Raclette::LeakyBucket.new(key: Random.uuid, leak_rate: 1.1, capacity: 15)
    assert_in_delta bucket.state.level, 0, 0.0001

    state = bucket.fillup(10)
    refute_predicate state, :full?

    refute bucket.able_to_accept?(6)
    assert bucket.able_to_accept?(4)
    assert_in_delta bucket.state.level, 10.0, 0.1
  end

  test "allows the bucket to leak out completely" do
    slow_test!

    bucket = Raclette::LeakyBucket.new(key: Random.uuid, leak_rate: 2, capacity: 1)
    assert_predicate bucket.fillup(1), :full?

    sleep(0.25)
    assert_in_delta bucket.state.level, 0.5, 0.1

    sleep(0.25)
    assert_in_delta bucket.state.level, 0, 0.1
  end
end
