# frozen_string_literal: true

require_relative "pecorino/version"
require_relative "pecorino/leaky_bucket"
require_relative "pecorino/throttle"
require_relative "pecorino/railtie" if defined?(Rails::Railtie)

module Pecorino
  # Deletes stale leaky buckets and blocks which have expired. Run this method regularly to
  # avoid accumulating too many unused rows in your tables.
  #
  # @return void
  def self.prune!
    # Delete all the old blocks here (if we are under a heavy swarm of requests which are all
    # blocked it is probably better to avoid the big delete)
    ActiveRecord::Base.connection.execute("DELETE FROM pecorino_blocks WHERE blocked_until < NOW()")

    # Prune buckets which are no longer used. No "uncached" needed here since we are using "execute"
    ActiveRecord::Base.connection.execute("DELETE FROM pecorino_leaky_buckets WHERE may_be_deleted_after < NOW()")
  end


  # Creates the tables and indexes needed for Pecorino. Call this from your migrations like so:
  #
  #     class CreatePecorinoTables < ActiveRecord::Migration[7.0]
  #       def change
  #         Pecorino.create_tables(self)
  #       end
  #     end
  #
  # @param active_record_schema[ActiveRecord::SchemaMigration] the migration through which we will create the tables
  # @return void
  def self.create_tables(active_record_schema)
    active_record_schema.create_table :pecorino_leaky_buckets, id: :uuid do |t|
      t.string :key, null: false
      t.float :level, null: false
      t.datetime :last_touched_at, null: false
      t.datetime :may_be_deleted_after, null: false
    end
    active_record_schema.add_index :pecorino_leaky_buckets, [:key], unique: true
    active_record_schema.add_index :pecorino_leaky_buckets, [:may_be_deleted_after]

    active_record_schema.create_table :pecorino_blocks, id: :uuid do |t|
      t.string :key, null: false
      t.datetime :blocked_until, null: false
    end
    active_record_schema.add_index :pecorino_blocks, [:key], unique: true
    active_record_schema.add_index :pecorino_blocks, [:blocked_until]
  end
end
