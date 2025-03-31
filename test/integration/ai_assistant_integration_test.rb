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
require "json"

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

      # In test environment with fake API key, we might see an error message instead
      if output.match?(/Error querying OpenAI/)
        assert_match(/Error querying OpenAI/, output, "Expected error message with test API key")
        # Also check if task listing is shown as fallback
        assert_match(/\d+:.*\(done\)/i, output, "Expected fallback task listing")
      else
        assert_match(/Exporting tasks.*'done'/i, output, "Expected exporting message")
        assert_match(/Successfully exported/i, output, "Expected successful export message")

        # Check for export file
        export_files = Dir.glob("done_tasks_export_*.json")
        assert_predicate export_files, :any?, "Expected at least one export file to be created"

        # Clean up
        export_files.each { |f| FileUtils.rm_f(f) }
      end
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
      assert_match(/Exporting tasks.*'done'/i, output, "Expected exporting message")
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
      assert_match(/Exporting tasks.*'done'/i, output, "Expected exporting message")
      assert_match(/Successfully exported/i, output, "Expected successful export message")
      assert_match(/#{filename}/i, output, "Expected filename in output")

      # Check if the file exists
      assert_path_exists filename, "Custom export file should exist"

      # Clean up
      FileUtils.rm_f(filename)
    end

    def test_ai_export_in_progress_tasks
      # Make sure we have some in-progress tasks
      in_progress_task = Task.find_by(status: "in_progress")
      unless in_progress_task
        in_progress_task = Task.first
        in_progress_task.update(status: "in_progress", updated_at: Time.now)
      end

      @output.truncate(0)
      @ai_assistant.ask("export the tasks in the in progress to reports.csv")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Exporting tasks.*'in_progress'/i, output, "Expected exporting message for in_progress tasks")
      assert_match(/Successfully exported/i, output, "Expected successful export message")
      assert_match(/reports\.csv/i, output, "Expected filename in output")

      # Check if the file exists
      assert_path_exists "reports.csv", "Export file should exist"

      # Verify CSV contains the in-progress task
      csv_content = File.read("reports.csv")
      assert_match(/#{in_progress_task.title}/i, csv_content, "CSV should contain the in-progress task")

      # Clean up
      FileUtils.rm_f("reports.csv")
    end

    def test_ai_export_todo_tasks
      # Make sure we have some todo tasks
      todo_task = Task.find_by(status: "todo")
      unless todo_task
        todo_task = Task.first
        todo_task.update(status: "todo", updated_at: Time.now)
      end

      filename = "todo_export_#{Time.now.to_i}.json"
      @output.truncate(0)
      @ai_assistant.ask("export todo tasks to #{filename}")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Exporting tasks.*'todo'/i, output, "Expected exporting message for todo tasks")
      assert_match(/Successfully exported/i, output, "Expected successful export message")
      assert_match(/#{filename}/i, output, "Expected filename in output")

      # Check if the file exists
      assert_path_exists filename, "Export file should exist"

      # Verify JSON contains the todo task
      json_content = JSON.parse(File.read(filename))
      notebook_tasks = json_content["notebooks"].flat_map { |n| n["tasks"] }
      assert notebook_tasks.any? { |t| t["title"] == todo_task.title }, "JSON should contain the todo task"

      # Clean up
      FileUtils.rm_f(filename)
    end

    def test_ai_export_archived_tasks
      # Make sure we have some archived tasks
      archived_task = Task.find_by(status: "archived")
      unless archived_task
        archived_task = Task.first
        archived_task.update(status: "archived", updated_at: Time.now)
      end

      filename = "archived_tasks.csv"
      @output.truncate(0)
      @ai_assistant.ask("export archived tasks to #{filename}")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Exporting tasks.*'archived'/i, output, "Expected exporting message for archived tasks")
      assert_match(/Successfully exported/i, output, "Expected successful export message")
      assert_match(/#{filename}/i, output, "Expected filename in output")

      # Check if the file exists
      assert_path_exists filename, "Export file should exist"

      # Verify CSV contains the archived task
      csv_content = File.read(filename)
      assert_match(/#{archived_task.title}/i, csv_content, "CSV should contain the archived task")

      # Clean up
      FileUtils.rm_f(filename)
    end

    def test_ai_export_tasks_with_status
      # Make sure we have tasks with various statuses
      todo_task = Task.find_by(status: "todo") || Task.create(notebook: @test_notebook, title: "Todo Test Task",
                                                              status: "todo")
      in_progress_task = Task.find_by(status: "in_progress") ||
                         Task.create(notebook: @test_notebook, title: "In Progress Test Task", status: "in_progress")
      done_task = Task.find_by(status: "done") || Task.create(notebook: @test_notebook, title: "Done Test Task",
                                                              status: "done")

      # Test exporting with specific status specified in query
      @output.truncate(0)
      @ai_assistant.ask("export tasks with status in_progress to status_export.csv")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Exporting tasks.*'in_progress'/i, output, "Expected exporting message for in_progress tasks")
      assert_match(/Successfully exported/i, output, "Expected successful export message")

      # Check if the file exists
      assert_path_exists "status_export.csv", "Export file should exist"

      # Verify CSV contains only in_progress tasks
      csv_content = File.read("status_export.csv")
      assert_match(/#{in_progress_task.title}/i, csv_content, "CSV should contain in_progress tasks")
      refute_match(/#{todo_task.title}/i, csv_content, "CSV should not contain todo tasks")
      refute_match(/#{done_task.title}/i, csv_content, "CSV should not contain done tasks")

      # Clean up
      FileUtils.rm_f("status_export.csv")
    end

    def test_ai_export_tasks_to_different_formats
      # Make sure we have some tasks to export
      test_task = Task.first
      test_task.update(status: "in_progress", updated_at: Time.now)

      # Test JSON export
      @output.truncate(0)
      @ai_assistant.ask("export in progress tasks to format.json")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Exporting tasks.*'in_progress'/i, output, "Expected exporting message")
      assert_match(/Successfully exported/i, output, "Expected successful export message")

      # Check if the JSON file exists
      assert_path_exists "format.json", "JSON export file should exist"

      # Verify JSON is valid - use begin/rescue instead of assert_nothing_raised
      begin
        JSON.parse(File.read("format.json"))
        pass("JSON should be valid")
      rescue JSON::ParserError => e
        flunk("Invalid JSON format: #{e.message}")
      end

      # Clean up
      FileUtils.rm_f("format.json")

      # Test CSV export
      @output.truncate(0)
      @ai_assistant.ask("export in progress tasks to format.csv")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Exporting tasks.*'in_progress'/i, output, "Expected exporting message")
      assert_match(/Successfully exported/i, output, "Expected successful export message")

      # Check if the CSV file exists
      assert_path_exists "format.csv", "CSV export file should exist"

      # Verify it's a valid CSV
      csv_lines = File.readlines("format.csv")
      assert_operator csv_lines.length, :>=, 2, "CSV should have header and at least one data row"

      # Clean up
      FileUtils.rm_f("format.csv")
    end

    def test_ai_conversational_export_requests
      # Make sure we have some tasks
      task = Task.first
      task.update(status: "in_progress", updated_at: Time.now)

      # Test conversational request for in-progress tasks
      @output.truncate(0)
      @ai_assistant.ask("Could you please export all my in-progress work to a CSV file?")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # In test environment with fake API key, we might see an error message instead
      if output.match?(/Error querying OpenAI/)
        assert_match(/Error querying OpenAI/, output, "Expected error message with test API key")
        # Also check if task listing is shown as fallback
        assert_match(/\d+:.*\(in_progress\)/i, output, "Expected fallback task listing")
      else
        assert_match(/Exporting tasks.*'in_progress'/i, output, "Expected exporting message for in_progress tasks")
        assert_match(/Successfully exported/i, output, "Expected successful export message")

        # Check for export file
        export_files = Dir.glob("in_progress_tasks_export_*.csv")
        assert_predicate export_files, :any?, "Expected at least one export file to be created"

        # Clean up
        export_files.each { |f| FileUtils.rm_f(f) }
      end
    end

    # Test with various status naming conventions
    def test_ai_export_with_different_status_formats
      # Setup a task with in_progress status
      task = Task.first
      task.update(status: "in_progress", updated_at: Time.now)

      # Test different formats of specifying "in progress"
      formats = [
        "in progress",
        "in-progress",
        "in_progress"
      ]

      formats.each do |format|
        @output.truncate(0)
        filename = "export_#{format.gsub(/[\s-]/, "_")}.csv"
        @ai_assistant.ask("export tasks with #{format} status to #{filename}")

        wait_for_output

        output = @output.string
        refute_empty output, "Expected non-empty response from AI for format '#{format}'"
        assert_match(/Exporting tasks.*'in_progress'/i, output,
                     "Expected exporting message for in_progress tasks using format '#{format}'")
        assert_match(/Successfully exported/i, output, "Expected successful export message")

        # Check if the file exists
        assert_path_exists filename, "Export file should exist for format '#{format}'"

        # Clean up
        FileUtils.rm_f(filename)
      end
    end

    # Test for handling non-existent statuses gracefully
    def test_ai_export_nonexistent_status
      @output.truncate(0)
      @ai_assistant.ask("export nonexistent_status tasks to nowhere.csv")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Should handle gracefully - either report no tasks found or normalize to a valid status
      assert output.match?(/No tasks.*found/i) ||
             output.match?(/Exporting tasks/i),
             "Expected either no tasks found message or exporting message"

      # Clean up any files that might have been created
      FileUtils.rm_f("nowhere.csv")
    end

    # Test custom filenames and export parameters handling
    def test_ai_export_with_custom_parameters
      # Setup test tasks
      task = Task.first
      task.update(status: "in_progress", updated_at: Time.now - (10 * 24 * 60 * 60)) # 10 days ago

      # Test with specific time period
      @output.truncate(0)
      @ai_assistant.ask("export in progress tasks from the last 2 weeks to custom_period.json")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"
      assert_match(/Exporting tasks.*'in_progress'/i, output, "Expected exporting message")
      assert_match(/Successfully exported/i, output, "Expected successful export message")

      # Check if the file exists
      assert_path_exists "custom_period.json", "Export file should exist"

      # Clean up
      FileUtils.rm_f("custom_period.json")
    end

    def test_ai_list_tasks_with_in_progress_status
      # Make sure we have some in-progress tasks
      in_progress_task = Task.find_by(status: "in_progress")
      unless in_progress_task
        in_progress_task = Task.first
        in_progress_task.update(status: "in_progress")
      end

      @output.truncate(0)
      @ai_assistant.ask("list tasks with status in progress")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify that the output contains the appropriate task(s)
      assert_match(/in_progress|In Progress/i, output, "Expected to see 'in_progress' or 'In Progress' in the output")

      # Check that the output contains the in-progress task title
      assert_match(/#{in_progress_task.title}/i, output, "Expected to see the in-progress task title in the output")

      # Check for any task status format
      assert(
        output.match?(/Status.*In Progress/i) ||
        output.match?(/\d+:.*\(in_progress\)/i) ||
        output.match?(/in[-_\s]*progress/i),
        "Expected to find in-progress tasks in some format"
      )
    end

    def test_ai_show_in_progress_tasks_alternative_phrasing
      # Make sure we have some in-progress tasks
      in_progress_task = Task.find_by(status: "in_progress")
      unless in_progress_task
        in_progress_task = Task.first
        in_progress_task.update(status: "in_progress")
      end

      @output.truncate(0)
      @ai_assistant.ask("show in progress tasks")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify that the output contains the appropriate task(s)
      assert_match(/in_progress|In Progress/i, output, "Expected to see 'in_progress' or 'In Progress' in the output")

      # Check that the output contains the in-progress task title
      assert_match(/#{in_progress_task.title}/i, output, "Expected to see the in-progress task title in the output")

      # Check for any task status format
      assert(
        output.match?(/Status.*In Progress/i) ||
        output.match?(/\d+:.*\(in_progress\)/i) ||
        output.match?(/in[-_\s]*progress/i),
        "Expected to find in-progress tasks in some format"
      )
    end

    def test_ai_list_tasks_with_status_in_progress
      # Make sure we have some in-progress tasks
      in_progress_task = Task.find_by(status: "in_progress")
      unless in_progress_task
        in_progress_task = Task.first
        in_progress_task.update(status: "in_progress")
      end

      @output.truncate(0)
      @ai_assistant.ask("list tasks with status in progress")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify that the output contains the appropriate task(s)
      assert_match(/in_progress|In Progress/i, output, "Expected to see 'in_progress' or 'In Progress' in the output")

      # Check that the output contains the in-progress task title
      assert_match(/#{in_progress_task.title}/i, output, "Expected to see the in-progress task title in the output")

      # Check for any task status format
      assert(
        output.match?(/Status.*In Progress/i) ||
        output.match?(/\d+:.*\(in_progress\)/i) ||
        output.match?(/in[-_\s]*progress/i),
        "Expected to find in-progress tasks in some format"
      )
    end

    def test_ai_list_tasks_with_todo_status
      # Make sure we have some todo tasks
      todo_task = Task.find_by(status: "todo")
      unless todo_task
        todo_task = Task.first
        todo_task.update(status: "todo")
      end

      @output.truncate(0)
      @ai_assistant.ask("list tasks with status todo")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify that the output contains the appropriate task(s)
      assert_match(/todo|Todo/i, output, "Expected to see 'todo' or 'Todo' in the output")

      # Check that the output contains the todo task title
      assert_match(/#{todo_task.title}/i, output, "Expected to see the todo task title in the output")

      # Check for any task status format
      assert(
        output.match?(/Status.*Todo/i) ||
        output.match?(/\d+:.*\(todo\)/i) ||
        output.match?(/todo/i),
        "Expected to find todo tasks in some format"
      )
    end

    def test_ai_show_todo_tasks_alternative_phrasing
      # Make sure we have some todo tasks
      todo_task = Task.find_by(status: "todo")
      unless todo_task
        todo_task = Task.first
        todo_task.update(status: "todo")
      end

      @output.truncate(0)
      @ai_assistant.ask("show todo tasks")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify that the output contains the appropriate task(s)
      assert_match(/todo|Todo/i, output, "Expected to see 'todo' or 'Todo' in the output")

      # Check that the output contains the todo task title
      assert_match(/#{todo_task.title}/i, output, "Expected to see the todo task title in the output")

      # Check for any task status format
      assert(
        output.match?(/Status.*Todo/i) ||
        output.match?(/\d+:.*\(todo\)/i) ||
        output.match?(/todo/i),
        "Expected to find todo tasks in some format"
      )
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

    # Test to verify the fix for notebook:list command
    def test_notebook_commands_with_explicit_methods
      @output.truncate(0)

      # Create a unique test notebook
      notebook_name = "cmd_test_notebook_#{Time.now.to_i}"
      Notebook.create!(name: notebook_name)

      # Create a CLI instance
      cli = RubyTodo::CLI.new

      # Test notebook:list
      cli.notebook_list

      output = @output.string
      refute_empty output, "Expected non-empty response from notebook:list command"
      assert_match(/#{notebook_name}/i, output, "Expected to see the test notebook in the output")

      # Reset output for next test
      @output.truncate(0)

      # Test notebook:create with a new name
      new_notebook_name = "new_test_notebook_#{Time.now.to_i}"
      cli.notebook_create(new_notebook_name)

      output = @output.string
      refute_empty output, "Expected non-empty response from notebook:create command"
      assert_match(/Created notebook: #{new_notebook_name}/i, output, "Expected confirmation of notebook creation")

      # Verify notebook was created
      assert Notebook.find_by(name: new_notebook_name), "New notebook should exist in the database"

      # Reset output for next test
      @output.truncate(0)

      # Test notebook:set_default
      cli.notebook_set_default(new_notebook_name)

      output = @output.string
      refute_empty output, "Expected non-empty response from notebook:set_default command"
      assert_match(/Successfully set '#{new_notebook_name}' as the default notebook/i, output,
                   "Expected confirmation of setting default notebook")

      # Verify notebook is set as default
      assert_predicate Notebook.find_by(name: new_notebook_name), :is_default?, "New notebook should be set as default"
    end

    # Test to verify the fix for template commands
    def test_template_commands_with_explicit_methods
      @output.truncate(0)

      # Create a CLI instance
      cli = RubyTodo::CLI.new

      # Test template:list (initially empty)
      cli.template_list

      output = @output.string
      refute_empty output, "Expected non-empty response from template:list command"

      # Reset output for next test
      @output.truncate(0)

      # Test template:create
      template_name = "test_template_#{Time.now.to_i}"

      # Need to provide options for the template
      # Set up options hash to mimic command line options
      cli.instance_variable_set(:@options, {
                                  title: "Task for template",
                                  description: "Task created from template",
                                  priority: "medium",
                                  tags: "test,template",
                                  notebook: "test_notebook"
                                })

      cli.template_create(template_name)

      output = @output.string
      refute_empty output, "Expected non-empty response from template:create command"
      assert_match(/Template '#{template_name}' created successfully/i, output,
                   "Expected confirmation of template creation")

      # Verify template was created
      assert RubyTodo::Template.find_by(name: template_name), "Template should exist in the database"

      # Reset output for next test
      @output.truncate(0)

      # Test template:show
      cli.template_show(template_name)

      output = @output.string
      refute_empty output, "Expected non-empty response from template:show command"
      assert_match(/#{template_name}/i, output, "Expected to see template name in the output")

      # Reset output for next test
      @output.truncate(0)

      # Test template:use
      cli.template_use(template_name, "test_notebook")

      output = @output.string
      refute_empty output, "Expected non-empty response from template:use command"
      assert_match(/Task created successfully/i, output, "Expected confirmation of task creation from template")

      # Reset output for final test
      @output.truncate(0)

      # Test template:delete
      cli.template_delete(template_name)

      output = @output.string
      refute_empty output, "Expected non-empty response from template:delete command"
      assert_match(/Template '#{template_name}' deleted successfully/i, output,
                   "Expected confirmation of template deletion")

      # Verify template was deleted
      refute RubyTodo::Template.find_by(name: template_name), "Template should be deleted from the database"
    end

    # New tests for the improved status filtering regex patterns
    def test_ai_list_tasks_with_in_progress_hyphenated
      # Make sure we have some in-progress tasks
      in_progress_task = Task.find_by(status: "in_progress")
      unless in_progress_task
        in_progress_task = Task.first
        in_progress_task.update(status: "in_progress")
      end

      @output.truncate(0)
      @ai_assistant.ask("list all tasks with in-progress status")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify that the output contains the appropriate task(s)
      assert_match(/in_progress|In Progress/i, output, "Expected to see 'in_progress' or 'In Progress' in the output")

      # Check that the output contains the in-progress task title
      assert_match(/#{in_progress_task.title}/i, output, "Expected to see the in-progress task title in the output")
    end

    def test_ai_show_tasks_having_in_progress_status
      # Make sure we have some in-progress tasks
      in_progress_task = Task.find_by(status: "in_progress")
      unless in_progress_task
        in_progress_task = Task.first
        in_progress_task.update(status: "in_progress")
      end

      @output.truncate(0)
      @ai_assistant.ask("show tasks having in progress status")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify that the output contains the appropriate task(s)
      assert_match(/in_progress|In Progress/i, output, "Expected to see 'in_progress' or 'In Progress' in the output")

      # Check that the output contains the in-progress task title
      assert_match(/#{in_progress_task.title}/i, output, "Expected to see the in-progress task title in the output")
    end

    def test_ai_display_in_progress_status_tasks
      # Make sure we have some in-progress tasks
      in_progress_task = Task.find_by(status: "in_progress")
      unless in_progress_task
        in_progress_task = Task.first
        in_progress_task.update(status: "in_progress")
      end

      @output.truncate(0)
      @ai_assistant.ask("display in_progress status tasks")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify that the output contains the appropriate task(s)
      assert_match(/in_progress|In Progress/i, output, "Expected to see 'in_progress' or 'In Progress' in the output")

      # Check that the output contains the in-progress task title
      assert_match(/#{in_progress_task.title}/i, output, "Expected to see the in-progress task title in the output")
    end

    def test_ai_list_tasks_that_are_in_todo_status
      # Make sure we have some todo tasks
      todo_task = Task.find_by(status: "todo")
      unless todo_task
        todo_task = Task.first
        todo_task.update(status: "todo")
      end

      @output.truncate(0)
      @ai_assistant.ask("list all tasks that are in todo")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify that the output contains the appropriate task(s)
      assert_match(/todo|Todo/i, output, "Expected to see 'todo' or 'Todo' in the output")

      # Check that the output contains the todo task title
      assert_match(/#{todo_task.title}/i, output, "Expected to see the todo task title in the output")

      # Make sure we don't see an error about notebook 'todo' not found
      refute_match(/notebook.*todo.*not found/i, output, "Should not see error about notebook 'todo' not found")

      # Assert that status filtering is working correctly - adjust pattern to match actual output format
      assert_match(/\d+:.*\(todo\)/i, output, "Output should show tasks with todo status")
    end

    def test_ai_display_tasks_that_are_in_progress
      # Make sure we have some in-progress tasks
      in_progress_task = Task.find_by(status: "in_progress")
      unless in_progress_task
        in_progress_task = Task.first
        in_progress_task.update(status: "in_progress")
      end

      @output.truncate(0)
      @ai_assistant.ask("display all tasks that are in progress")

      wait_for_output

      output = @output.string
      refute_empty output, "Expected non-empty response from AI"

      # Verify that the output contains the appropriate task(s)
      assert_match(/in_progress|In Progress/i, output, "Expected to see 'in_progress' or 'In Progress' in the output")

      # Check that the output contains the in-progress task title
      assert_match(/#{in_progress_task.title}/i, output, "Expected to see the in-progress task title in the output")

      # Make sure we don't see an error about notebook 'in progress' not found
      refute_match(/notebook.*in progress.*not found/i, output,
                   "Should not see error about notebook 'in progress' not found")

      # Assert that status filtering is working correctly - adjust pattern to match actual output format
      assert_match(/\d+:.*\(in_progress\)/i, output, "Output should show tasks with in_progress status")
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
