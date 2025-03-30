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
      $stdout = @original_stdout
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
