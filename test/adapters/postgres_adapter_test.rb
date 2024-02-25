require_relative "../test_helper"
require_relative "adapter_test_methods"

class PostgresAdapterTest < ActiveSupport::TestCase
  include AdapterTestMethods

  setup { create_postgres_database }
  teardown { drop_postgres_database }

  def create_adapter
    Pecorino::Adapters::PostgresAdapter.new(ActiveRecord::Base)
  end

  def create_postgres_database
    seed_db_name = Random.new(Minitest.seed).hex(4)
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: "postgres")
    ActiveRecord::Base.connection.create_database("pecorino_tests_%s" % seed_db_name, charset: :unicode)
    ActiveRecord::Base.connection.close
    ActiveRecord::Base.establish_connection(adapter: "postgresql", encoding: "unicode", database: "pecorino_tests_%s" % seed_db_name)

    ActiveRecord::Schema.define(version: 1) do |via_definer|
      Pecorino.create_tables(via_definer)
    end
  end

  def drop_postgres_database
    seed_db_name = Random.new(Minitest.seed).hex(4)
    ActiveRecord::Base.connection.close
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: "postgres")
    ActiveRecord::Base.connection.drop_database("pecorino_tests_%s" % seed_db_name)
  end
end
