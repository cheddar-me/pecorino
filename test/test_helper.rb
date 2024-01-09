# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "pecorino"

require "minitest/autorun"
require "active_support"
require "active_support/test_case"
require "active_record"

class ActiveSupport::TestCase
  def setup_sqlite_db
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: test_db_filename)

    ActiveRecord::Schema.define(version: 1) do |via_definer|
      Pecorino.create_tables(via_definer)
    end
  end

  def drop_sqlite_db
    ActiveRecord::Base.connection.close
    FileUtils.rm_rf(test_db_filename)
  end

  def test_db_filename
    "pecorino_tests_%s.sqlite3" % Random.new(Minitest.seed).hex(4)
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
