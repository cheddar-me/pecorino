# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"
require "yard"

YARD::Rake::YardocTask.new(:doc)

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task :format do
  `bundle exec standardrb --fix`
  `bundle exec magic_frozen_string_literal .`
end

task :generate_typedefs do
  `bundle exec sord rbi/pecorino.rbi`
  `bundle exec sord rbi/pecorino.rbs`
end

task default: [:test, :standard, :generate_typedefs]

# When building the gem, generate typedefs beforehand,
# so that they get included
Rake::Task["build"].enhance(["generate_typedefs"])
