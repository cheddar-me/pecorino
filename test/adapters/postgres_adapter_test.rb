require_relative "../test_helper"
require_relative "adapter_test_methods"

class PostgresAdapterTest < ActiveSupport::TestCase
  include AdapterTestMethods

  setup { create_postgres_database }
  teardown { drop_postgres_database }

  def create_adapter
    Pecorino::Adapters::PostgresAdapter.new(ActiveRecord::Base)
  end
end

