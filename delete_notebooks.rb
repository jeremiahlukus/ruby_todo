#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/ruby_todo"
require_relative "lib/ruby_todo/database"

# Setup the database connection
RubyTodo::Database.setup

# Count notebooks and tasks before deletion
notebook_count = RubyTodo::Notebook.count
task_count = RubyTodo::Task.count

# Delete tasks first to avoid foreign key constraint errors
RubyTodo::Task.delete_all
puts "Successfully deleted #{task_count} tasks."

# Then delete notebooks
RubyTodo::Notebook.delete_all
puts "Successfully deleted #{notebook_count} notebooks."

