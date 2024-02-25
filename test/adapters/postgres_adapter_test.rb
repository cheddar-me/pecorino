require_relative "../test_helper"
require_relative "adapter_test_methods"

class PostgresAdapterTest < ActiveSupport::TestCase
  include AdapterTestMethods

  setup do
    create_postgres_database
    @adapter = Pecorino::Adapters::PostgresAdapter.new(ActiveRecord::Base)
  end

  teardown { drop_postgres_database }
end

