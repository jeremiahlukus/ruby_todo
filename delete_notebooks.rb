#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/ruby_todo"
require_relative "lib/ruby_todo/database"

# Ensure database connection is established first
RubyTodo::Database.setup

def count_records
  {
    tasks: RubyTodo::Task.count,
    notebooks: RubyTodo::Notebook.count,
    templates: RubyTodo::Template.count
  }
end

def print_counts(counts, prefix = "")
  puts "#{prefix}Tasks: #{counts[:tasks]}"
  puts "#{prefix}Notebooks: #{counts[:notebooks]}"
  puts "#{prefix}Templates: #{counts[:templates]}"
end

def reset_sqlite_sequences
  connection = ActiveRecord::Base.connection
  connection.tables.each do |table|
    connection.execute("DELETE FROM sqlite_sequence WHERE name='#{table}'")
    puts "Reset sequence counter for table: #{table}"
  end
end

begin
  # Get initial record counts
  initial_counts = count_records
  puts "\nCurrent record counts:"
  print_counts(initial_counts)

  puts "\nResetting database..."

  # Drop all tables
  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.drop_table(table)
    puts "Dropped table: #{table}"
  end

  # Recreate the database schema
  puts "\nRecreating database schema..."
  RubyTodo::Database.setup

  # Reset sequence counters
  puts "\nResetting sequence counters..."
  reset_sqlite_sequences

  # Verify the reset
  final_counts = count_records
  puts "\nFinal record counts:"
  print_counts(final_counts)

  puts "\nDatabase reset complete! All tables and sequence counters have been reset."
rescue ActiveRecord::ConnectionNotEstablished => e
  puts "\nError: Could not establish database connection"
  puts "Make sure the database directory exists at ~/.ruby_todo/"
  puts "Error details: #{e.message}"
  exit 1
rescue StandardError => e
  puts "\nAn error occurred while resetting the database:"
  puts e.message
  puts e.backtrace
  exit 1
end
