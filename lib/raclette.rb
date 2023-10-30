# frozen_string_literal: true

require_relative "raclette/version"
require_relative "raclette/leaky_bucket"
require_relative "raclette/throttle"
require_relative "raclette/railtie" if defined?(Rails::Railtie)

module Raclette
  def self.prune!
    # Delete all the old blocks here (if we are under a heavy swarm of requests which are all
    # blocked it is probably better to avoid the big delete)
    ActiveRecord::Base.connection.execute("DELETE FROM raclette_blocks WHERE blocked_until < NOW()")

    # Prune buckets which are no longer used. No "uncached" needed here since we are using "execute"
    ActiveRecord::Base.connection.execute("DELETE FROM raclette_leaky_buckets WHERE may_be_deleted_after < NOW()")
  end
end
