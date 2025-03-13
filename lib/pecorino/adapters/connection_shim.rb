# frozen_string_literal: true

module Pecorino::Adapters::ConnectionShim
  def with_connection
    raise "No @model_class in #{self.inspect} - unable to obtain connection" unless @model_class
    @model_class.connection.pool.with_connection do |conn|
      conn.uncached do
        yield(conn)
      end
    end
  end
end
