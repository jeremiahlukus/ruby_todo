# frozen_string_literal: true

require "active_record"
require "sqlite3"
require "fileutils"

module RubyTodo
  class Database
    class << self
      def setup
        return if ActiveRecord::Base.connected?

        db_path = File.expand_path("~/.ruby_todo/todo.db")
        FileUtils.mkdir_p(File.dirname(db_path))

        ActiveRecord::Base.establish_connection(
          adapter: "sqlite3",
          database: db_path
        )

        create_tables unless tables_exist?
        check_schema_version
      end

      private

      def tables_exist?
        ActiveRecord::Base.connection.tables.include?("notebooks") &&
          ActiveRecord::Base.connection.tables.include?("tasks") &&
          ActiveRecord::Base.connection.tables.include?("schema_migrations")
      end

      def create_tables
        ActiveRecord::Schema.define do
          create_table :notebooks do |t|
            t.string :name, null: false
            t.timestamps
          end

          create_table :tasks do |t|
            t.references :notebook, null: false, foreign_key: true
            t.string :title, null: false
            t.string :status, null: false, default: "todo"
            t.text :description
            t.datetime :due_date
            t.string :priority
            t.string :tags
            t.timestamps
          end

          create_table :templates do |t|
            t.references :notebook, foreign_key: true
            t.string :name, null: false
            t.string :title_pattern, null: false
            t.text :description_pattern
            t.string :tags_pattern
            t.string :priority
            t.string :due_date_offset
            t.timestamps
          end

          add_index :tasks, %i[notebook_id status]
          add_index :tasks, :priority
          add_index :tasks, :due_date
          add_index :templates, :name, unique: true

          create_table :schema_migrations do |t|
            t.integer :version, null: false
          end
        end

        # Set initial schema version
        ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES (2)")
      end

      def check_schema_version
        # Get current schema version
        current_version = ActiveRecord::Base.connection.select_value("SELECT MAX(version) FROM schema_migrations").to_i

        # If needed, perform migrations
        if current_version < 1
          upgrade_to_version_1
        end

        if current_version < 2
          upgrade_to_version_2
        end
      end

      def upgrade_to_version_1
        ActiveRecord::Base.connection.execute(<<-SQL)
          ALTER TABLE tasks ADD COLUMN priority STRING;
          ALTER TABLE tasks ADD COLUMN tags STRING;
        SQL

        ActiveRecord::Base.connection.execute("UPDATE schema_migrations SET version = 1")
      end

      def upgrade_to_version_2
        ActiveRecord::Base.connection.execute(<<-SQL)
          CREATE TABLE templates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            notebook_id INTEGER,
            name VARCHAR NOT NULL,
            title_pattern VARCHAR NOT NULL,
            description_pattern TEXT,
            tags_pattern VARCHAR,
            priority VARCHAR,
            due_date_offset VARCHAR,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            FOREIGN KEY (notebook_id) REFERENCES notebooks(id)
          );
          CREATE UNIQUE INDEX index_templates_on_name ON templates (name);
        SQL

        ActiveRecord::Base.connection.execute("UPDATE schema_migrations SET version = 2")
      end
    end
  end
end
