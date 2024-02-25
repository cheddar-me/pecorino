# frozen_string_literal: true

class Pecorino::Adapters::DatabaseAdapter
  attr_reader :model_class

  def initialize(model_class)
    @model_class = model_class
  end

  def prune
    # Delete all the old blocks here (if we are under a heavy swarm of requests which are all
    # blocked it is probably better to avoid the big delete)
    model_class.connection.execute("DELETE FROM pecorino_blocks WHERE blocked_until < NOW()")

    # Prune buckets which are no longer used. No "uncached" needed here since we are using "execute"
    model_class.connection.execute("DELETE FROM pecorino_leaky_buckets WHERE may_be_deleted_after < NOW()")
  end

  def create_tables(active_record_schema)
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
