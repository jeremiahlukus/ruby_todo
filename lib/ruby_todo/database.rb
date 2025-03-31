# frozen_string_literal: true

require "active_record"
require "sqlite3"
require "fileutils"

module RubyTodo
  class Database
    class << self
      def setup
        return if ActiveRecord::Base.connected?

        ensure_database_directory
        establish_connection
        create_tables
      end

      def initialized?
        # Try to check if the database exists and is set up
        db_path = File.expand_path("~/.ruby_todo/ruby_todo.db")
        File.exist?(db_path) && ActiveRecord::Base.connected?
      rescue StandardError
        false
      end

      def db
        # Ensure connection is established
        setup unless initialized?

        # Return connection
        ActiveRecord::Base.connection
      end

      private

      def ensure_database_directory
        db_dir = File.expand_path("~/.ruby_todo")
        FileUtils.mkdir_p(db_dir)
      end

      def establish_connection
        db_path = File.expand_path("~/.ruby_todo/ruby_todo.db")
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
