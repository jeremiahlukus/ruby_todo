# frozen_string_literal: true

require_relative "../test_helper"
require "minitest/autorun"
require "ruby_todo"
require "ruby_todo/cli"
require "ruby_todo/commands/ai_assistant"
require "stringio"

module RubyTodo
  # Simple test CLI class to avoid mocking
  class TestCLI
    attr_accessor :options

    def initialize
      @options = {}
    end

    def task_list(notebook_name)
      # Just a stub for testing
    end
  end

  # Test class specifically for pattern matching without requiring API keys
  class StatusFilteringTest < Minitest::Test
    def setup
      super
      # Use the test database setup from test_helper
      # The test helper already handles database setup/teardown

      # Create test notebook
      @test_notebook = RubyTodo::Notebook.create(name: "test_pattern_notebook", is_default: true)

      # Create AI assistant instance
      @ai_assistant = RubyTodo::AIAssistantCommand.new
    end

    # Direct regex pattern tests that don't require OpenAI API
    def test_status_filtering_patterns
      # Test different in-progress status filtering patterns
      patterns_to_test = [
        "list all tasks with in progress status",
        "list all tasks with in-progress status",
        "display in_progress status tasks",
        "show tasks having in progress status",
        "list tasks with status in_progress",
        "show in progress tasks"
      ]

      # For each pattern, verify that our regex patterns match it
      patterns_to_test.each do |pattern|
        # Test with tasks_with_status_regex
        if pattern.match?(@ai_assistant.send(:tasks_with_status_regex))
          status_match = pattern.match(@ai_assistant.send(:tasks_with_status_regex))
          assert_match(/in[\s_-]?progress/i, status_match[1],
                       "Pattern '#{pattern}' should match in-progress status with tasks_with_status_regex")
        # Test with tasks_by_status_regex
        elsif pattern.match?(@ai_assistant.send(:tasks_by_status_regex))
          status_match = pattern.match(@ai_assistant.send(:tasks_by_status_regex))
          assert_match(/in[\s_-]?progress/i, status_match[1],
                       "Pattern '#{pattern}' should match in-progress status with tasks_by_status_regex")
        # Test with status_prefix_tasks_regex
        elsif pattern.match?(@ai_assistant.send(:status_prefix_tasks_regex))
          status_match = pattern.match(@ai_assistant.send(:status_prefix_tasks_regex))
          assert_match(/in[\s_-]?progress/i, status_match[1],
                       "Pattern '#{pattern}' should match in-progress status with status_prefix_tasks_regex")
        else
          flunk "Pattern '#{pattern}' did not match any of the status filtering regex patterns"
        end
      end
    end

    # Test status normalization
    def test_status_text_normalization
      # Create test CLI object
      test_cli = TestCLI.new

      # Test different status text variations
      status_variations = {
        "in progress" => "in_progress",
        "in-progress" => "in_progress",
        "in_progress" => "in_progress",
        "inprogress" => "in_progress",
        "IN PROGRESS" => "in_progress",
        "In-Progress" => "in_progress"
      }

      status_variations.each do |input, expected|
        # Call the method directly
        @ai_assistant.send(:handle_filtered_tasks, test_cli, input)

        # Check that status was normalized correctly
        assert_equal({ status: expected }, test_cli.options,
                     "Status '#{input}' should be normalized to '#{expected}'")
      end
    end

    # Test that status filtering regex works with more complex phrases
    def test_complex_status_filtering_phrases
      complex_phrases = [
        "please list all tasks with in progress status",
        "can you show me in-progress tasks?",
        "I need to see all tasks that are in progress",
        "display tasks having in_progress status now",
        "list all the tasks with status in-progress please"
      ]

      complex_phrases.each do |phrase|
        assert(
          phrase.match?(@ai_assistant.send(:tasks_with_status_regex)) ||
          phrase.match?(@ai_assistant.send(:tasks_by_status_regex)) ||
          phrase.match?(@ai_assistant.send(:status_prefix_tasks_regex)),
          "Complex phrase '#{phrase}' should match at least one status filtering regex pattern"
        )
      end
    end

    # Test that handle_status_filtering properly handles all variations
    def test_handle_status_filtering
      # Create test CLI object
      test_cli = TestCLI.new

      # Test different status filtering commands
      commands_to_test = [
        "list all tasks with in progress status",
        "show in-progress tasks",
        "display tasks with status in_progress"
      ]

      commands_to_test.each do |command|
        # Reset options before each test
        test_cli.options = {}

        # Call the method directly
        result = @ai_assistant.send(:handle_status_filtering, command, test_cli)

        # Verify it was handled successfully
        assert result, "Command '#{command}' should be handled by handle_status_filtering"

        # Check that status was set to in_progress
        assert_equal({ status: "in_progress" }, test_cli.options,
                     "Command '#{command}' should set status to in_progress")
      end
    end
  end
end
