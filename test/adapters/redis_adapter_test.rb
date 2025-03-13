# frozen_string_literal: true

require_relative "../test_helper"
require_relative "adapter_test_methods"

class RedisAdapterTest < ActiveSupport::TestCase
  include AdapterTestMethods

  teardown { delete_created_keys }

  def create_adapter
    Pecorino::Adapters::RedisAdapter.new(new_redis, key_prefix: key_prefix)
  end

  def key_prefix
    "pecorino-test" + Random.new(Minitest.seed).bytes(4)
  end

  def delete_created_keys
    r = new_redis
    r.del(r.keys(key_prefix + "*"))
  end

  def new_redis
    Redis.new
  end

  undef :test_create_tables
end
