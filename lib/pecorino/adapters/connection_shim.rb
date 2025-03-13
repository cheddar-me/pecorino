# frozen_string_literal: true

module Pecorino::Adapters::ConnectionShim
  def sanitize_sql_array(*args)
    raise "No @model_class in #{inspect} - unable to obtain connection" unless @model_class
    @model_class.sanitize_sql_array(*args)
  end

  def with_connection
    raise "No @model_class in #{inspect} - unable to obtain connection" unless @model_class
    @model_class.connection.pool.with_connection do |conn|
      conn.uncached { yield(conn) }
    end
  end
end
