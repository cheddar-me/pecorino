require_relative "../test_helper"
require_relative "adapter_test_methods"

class PostgresAdapterTest < ActiveSupport::TestCase
  include AdapterTestMethods

  setup { create_postgres_database_if_none }
  teardown { truncate_test_tables }

  def create_adapter
    Pecorino::Adapters::PostgresAdapter.new(ActiveRecord::Base)
  end

  SEED_DB_NAME = -> { "pecorino_tests_%s" % Random.new(Minitest.seed).hex(4) }

  def create_postgres_database_if_none
    ActiveRecord::Base.establish_connection(adapter: "postgresql", encoding: "unicode", database: SEED_DB_NAME.call)
    ActiveRecord::Base.connection.execute("SELECT 1 FROM pecorino_leaky_buckets")
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    create_postgres_database
    retry
  rescue ActiveRecord::StatementInvalid
    retained_adapter = adapter # the schema define block is run via instance_exec so it does not retain scope
    ActiveRecord::Schema.define(version: 1) do |via_definer|
      retained_adapter.create_tables(via_definer)
    end
    retry
  end

  def create_postgres_database
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: "postgres")
    ActiveRecord::Base.connection.create_database(SEED_DB_NAME.call, charset: :unicode)
    ActiveRecord::Base.connection.close
    ActiveRecord::Base.establish_connection(adapter: "postgresql", encoding: "unicode", database: SEED_DB_NAME.call)
  end

  def truncate_test_tables
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE pecorino_leaky_buckets")
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE pecorino_blocks")
  end

  Minitest.after_run do
    ActiveRecord::Base.connection.close
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: "postgres")
    ActiveRecord::Base.connection.drop_database(SEED_DB_NAME.call)
  end
end
