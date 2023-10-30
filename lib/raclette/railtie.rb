module Raclette
  class Railtie < Rails::Railtie
    generators do
      require "path/to/my_railtie_generator"
    end
  end
end