require_relative "../test_helper"
require_relative "adapter_test_methods"

class SqliteAdapterTest < ActiveSupport::TestCase
  include AdapterTestMethods

  setup { create_sqlite_db }
  teardown { drop_sqlite_db }

  def create_sqlite_db
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: test_db_filename)

    ActiveRecord::Schema.define(version: 1) do |via_definer|
      Pecorino.create_tables(via_definer)
    end
  end

  def drop_sqlite_db
    ActiveRecord::Base.connection.close
    FileUtils.rm_rf(test_db_filename)
    FileUtils.rm_rf(test_db_filename + "-wal")
    FileUtils.rm_rf(test_db_filename + "-shm")
  end

  def test_db_filename
    "pecorino_tests_%s.sqlite3" % Random.new(Minitest.seed).hex(4)
  end

  def create_adapter
    Pecorino::Adapters::SqliteAdapter.new(ActiveRecord::Base)
  end
end
