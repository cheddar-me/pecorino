# frozen_string_literal: true

require "test_helper"

class PecorinoTest < ActiveSupport::TestCase
  test "has a version number" do
    refute_nil ::Pecorino::VERSION
  end
end
