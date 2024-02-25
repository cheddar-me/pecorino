require_relative "../test_helper"
require_relative "adapter_test_methods"

class SqliteAdapterTest < ActiveSupport::TestCase
  include AdapterTestMethods

  setup { create_sqlite_db }
  teardown { drop_sqlite_db }

  def create_adapter
    Pecorino::Adapters::SqliteAdapter.new(ActiveRecord::Base)
  end
end
