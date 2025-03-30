# frozen_string_literal: true

require "test_helper"
require "minitest/pride" # For colored output
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

      @original_stdout = $stdout
      @output = StringIO.new
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
      @ai_assistant.ask("Hello, can you help me with task management?")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/task|help|manage/i, output)
    end

    def test_ai_task_creation_suggestion
      @output.truncate(0)
      @ai_assistant.ask("suggest a new task for my project with high priority")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      # The AI might either suggest a task directly or ask for more details
      assert(
        output.match?(/high.*priority|priority.*high/i) || output.match?(/details|provide|title|description/i),
        "Expected response to either mention high priority or ask for task details"
      )
    end

    def test_ai_task_listing
      @output.truncate(0)
      @ai_assistant.ask("show me all my tasks")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/task:list/i, output, "Expected response to include task listing")
      assert_match(/test_notebook/i, output, "Expected response to mention the notebook")
    end

    def test_ai_task_status_update
      @output.truncate(0)
      @ai_assistant.ask("mark my documentation task as done")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/task:move/i, output, "Expected response to include task movement")
      assert_match(/done/i, output, "Expected response to mention done status")
    end

    def test_ai_task_search
      @output.truncate(0)
      @ai_assistant.ask("find tasks related to documentation")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/task:search|task:list/i, output, "Expected response to include task search or list")
      assert_match(/documentation/i, output, "Expected response to mention documentation")
    end

    def test_ai_notebook_listing
      @output.truncate(0)
      @ai_assistant.ask("list all notebooks")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/ID|Name|Tasks|Created At|Default/i, output, "Expected notebook listing table headers")
      assert_match(/test_notebook/i, output, "Expected to see test notebook in the output")
    end

    def test_ai_create_notebook
      @output.truncate(0)
      notebook_name = "ai_test_notebook_#{Time.now.to_i}"
      @ai_assistant.ask("create a new notebook called #{notebook_name}")
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
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/ID|Title|Status|Priority|Due Date|Tags|Description/i, output, "Expected task listing table headers")
      assert_match(/documentation/i, output, "Expected to see documentation task in the output")
      assert_match(/github/i, output, "Expected to see github task in the output")
    end

    def test_ai_export_done_tasks
      # First, mark a task as done
      task = Task.first
      task.update(status: "done", updated_at: Time.now)

      @output.truncate(0)
      @ai_assistant.ask("export all the tasks with the done status from the last two weeks")
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
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Total:|Task Counts:|Priority:/i, output, "Expected response to include statistics information")
    end

    def test_ai_batch_task_update_by_tag
      @output.truncate(0)
      @ai_assistant.ask("move all tasks tagged with migration to in progress")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/task:move/i, output, "Expected response to include task movement")
      assert_match(/in[_ ]progress/i, output, "Expected response to mention in_progress status")
      assert_match(/migration/i, output, "Expected response to mention migration tag")
    end

    def test_ai_batch_task_update_by_keyword
      @output.truncate(0)
      @ai_assistant.ask("move all github tasks to in progress")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/task:move/i, output, "Expected response to include task movement")
      assert_match(/in[_ ]progress/i, output, "Expected response to mention in_progress status")
      assert_match(/github/i, output, "Expected response to mention github")
    end

    def test_ai_multiple_specific_task_update
      @output.truncate(0)
      @ai_assistant.ask("move the documentation task and the github migration task to in progress")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/task:move/i, output, "Expected response to include task movement")
      assert_match(/in[_ ]progress/i, output, "Expected response to mention in_progress status")
      assert_match(/documentation.*github|github.*documentation/i, output, "Expected response to mention both tasks")
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
      error = assert_raises(Faraday::UnauthorizedError, "Expected unauthorized error for invalid API key") do
        invalid_ai.ask("Hello")
      end
      assert_match(/401/, error.message.to_s)
    end

    def test_ai_nonexistent_notebook
      @output.truncate(0)
      @ai_assistant.ask("show tasks in nonexistent_notebook")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/does not exist|check the notebook name/i, output,
                   "Expected error message about nonexistent notebook")
    end

    def test_ai_invalid_task_id
      @output.truncate(0)
      @ai_assistant.ask("mark task 999999 as done")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/does not exist|valid task ID/i, output, "Expected error message about invalid task ID")
    end

    def test_ai_invalid_status
      @output.truncate(0)
      @ai_assistant.ask("move task 1 to invalid_status")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/not a recognized status|valid status/i, output, "Expected error message about invalid status")
    end

    def test_ai_task_with_invalid_attributes
      @output.truncate(0)
      @ai_assistant.ask("add task 'Test Task' to test_notebook with invalid_priority xyz")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # The task should still be created, but without the invalid attributes
      assert_match(/Added task: Test Task/i, output, "Expected task to be created despite invalid attributes")

      # Verify the task exists but doesn't have the invalid priority
      task = Task.find_by(title: "Test Task")
      assert task, "Task should still be created"
      refute_equal "invalid_priority", task.priority, "Invalid priority should not be set"
    end

    def test_ai_export_with_no_done_tasks
      # Make sure there are no done tasks
      Task.update_all(status: "todo")

      @output.truncate(0)
      @ai_assistant.ask("export done tasks from the last week")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/No 'done' tasks found/i, output, "Expected message about no done tasks")
    end

    def test_ai_ambiguous_notebook_reference
      # Create two notebooks with similar names
      Notebook.create(name: "work")
      Notebook.create(name: "work_personal")

      @output.truncate(0)
      @ai_assistant.ask("list tasks in work")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Should match one of the notebooks exactly
      assert_match(/ID|Title|Status|Priority/i, output, "Expected task listing header")
    end

    def test_ai_complex_task_creation_with_natural_language
      @output.truncate(0)
      @ai_assistant.ask("I need to create a new task called 'Call the client about project requirements' in my test_notebook. It should be high priority and due tomorrow with a tag 'client'.")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Check if task was created
      task = Task.find_by(title: "Call the client about project requirements")
      assert task, "Task should be created from natural language request"
    end

    def test_ai_conversational_request_for_notebook_contents
      @output.truncate(0)
      @ai_assistant.ask("Can you please show me what's in my test notebook?")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/ID|Title|Status|Priority|Due Date|Tags|Description/i, output, "Expected task listing table headers")
      assert_match(/documentation|github/i, output, "Expected to see task titles in the output")
    end

    def test_ai_date_based_export_request
      # First, mark a task as done
      task = Task.first
      task.update(status: "done", updated_at: Time.now)

      @output.truncate(0)
      @ai_assistant.ask("I'd like to get all the tasks I've finished in the past 14 days and save them to a file")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Exporting tasks marked as 'done'/i, output, "Expected exporting message")
      assert_match(/Successfully exported/i, output, "Expected successful export message")

      # Clean up
      export_files = Dir.glob("done_tasks_export_*.json")
      export_files.each { |f| FileUtils.rm_f(f) }
    end

    def test_ai_task_movement_with_natural_language
      task = Task.first
      initial_status = task.status
      new_status = initial_status == "done" ? "in_progress" : "done"

      @output.truncate(0)
      @ai_assistant.ask("Please change the status of the task about documentation to #{new_status}")
      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify task status was updated
      task.reload
      assert_equal new_status, task.status, "Task status should be updated to #{new_status}"
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
  end
end
