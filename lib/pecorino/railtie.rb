# frozen_string_literal: true

module Pecorino
  class Railtie < Rails::Railtie
    generators do
      require_relative "install_generator"
    end
  end
end
