# frozen_string_literal: true

require "test_helper"
require_relative "leaky_bucket_postgres_test"

class LeakyBucketSqliteTest < LeakyBucketPostgresTest
  def setup
    setup_sqlite_db
  end

  def teardown
    drop_sqlite_db
  end
end
