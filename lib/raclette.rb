# frozen_string_literal: true

require_relative "raclette/version"
require_relative "raclette/leaky_bucket"
require_relative "raclette/throttle"
require_relative "raclette/railtie" if defined?(Rails::Railtie)

module Raclette
end
