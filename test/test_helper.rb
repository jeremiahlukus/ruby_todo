# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruby_todo"
require "minitest/autorun"
require "fileutils"

# Set up test database
module RubyTodo
  class Database
    class << self
      alias original_setup setup

      def setup
        return if ActiveRecord::Base.connected?

        # Use in-memory database for tests
        ActiveRecord::Base.establish_connection(
          adapter: "sqlite3",
          database: ":memory:"
        )

        create_tables
      end
    end
  end
end

# Configure ActiveRecord for testing
ActiveRecord::Base.logger = nil
