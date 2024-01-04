# frozen_string_literal: true

require "test_helper"

class LeakyBucketSqliteTest < LeakyBucketPostgresTest
  def setup
    setup_sqlite_db
  end

  def teardown
    drop_sqlite_db
  end
end
