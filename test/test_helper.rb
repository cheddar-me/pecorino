# frozen_string_literal: true

require "bundler"
Bundler.setup

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "pecorino"

require "minitest/autorun"
require "active_support"
require "active_support/test_case"
require "active_record"

class ActiveSupport::TestCase
end
