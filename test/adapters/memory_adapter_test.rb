require_relative "../test_helper"
require_relative "adapter_test_methods"

class MemoryAdapterTest < ActiveSupport::TestCase
  include AdapterTestMethods

  def create_adapter
    Pecorino::Adapters::MemoryAdapter.new
  end
end
