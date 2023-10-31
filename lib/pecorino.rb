# frozen_string_literal: true

require_relative "pecorino/version"
require_relative "pecorino/leaky_bucket"
require_relative "pecorino/throttle"
require_relative "pecorino/railtie" if defined?(Rails::Railtie)

module Pecorino
  def self.prune!
    # Delete all the old blocks here (if we are under a heavy swarm of requests which are all
    # blocked it is probably better to avoid the big delete)
    ActiveRecord::Base.connection.execute("DELETE FROM pecorino_blocks WHERE blocked_until < NOW()")

    # Prune buckets which are no longer used. No "uncached" needed here since we are using "execute"
    ActiveRecord::Base.connection.execute("DELETE FROM pecorino_leaky_buckets WHERE may_be_deleted_after < NOW()")
  end
end
