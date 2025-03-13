# frozen_string_literal: true

module Pecorino::Adapters::ConnectionShim
  def with_connection
    @model.connection.pool.with_connection do |conn|
      conn.uncached do
        yield(conn)
      end
    end
  end
end
