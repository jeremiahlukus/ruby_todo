#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/ruby_todo"

# Create notebooks and tasks
puts "Creating test notebooks and tasks..."
notebook = RubyTodo::Notebook.create(name: "Test Notebook")
notebook.update!(is_default: true)

notebook.tasks.create(
  title: "Migrate to the barracua org",
  status: "todo",
  description: "Migration task for repository"
)

notebook.tasks.create(
  title: "Task 2",
  status: "todo"
)

notebook.tasks.create(
  title: "Regular task not related to migrations",
  status: "in_progress"
)

# Create the AI Assistant
ai_command = RubyTodo::AIAssistantCommand.new([], { verbose: true })

# Test the problematic case
puts "\n\n=== Testing problematic case ==="
prompt = "move all migrate to the barracua org tasks to in porgress"

puts "Running test with prompt: '#{prompt}'"
context = {}

ai_command.send(:handle_task_request, prompt, context)

# Display results
puts "\n=== Results ==="
if context[:matching_tasks]&.any?
  puts "Found #{context[:matching_tasks].size} matching tasks:"
  context[:matching_tasks].each do |task|
    puts "- #{task[:title]} (ID: #{task[:task_id]}, Notebook: #{task[:notebook]})"
  end
  puts "Target status: #{context[:target_status]}"
else
  puts "No matching tasks found"
end

# Clean up
puts "\n=== Cleaning up ==="
RubyTodo::Task.delete_all
RubyTodo::Notebook.delete_all
puts "Test completed"
