# frozen_string_literal: true

require_relative "../test_helper"
require_relative "adapter_test_methods"

class PostgresAdapterTest < ActiveSupport::TestCase
  include AdapterTestMethods

  setup { create_postgres_database_if_none }
  teardown { truncate_test_tables }

  def self.establish_connection(**options)
    ActiveRecord::Base.establish_connection(
      adapter: "postgresql",
      connect_timeout: 2,
      **options
    )
  end

  def create_adapter
    Pecorino::Adapters::PostgresAdapter.new(ActiveRecord::Base)
  end

  SEED_DB_NAME = -> { "pecorino_tests_%s" % Random.new(Minitest.seed).hex(4) }

  def create_postgres_database_if_none
    self.class.establish_connection(encoding: "unicode", database: SEED_DB_NAME.call)
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
    self.class.establish_connection(database: "postgres")
    ActiveRecord::Base.connection.create_database(SEED_DB_NAME.call, charset: :unicode)
    ActiveRecord::Base.connection.close
    self.class.establish_connection(encoding: "unicode", database: SEED_DB_NAME.call)
  end

  def truncate_test_tables
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE pecorino_leaky_buckets")
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE pecorino_blocks")
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

  Minitest.after_run do
    ActiveRecord::Base.connection.close
    establish_connection(database: "postgres")
    ActiveRecord::Base.connection.drop_database(SEED_DB_NAME.call)
  end
end
