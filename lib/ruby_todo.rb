# frozen_string_literal: true

require_relative "ruby_todo/version"
require_relative "ruby_todo/database"
require_relative "ruby_todo/models/notebook"
require_relative "ruby_todo/models/task"
require_relative "ruby_todo/models/template"
require_relative "ruby_todo/cli"

module RubyTodo
  class Error < StandardError; end

  def self.start
    CLI.start(ARGV)
  end
end
