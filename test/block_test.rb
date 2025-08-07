# frozen_string_literal: true

require "test_helper"
require "base64"

class BlockTest < ActiveSupport::TestCase
  def setup
    @adapter = Pecorino::Adapters::MemoryAdapter.new
  end

  test "sets a block" do
    k = Base64.strict_encode64(Random.bytes(4))
    assert_nil Pecorino::Block.blocked_until(key: k, adapter: @adapter)
    assert Pecorino::Block.set!(key: k, block_for: 30.minutes, adapter: @adapter)

    blocked_until = Pecorino::Block.blocked_until(key: k, adapter: @adapter)
    assert_in_delta Time.now + 30.minutes, blocked_until, 10
  end

  test "does not return a block which has lapsed" do
    k = Base64.strict_encode64(Random.bytes(4))
    assert_nil Pecorino::Block.blocked_until(key: k, adapter: @adapter)
    Pecorino::Block.set!(key: k, block_for: -30.minutes, adapter: @adapter)
    blocked_until = Pecorino::Block.blocked_until(key: k, adapter: @adapter)
    assert_nil blocked_until
  end
end
