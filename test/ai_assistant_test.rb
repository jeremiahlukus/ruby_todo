# frozen_string_literal: true

require "test_helper"

class AIAssistantTest < Minitest::Test
  def setup
    super
    @notebook = RubyTodo::Notebook.create(name: "Test Notebook")
    @task1 = @notebook.tasks.create(title: "Test Task 1", status: "todo")
    @ai_command = RubyTodo::AIAssistantCommand.new([], { verbose: true })
  end

  def teardown
    # Clean up test database
    RubyTodo::Task.delete_all
    RubyTodo::Notebook.delete_all
  end

  def test_build_context
    # Use send to access private method
    context = @ai_command.send(:build_context)

    assert_kind_of Hash, context
    assert_includes context.keys, :matching_tasks
    assert_kind_of Array, context[:matching_tasks]
  end

  def test_handle_response
    # Mock JSON response with a simpler command
    json_response = {
      "command" => "ruby_todo notebook:list",
      "explanation" => "Listing all notebooks"
    }

    # Capture stdout to verify output
    out, _err = capture_io do
      @ai_command.send(:handle_response, json_response)
    end

    # Verify output
    assert_match(/Listing all notebooks/, out)
    assert_match(/Executing command:/, out)
  end

  def test_handle_invalid_response
    # Test with invalid response
    invalid_response = nil

    out, _err = capture_io do
      @ai_command.send(:handle_response, invalid_response)
    end

    # Verify no output for nil response
    assert_empty out
  end

  def test_handle_task_movement
    # Test task movement
    prompt = "move task about Test Task 1 to done"
    context = { matching_tasks: [
      {
        notebook: @notebook.name,
        task_id: @task1.id,
        title: @task1.title,
        status: @task1.status
      }
    ] }

    # Capture stdout to verify output
    out, _err = capture_io do
      @ai_command.send(:handle_task_request, prompt, context)
    end

    # Verify task was found and moved
    assert_match(/Found 1 task/, out)
    assert_match(/Successfully moved task/, out)

    # Verify task status was updated (tasks marked as done are automatically archived)
    @task1.reload
    assert_equal "archived", @task1.status
  end
end
