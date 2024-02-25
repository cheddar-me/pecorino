require_relative "../test_helper"
require_relative "adapter_test_methods"

class MemoryAdapterTest < Minitest::Test
  include AdapterTestMethods

  def setup
    @adapter = Pecorino::Adapters::MemoryAdapter.new
    super
  end

  def teardown
    @adapter = nil
    super
  end
end
