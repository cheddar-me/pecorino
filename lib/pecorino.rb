# frozen_string_literal: true

require "active_support/concern"
require "active_record/sanitization"

require_relative "pecorino/version"
require_relative "pecorino/railtie" if defined?(Rails::Railtie)

module Pecorino
  autoload :LeakyBucket, "pecorino/leaky_bucket"
  autoload :Block, "pecorino/block"
  autoload :Throttle, "pecorino/throttle"
  autoload :CachedThrottle, "pecorino/cached_throttle"

  module Adapters
    autoload :MemoryAdapter, "pecorino/adapters/memory_adapter"
    autoload :PostgresAdapter, "pecorino/adapters/postgres_adapter"
    autoload :SqliteAdapter, "pecorino/adapters/sqlite_adapter"
    autoload :RedisAdapter, "pecorino/adapters/redis_adapter"
  end

  # Deletes stale leaky buckets and blocks which have expired. Run this method regularly to
  # avoid accumulating too many unused rows in your tables.
  #
  # @return void
  def self.prune!
    adapter.prune
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
    adapter.create_tables(active_record_schema)
  end

  # Allows assignment of an adapter for storing throttles. Normally this would be a subclass of `Pecorino::Adapters::BaseAdapter`, but
  # you can assign anything you like. Set this in an initializer. By default Pecorino will use the adapter configured from your main
  # database, but you can also create a separate database for it - or use Redis or memory storage.
  #
  # @param adapter[Pecorino::Adapters::BaseAdapter]
  # @return [Pecorino::Adapters::BaseAdapter]
  def self.adapter=(adapter)
    @adapter = adapter
  end

  # Returns the currently configured adapter, or the default adapter from the main database
  #
  # @return [Pecorino::Adapters::BaseAdapter]
  def self.adapter
    @adapter || default_adapter_from_main_database
  end

  # Returns the database implementation for setting the values atomically. Since the implementation
  # differs per database, this method will return a different adapter depending on which database is
  # being used.
  #
  # @return [Pecorino::Adapters::BaseAdapter]
  def self.default_adapter_from_main_database
    adapter_name = ActiveRecord::Base.connection_pool.with_connection(&:adapter_name)

    case adapter_name
    when /postgres/i
      Pecorino::Adapters::PostgresAdapter.new(model_class)
    when /sqlite/i
      Pecorino::Adapters::SqliteAdapter.new(model_class)
    else
      raise "Pecorino does not support the #{adapter_name} database just yet"
    end
  end
end
