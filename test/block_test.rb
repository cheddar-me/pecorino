# frozen_string_literal: true

require_relative "test_helper"
require "base64"

class BlockTest < ActiveSupport::TestCase
  def setup
    Pecorino.adapter = Pecorino::Adapters::MemoryAdapter.new
  end

  test "sets a block" do
    k = Base64.strict_encode64(Random.bytes(4))
    assert_nil Pecorino::Block.blocked_until(key: k)
    assert Pecorino::Block.set!(key: k, block_for: 30 * 60)

    blocked_until = Pecorino::Block.blocked_until(key: k)
    assert_in_delta Time.now + (30 * 60), blocked_until, 10
  end

  test "does not return a block which has lapsed" do
    k = Base64.strict_encode64(Random.bytes(4))
    assert_nil Pecorino::Block.blocked_until(key: k)
    Pecorino::Block.set!(key: k, block_for: -30 * 60)
    blocked_until = Pecorino::Block.blocked_until(key: k)
    assert_nil blocked_until
  end
end
