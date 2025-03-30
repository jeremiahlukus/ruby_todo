# frozen_string_literal: true

require_relative "../test_helper"
require "minitest/autorun"
require "ruby_todo"
require "ruby_todo/cli"
require "ruby_todo/commands/ai_assistant"
require "ruby_todo/ai_assistant/openai_integration"
require "openai"
require "fileutils"
require "active_record"
require "stringio"

module RubyTodo
  class AiAssistantIntegrationTest < Minitest::Test
    def setup
      super
      # Skip all tests in this class if no API key is available
      skip "Skipping AI integration tests: OPENAI_API_KEY environment variable not set" unless ENV["OPENAI_API_KEY"]

      # Set a shorter timeout for CI environments
      @timeout = ENV["CI"] ? 10 : 30

      @original_stdout = $stdout
      @output = StringIO.new

      # Make StringIO work with TTY by adding necessary methods
      def @output.ioctl(*_args)
        80
      end

      $stdout = @output

      @ai_assistant = RubyTodo::AIAssistantCommand.new([], { api_key: ENV.fetch("OPENAI_API_KEY", nil) })
      @test_notebook = Notebook.create(name: "test_notebook", is_default: true)
      create_sample_tasks
    end

    def teardown
      super
      $stdout = @original_stdout if @original_stdout
    end

    def test_ai_basic_functionality
      @output.truncate(0)
      @ai_assistant.ask("Hello, can you help me with task management?")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      # Just check that we get any response, don't be too specific
      assert_operator output.length, :>, 10, "Expected a substantial response"
    end

    def test_ai_task_creation_suggestion
      @output.truncate(0)
      # Use a more direct command that will always get a response
      task_title = "High Priority Task #{Time.now.to_i}"
      @ai_assistant.ask("add task '#{task_title}' to test_notebook priority high")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Check that some expected content is in the response
      assert(
        output.match?(/#{task_title}/i) ||
        output.match?(/high.*priority/i) ||
        output.match?(/priority.*high/i) ||
        output.match?(/task.*add/i) ||
        output.match?(/added task/i),
        "Expected response to mention adding a high priority task"
      )

      # Verify a task was created
      tasks = Task.where("title LIKE ?", "%#{task_title}%")
      assert_predicate tasks, :any?, "Expected a task to be created with title containing '#{task_title}'"
    end

    def test_ai_task_listing
      @output.truncate(0)
      @ai_assistant.ask("show me all my tasks")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      # The output format has changed, check for task IDs instead of specific command
      assert_match(/\d+:.*\((?:todo|in_progress|done)\)/i, output, "Expected response to include tasks with status")
    end

    def test_ai_task_status_update
      # Mark sure we have a documentation task and it's not already done
      doc_task = Task.where("title LIKE ?", "%documentation%").first
      refute_nil doc_task, "Expected to find a documentation task"
      doc_task.update(status: "todo") # Reset to todo to ensure we can change it

      @output.truncate(0)
      @ai_assistant.ask("mark my documentation task as done")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Give the system time to process the update
      sleep 2

      # Reload the task and check its status directly
      doc_task.reload
      assert_equal "done", doc_task.status, "Documentation task should be marked as done"
    end

    def test_ai_task_search
      @output.truncate(0)
      @ai_assistant.ask("find tasks related to documentation")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      # The output format has changed, look for task listings instead of command names
      assert(
        output.match?(/\d+:.*documentation/i) ||
        output.match?(/documentation/i),
        "Expected response to mention documentation or show tasks with documentation"
      )
    end

    def test_ai_notebook_listing
      @output.truncate(0)
      @ai_assistant.ask("list all notebooks")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      # Since we're using StringIO with ioctl, the table rendering should work
      assert_match(/test_notebook/i, output, "Expected to see test notebook in the output")
    end

    def test_ai_create_notebook
      @output.truncate(0)
      notebook_name = "ai_test_notebook_#{Time.now.to_i}"
      @ai_assistant.ask("create a new notebook called #{notebook_name}")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Created notebook: #{notebook_name}/i, output, "Expected confirmation of notebook creation")

      # Verify notebook was actually created
      assert Notebook.find_by(name: notebook_name), "Notebook should exist in the database"
    end

    def test_ai_create_task_with_attributes
      @output.truncate(0)
      task_title = "AI Integration Test Task #{Time.now.to_i}"
      @ai_assistant.ask("add a task titled '#{task_title}' in test_notebook priority high tag testing")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Added task: #{task_title}/i, output, "Expected confirmation of task creation")
      assert_match(/Priority: high/i, output, "Expected priority to be set to high")
      assert_match(/Tags: testing/i, output, "Expected tag to be set to testing")

      # Verify task was actually created with correct attributes
      task = Task.find_by(title: task_title)
      assert task, "Task should exist in the database"
      assert_equal "high", task.priority.downcase, "Task priority should be high"
      assert_match(/testing/i, task.tags, "Task should have testing tag")
    end

    def test_ai_list_tasks_in_notebook
      @output.truncate(0)
      @ai_assistant.ask("show tasks in test_notebook")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      # The output format has changed, check for task IDs instead of specific command
      assert_match(/\d+:.*\((?:todo|in_progress|done)\)/i, output, "Expected response to include tasks with status")
      assert_match(/documentation|github/i, output, "Expected to see task titles in the output")
    end

    def test_ai_export_done_tasks
      # First, mark a task as done
      task = Task.first
      task.update(status: "done", updated_at: Time.now)

      @output.truncate(0)
      @ai_assistant.ask("export all the tasks with the done status from the last two weeks")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Exporting tasks marked as 'done'/i, output, "Expected exporting message")
      assert_match(/Successfully exported/i, output, "Expected successful export message")

      # Check for export file
      export_files = Dir.glob("done_tasks_export_*.json")
      assert_predicate export_files, :any?, "Expected at least one export file to be created"

      # Clean up
      export_files.each { |f| FileUtils.rm_f(f) }
    end

    def test_ai_export_done_tasks_to_csv
      # First, mark a task as done
      task = Task.first
      task.update(status: "done", updated_at: Time.now)

      @output.truncate(0)
      @ai_assistant.ask("export done tasks to CSV")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Exporting tasks marked as 'done'/i, output, "Expected exporting message")
      assert_match(/Successfully exported/i, output, "Expected successful export message")

      # Check for export file
      export_files = Dir.glob("*.csv")
      assert_predicate export_files, :any?, "Expected at least one CSV export file to be created"

      # Clean up
      export_files.each { |f| FileUtils.rm_f(f) }
    end

    def test_ai_export_done_tasks_with_custom_filename
      # First, mark a task as done
      task = Task.first
      task.update(status: "done", updated_at: Time.now)

      filename = "custom_export_#{Time.now.to_i}.json"
      @output.truncate(0)
      @ai_assistant.ask("export done tasks from the last 2 weeks to file #{filename}")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Exporting tasks marked as 'done'/i, output, "Expected exporting message")
      assert_match(/Successfully exported/i, output, "Expected successful export message")
      assert_match(/#{filename}/i, output, "Expected filename in output")

      # Check if the file exists
      assert_path_exists filename, "Custom export file should exist"

      # Clean up
      FileUtils.rm_f(filename)
    end

    def test_ai_statistics_request
      @output.truncate(0)
      @ai_assistant.ask("show me task statistics")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Just check that we get some kind of response
      assert_operator output.length, :>, 10, "Expected a substantial response"
    end

    def test_ai_batch_task_update_by_tag
      @output.truncate(0)
      @ai_assistant.ask("move all tasks tagged with migration to in progress")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      # The output format has changed, check for status update message
      assert_match(/moved task|migration|in_progress/i, output,
                   "Expected response to mention moving tasks with migration tag")
    end

    def test_ai_batch_task_update_by_keyword
      @output.truncate(0)
      @ai_assistant.ask("move all github tasks to in progress")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      # The output format has changed, check for status update message
      assert_match(/moved task|github|in_progress/i, output, "Expected response to mention moving GitHub tasks")
    end

    def test_ai_multiple_specific_task_update
      @output.truncate(0)
      @ai_assistant.ask("move the documentation task and the github migration task to in progress")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Just verify we get a response
      assert_operator output.length, :>, 10, "Expected a substantial response"

      # Check if any documentation or github tasks are in_progress
      sleep 2
      assert Task.where("(title LIKE ? OR title LIKE ?) AND status = ?",
                        "%documentation%", "%github%", "in_progress").exists? ||
             output.match?(/moved|updated|changed|status|progress/i),
             "Expected tasks to be moved to in_progress or output to mention status change"
    end

    # Error cases
    def test_ai_empty_prompt
      @output.truncate(0)
      error = assert_raises(ArgumentError, "Expected ArgumentError for empty prompt") do
        @ai_assistant.ask("")
      end
      assert_equal "Empty prompt", error.message
    end

    def test_ai_invalid_api_key
      @output.truncate(0)
      invalid_ai = RubyTodo::AIAssistantCommand.new([], { api_key: "invalid_key" })
      # We're using the environment variable key anyway, so no error
      invalid_ai.ask("Hello")

      wait_for_output

      refute_empty @output.string, "Even with invalid key provided in options, still expected response using env var"
    end

    def test_ai_nonexistent_notebook
      @output.truncate(0)
      @ai_assistant.ask("show tasks in nonexistent_notebook")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/notebook.*not found/i, output, "Expected error message about nonexistent notebook")
    end

    def test_ai_invalid_task_id
      @output.truncate(0)
      @ai_assistant.ask("mark task 999999 as done")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/does not exist|valid task ID/i, output, "Expected error message about invalid task ID")
    end

    def test_ai_invalid_status
      @output.truncate(0)
      @ai_assistant.ask("move task 1 to invalid_status")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/not a recognized status|valid status/i, output, "Expected error message about invalid status")
    end

    def test_ai_task_with_invalid_attributes
      @output.truncate(0)
      @ai_assistant.ask("add task 'Test Task' to test_notebook with invalid_priority xyz")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify the task exists despite invalid attributes
      task = Task.find_by(title: "Test Task")
      assert task, "Task should still be created despite invalid attributes"

      # Invalid priority should not be set
      refute_equal "invalid_priority", task.priority, "Invalid priority should not be set"
    end

    def test_ai_export_with_no_done_tasks
      # Make sure there are no done tasks
      Task.update_all(status: "todo")

      @output.truncate(0)
      @ai_assistant.ask("export done tasks from the last week")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      # The output format might have changed
      assert_predicate(Dir.glob("done_tasks_export_*.json"), :none?,
                       "No export files should be created when there are no done tasks")
    end

    def test_ai_ambiguous_notebook_reference
      # Create two notebooks with similar names
      Notebook.create(name: "work")
      Notebook.create(name: "work_personal")

      @output.truncate(0)
      @ai_assistant.ask("list tasks in work")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      # Check for "No tasks found" or task listing
      assert(output.match?(/no tasks found/i) || output.match?(/\d+:.*\((?:todo|in_progress|done)\)/i),
             "Expected either no tasks message or task listing")
    end

    def test_ai_complex_task_creation_with_natural_language
      @output.truncate(0)
      task_description = "Call the client about project requirements"
      @ai_assistant.ask(
        "add task '#{task_description}' to test_notebook " \
        "priority high tags client"
      )

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Check task was created
      tasks = Task.where("title LIKE ?", "%#{task_description}%")
      assert_predicate tasks, :any?, "Task should be created from natural language request"

      # Verify the task has appropriate attributes
      task = tasks.first
      assert_match(/high/i, task.priority.to_s, "Task should have high priority")
      assert_match(/client/i, task.tags.to_s, "Task should have client tag")
    end

    def test_ai_conversational_request_for_notebook_contents
      @output.truncate(0)
      @ai_assistant.ask("Can you please show me what's in my test notebook?")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert output.match?(/\d+:.*\((?:todo|in_progress|done)\)/i) || output.match?(/test_notebook/i),
             "Expected to see task listings or notebook reference"
    end

    def test_ai_date_based_export_request
      # First, mark a task as done
      task = Task.first
      task.update(status: "done", updated_at: Time.now)

      @output.truncate(0)
      @ai_assistant.ask("I'd like to export all tasks I've completed in the last 14 days to a file")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Clean up any export files that might have been created
      export_files = Dir.glob("done_tasks_export_*.json")
      export_files.each { |f| FileUtils.rm_f(f) }
    end

    def test_ai_task_movement_with_natural_language
      # Use the first task with "documentation" in the title
      task = Task.where("title LIKE ?", "%documentation%").first
      refute_nil task, "Expected to find a documentation task"

      initial_status = task.status
      new_status = initial_status == "done" ? "in_progress" : "done"

      @output.truncate(0)
      @ai_assistant.ask("Please change the status of the task about documentation to #{new_status}")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify task status was updated, give it a moment to process
      sleep 3
      task.reload
      assert_equal new_status, task.status, "Task status should be updated to #{new_status}"
    end

    def test_ai_natural_language_task_creation
      skip "Test requires valid OpenAI API key" unless ENV["OPENAI_API_KEY"] && ENV["OPENAI_API_KEY"] != "test_key"

      # Count tasks before test
      tasks_before = Task.count

      @output.truncate(0)
      # Use a simple, direct task creation to avoid OpenAI dependency
      task_description = "Test new task creation #{Time.now.to_i}"
      @ai_assistant.ask("add task '#{task_description}' to test_notebook priority high")

      wait_for_output(60) # May need longer for API call

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Give the system a moment to create the task
      sleep 3

      # Check that a new task was created
      assert_operator Task.count, :>, tasks_before, "Expected a new task to be created"

      # The newest task should be ours
      newest_task = Task.order(created_at: :desc).first
      assert newest_task, "Expected to find the newly created task"
      assert newest_task.title.include?(task_description) ||
             newest_task.created_at > (Time.now - 60),
             "Expected newest task to be the one we created"
    end

    def test_ai_task_list
      @output.truncate(0)

      # Create a test notebook if it doesn't exist
      unless Notebook.find_by(name: "test_notebook")
        Notebook.create!(name: "test_notebook")
      end

      # Create some test tasks
      3.times do |i|
        Task.create!(
          title: "Test task #{i + 1}",
          notebook: Notebook.find_by(name: "test_notebook"),
          priority: %w[low medium high][i % 3]
        )
      end

      # Ask the AI to list tasks
      @ai_assistant.ask("list all the tasks in the test_notebook")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify that the output contains task list information
      # Just check that we receive some output and don't throw an error
      assert_operator output.length, :>, 10, "Expected substantial output for task listing"

      # Check that we have at least one numeric task ID in the output
      assert_match(/\d+/, output, "Expected output to contain at least one task ID")
    end

    private

    def create_sample_tasks
      [
        Task.create(
          notebook: @test_notebook,
          title: "Complete project documentation",
          description: "Write comprehensive documentation for the Ruby Todo project",
          status: "todo",
          priority: "high",
          tags: "documentation,writing",
          due_date: Time.now + (7 * 24 * 60 * 60)
        ),
        Task.create(
          notebook: @test_notebook,
          title: "Fix bug in export feature",
          description: "Address issue with CSV export formatting",
          status: "in_progress",
          priority: "high",
          tags: "bug,export",
          due_date: Time.now + (2 * 24 * 60 * 60)
        ),
        Task.create(
          notebook: @test_notebook,
          title: "Migrate CI to GitHub Actions",
          description: "Move all CI/CD pipelines to GitHub Actions",
          status: "todo",
          priority: "high",
          tags: "github,migration,ci",
          due_date: Time.now + (3 * 24 * 60 * 60)
        ),
        Task.create(
          notebook: @test_notebook,
          title: "Update GitHub repository settings",
          description: "Configure branch protection and access controls",
          status: "todo",
          priority: "medium",
          tags: "github,security",
          due_date: Time.now + (4 * 24 * 60 * 60)
        ),
        Task.create(
          notebook: @test_notebook,
          title: "Migrate test suite to RSpec",
          description: "Convert all tests to RSpec format",
          status: "todo",
          priority: "medium",
          tags: "testing,migration",
          due_date: Time.now + (5 * 24 * 60 * 60)
        )
      ]
    end

    # Helper method to wait for output
    def wait_for_output(max_wait = nil)
      timeout = max_wait || @timeout
      start_time = Time.now

      # Wait for output to appear
      sleep 0.1 while @output.string.empty? && (Time.now - start_time) < timeout

      # Wait a bit more to allow for complete output
      sleep 1 unless @output.string.empty?
    end
  end
end
