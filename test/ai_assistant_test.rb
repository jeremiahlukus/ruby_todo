# frozen_string_literal: true

require "test_helper"

class AIAssistantTest < Minitest::Test
  def setup
    # Setup test database
    RubyTodo::Database.setup
    
    # Create a test notebook
    @notebook = RubyTodo::Notebook.create(name: "Test Notebook")
    
    # Create some test tasks
    @task1 = RubyTodo::Task.create(
      notebook: @notebook,
      title: "Test Task 1", 
      description: "Task description",
      status: "todo",
      priority: "high",
      tags: "test,important"
    )
    
    @task2 = RubyTodo::Task.create(
      notebook: @notebook,
      title: "Test Task 2", 
      description: "Another task description",
      status: "in_progress",
      priority: "medium",
      tags: "test,documentation"
    )
    
    # Initialize AI command
    @ai_command = RubyTodo::AIAssistantCommand.new
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
    assert_includes context.keys, :notebooks
    assert_includes context.keys, :commands
    assert_includes context.keys, :app_version
    
    # Check notebooks data
    notebooks = context[:notebooks]
    assert_kind_of Array, notebooks
    assert_equal 1, notebooks.length
    
    notebook_data = notebooks.first
    assert_equal @notebook.id, notebook_data[:id]
    assert_equal "Test Notebook", notebook_data[:name]
    assert_equal 2, notebook_data[:task_count]
    assert_equal 1, notebook_data[:todo_count]
    assert_equal 1, notebook_data[:in_progress_count]
  end
  
  def test_parse_and_execute_actions
    # Mock JSON response
    json_response = {
      explanation: "Creating a new task",
      actions: [
        {
          type: "create_task",
          notebook: "Test Notebook",
          title: "New test task",
          description: "Task created from test",
          priority: "medium",
          tags: "test,mock"
        }
      ]
    }.to_json
    
    # Capture stdout to verify output
    out, _err = capture_io do
      @ai_command.send(:parse_and_execute_actions, json_response)
    end
    
    # Verify output
    assert_match(/Creating a new task/, out)
    assert_match(/Added task: New test task/, out)
    
    # Verify task was created
    task = RubyTodo::Task.find_by(title: "New test task")
    assert_equal "Task created from test", task.description
    assert_equal "medium", task.priority
    assert_equal "test,mock", task.tags
  end
  
  def test_parsing_invalid_json
    # Test with invalid JSON
    invalid_json = "This is not valid JSON"
    
    out, _err = capture_io do
      @ai_command.send(:parse_and_execute_actions, invalid_json)
    end
    
    # Verify error message
    assert_match(/Couldn't parse AI response/, out)
  end
  
  def test_move_task_action
    # Mock move task action
    json_response = {
      explanation: "Moving task to done",
      actions: [
        {
          type: "move_task",
          notebook: "Test Notebook",
          task_id: @task1.id,
          status: "done"
        }
      ]
    }.to_json
    
    # Capture stdout to verify output
    out, _err = capture_io do
      @ai_command.send(:parse_and_execute_actions, json_response)
    end
    
    # Verify output
    assert_match(/Moving task to done/, out)
    assert_match(/Moved task #{@task1.id} to done/, out)
    
    # Verify task was moved
    @task1.reload
    assert_equal "archived", @task1.status  # It should be archived due to the auto-archiving behavior
  end
end 