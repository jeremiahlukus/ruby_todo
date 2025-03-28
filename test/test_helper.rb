# frozen_string_literal: true

ENV["MT_NO_PLUGINS"] = "true" # Disable Rails plugins in Minitest
require "minitest/autorun"
require "ruby_todo"

# Set up test environment
RubyTodo::Database.setup

module Minitest
  class Test
    def setup
      super
      # Clean up test database before each test
      RubyTodo::Task.delete_all
      RubyTodo::Notebook.delete_all
    end

    def teardown
      super
      # Clean up test database after each test
      RubyTodo::Task.delete_all
      RubyTodo::Notebook.delete_all
    end
  end
end
