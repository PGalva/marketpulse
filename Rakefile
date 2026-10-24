# frozen_string_literal: true

require "rake/testtask"

# `rake test` roda todos os arquivos test/**/*_test.rb
Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.pattern = "test/**/*_test.rb"
  t.warning = false
end

task default: :test
