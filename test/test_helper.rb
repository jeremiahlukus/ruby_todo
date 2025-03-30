# frozen_string_literal: true

ENV["MT_NO_PLUGINS"] = "true" # Disable Rails plugins in Minitest
require "minitest/autorun"
require "ruby_todo"
require "ruby_todo/commands/ai_assistant"
require "ruby_todo/ai_assistant/openai_integration"
require "openai"
require "fileutils"

# Set test environment
ENV["RUBY_TODO_TEST"] = "true"
ENV["RUBY_TODO_ENV"] = "test"

# Set up test database
module RubyTodo
  class Database
    class << self
      def test_setup
        return if ActiveRecord::Base.connected?

        ensure_test_database_directory
        establish_test_connection
        create_tables
      end

      private

      def ensure_test_database_directory
        db_dir = File.expand_path("~/.ruby_todo/test")
        FileUtils.mkdir_p(db_dir)
      end

      def establish_test_connection
        db_path = File.expand_path("~/.ruby_todo/test/ruby_todo_test.db")
        ActiveRecord::Base.establish_connection(
          adapter: "sqlite3",
          database: db_path
        )
      end

      def create_tables
        connection = ActiveRecord::Base.connection

        ActiveRecord::Schema.define do
          unless connection.table_exists?(:notebooks)
            create_table :notebooks do |t|
              t.string :name, null: false
              t.boolean :is_default, default: false
              t.timestamps
            end
          end

          unless connection.table_exists?(:tasks)
            create_table :tasks do |t|
              t.references :notebook, null: false
              t.string :title, null: false
              t.text :description
              t.string :status, default: "todo"
              t.datetime :due_date
              t.string :priority
              t.string :tags
              t.timestamps
            end
          end

          unless connection.table_exists?(:templates)
            create_table :templates do |t|
              t.string :name, null: false
              t.string :title_pattern, null: false
              t.text :description_pattern
              t.string :priority
              t.string :tags_pattern
              t.string :due_date_offset
              t.references :notebook
              t.timestamps
            end
          end

          # Add indexes if they don't exist
          unless connection.index_exists?(:tasks, %i[notebook_id status])
            add_index :tasks, %i[notebook_id status]
          end

          unless connection.index_exists?(:tasks, :priority)
            add_index :tasks, :priority
          end

          unless connection.index_exists?(:tasks, :due_date)
            add_index :tasks, :due_date
          end

          unless connection.index_exists?(:templates, :name)
            add_index :templates, :name, unique: true
          end

          unless connection.index_exists?(:notebooks, :is_default)
            add_index :notebooks, :is_default
          end
        end
      end
    end
  end
end

# Set up test environment
RubyTodo::Database.test_setup

module Minitest
  class Test
    def setup
      super
      RubyTodo::Task.delete_all
      RubyTodo::Notebook.delete_all
      RubyTodo::Template.delete_all
    end

    def teardown
      super
      # Clean up test database after each test
      RubyTodo::Task.delete_all
      RubyTodo::Notebook.delete_all
      RubyTodo::Template.delete_all
    end

    def run_with_retry
      retries = 0
      begin
        yield
      rescue OpenAI::Error => e
        retries += 1
        if retries < 3
          puts "OpenAI API error (attempt #{retries}/3): #{e.message}"
          sleep(2**retries) # Exponential backoff
          retry
        else
          raise
        end
      end
    end
  end
end
