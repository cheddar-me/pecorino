# frozen_string_literal: true

require_relative "../test_helper"
require_relative "adapter_test_methods"

class SqliteAdapterTest < ActiveSupport::TestCase
  include AdapterTestMethods

  setup { create_sqlite_db }
  teardown { drop_sqlite_db }

  def create_sqlite_db
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: db_filename)

    ActiveRecord::Schema.define(version: 1) do |via_definer|
      Pecorino.create_tables(via_definer)
    end
  end

  def drop_sqlite_db
    ActiveRecord::Base.connection.close
    FileUtils.rm_rf(db_filename)
    FileUtils.rm_rf(db_filename + "-wal")
    FileUtils.rm_rf(db_filename + "-shm")
  end

  def db_filename
    "pecorino_tests_%s.sqlite3" % Random.new(Minitest.seed).hex(4)
  end

  def create_adapter
    Pecorino::Adapters::SqliteAdapter.new(ActiveRecord::Base)
  end

  def test_create_tables
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("DROP TABLE pecorino_leaky_buckets")
      ActiveRecord::Base.connection.execute("DROP TABLE pecorino_blocks")
      # The adapter has to be in a variable as the schema definition is scoped to the migrator, not self
      retained_adapter = create_adapter # the schema define block is run via instance_exec so it does not retain scope
      ActiveRecord::Schema.define(version: 1) do |via_definer|
        retained_adapter.create_tables(via_definer)
      end
    end
    assert true
  end
end
