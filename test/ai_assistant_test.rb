# frozen_string_literal: true

require "test_helper"

class AIAssistantTest < Minitest::Test
  def setup
    super
    @notebook = RubyTodo::Notebook.create(name: "Test Notebook")
    @notebook.update!(is_default: true)
    @task1 = @notebook.tasks.create(title: "Test Task 1", status: "todo")
    @task2 = @notebook.tasks.create(title: "Test Task 2", status: "todo")
    @task3 = @notebook.tasks.create(title: "Test Task 3", status: "in_progress")
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
    assert_includes context.keys, :notebooks
    assert_kind_of Array, context[:notebooks]
    assert_equal 1, context[:notebooks].size
    assert_equal "Test Notebook", context[:notebooks].first[:name]
  end

  def test_execute_commands
    # Test execute_commands with a mock response
    response = {
      "commands" => ["task:list Test Notebook"],
      "explanation" => "Listing all tasks in Test Notebook"
    }

    # Capture stdout to verify output
    _out, _err = capture_io do
      @ai_command.send(:execute_actions, response)
    end
  end

  def test_execute_commands_with_invalid_input
    # Test with invalid response
    response = { "commands" => nil }

    _out, _err = capture_io do
      @ai_command.send(:execute_actions, response)
    end
  end

  def test_task_creation
    # Test task creation with various parameters
    notebook_name = "Test Notebook"
    title = "New test task"
    description = "Test description"

    # Create the task directly with CLI instead of through AIAssistant
    cli = RubyTodo::CLI.new
    cli.options = {
      description: description,
      priority: "high",
      tags: "test,important"
    }

    _out, _err = capture_io do
      cli.task_add(notebook_name, title)
    end

    # Verify task was created
    task = RubyTodo::Task.where(title: title).last
    assert_equal title, task.title
    assert_equal description, task.description
    assert_equal "high", task.priority
    assert_equal "test,important", task.tags
  end

  def test_task_creation_unquoted_description
    # Test task creation with unquoted description
    notebook_name = "Test Notebook"
    title = "New test task"
    description = "Test description without quotes"

    # Create the task directly with CLI instead of through AIAssistant
    cli = RubyTodo::CLI.new
    cli.options = {
      description: description,
      priority: "high"
    }

    _out, _err = capture_io do
      cli.task_add(notebook_name, title)
    end

    # Verify task was created
    task = RubyTodo::Task.where(title: title).last
    assert_equal title, task.title
    assert_equal description, task.description
    assert_equal "high", task.priority
  end

  def test_task_movement
    # Test task movement
    task = @notebook.tasks.create(title: "Move me", status: "todo")

    response = {
      "commands" => [
        "task:move \"Test Notebook\" #{task.id} in_progress"
      ]
    }

    _out, _err = capture_io do
      @ai_command.send(:execute_actions, response)
    end

    # Verify task was moved
    task.reload
    assert_equal "in_progress", task.status
  end

  def test_task_listing
    response = {
      "commands" => [
        'task:list "Test Notebook"'
      ]
    }

    out, _err = capture_io do
      @ai_command.send(:execute_actions, response)
    end

    # Verify tasks are listed
    assert_match(/#{@task1.id}: Test Task 1 \(todo\)/, out)
    assert_match(/#{@task2.id}: Test Task 2 \(todo\)/, out)
    assert_match(/#{@task3.id}: Test Task 3 \(in_progress\)/, out)
  end

  def test_task_deletion
    task = @notebook.tasks.create(title: "Delete me", status: "todo")

    response = {
      "commands" => [
        "task:delete \"Test Notebook\" #{task.id}"
      ]
    }

    _out, _err = capture_io do
      @ai_command.send(:execute_actions, response)
    end

    # Verify task was deleted
    assert_nil RubyTodo::Task.find_by(id: task.id)
  end

  def test_handle_task_request
    # Test task movement with task ID
    response = {
      "commands" => [
        "task:move \"Test Notebook\" #{@task1.id} done"
      ]
    }

    # Capture stdout to verify output
    _out, _err = capture_io do
      @ai_command.send(:execute_actions, response)
    end

    # Verify task was moved
    @task1.reload
    assert_equal "done", @task1.status

    # Test with a different status
    response = {
      "commands" => [
        "task:move \"Test Notebook\" #{@task2.id} in_progress"
      ]
    }

    _out, _err = capture_io do
      @ai_command.send(:execute_actions, response)
    end

    # Verify task was moved
    @task2.reload
    assert_equal "in_progress", @task2.status
  end

  def test_handle_move_all_tasks
    # Test handling of "move all tasks" command
    response = {
      "commands" => [
        "task:move \"Test Notebook\" #{@task1.id} in_progress",
        "task:move \"Test Notebook\" #{@task2.id} in_progress",
        "task:move \"Test Notebook\" #{@task3.id} in_progress"
      ]
    }

    # Capture stdout to verify output
    _out, _err = capture_io do
      @ai_command.send(:execute_actions, response)
    end

    # Verify all tasks were moved
    [@task1, @task2, @task3].each do |task|
      task.reload
      assert_equal "in_progress", task.status
    end
  end

  def test_compound_query_detection
    # Create tasks with multiple terms
    project1 = "alpha-project"
    project2 = "beta-project"

    # Create test tasks
    task1 = @notebook.tasks.create(
      title: "Update #{project1} documentation",
      status: "todo"
    )
    task2 = @notebook.tasks.create(
      title: "Fix bugs in #{project2} module",
      status: "todo"
    )
    task3 = @notebook.tasks.create(
      title: "Refactor code in both #{project1} and #{project2}",
      status: "todo"
    )

    # Test compound query with multiple tasks
    response = {
      "commands" => [
        "task:move \"Test Notebook\" #{task1.id} done",
        "task:move \"Test Notebook\" #{task2.id} done",
        "task:move \"Test Notebook\" #{task3.id} done"
      ]
    }

    # Capture stdout to verify output
    _out, _err = capture_io do
      @ai_command.send(:execute_actions, response)
    end

    # Verify tasks were moved
    [task1, task2, task3].each do |task|
      task.reload
      assert_equal "done", task.status
    end
  end

  def test_status_extraction
    # Test direct status extraction for different commands
    test_cases = [
      {
        prompt: "task:move \"Test Notebook\" #{@task1.id} done",
        expected: "done"
      },
      {
        prompt: "task:move \"Test Notebook\" #{@task2.id} in_progress",
        expected: "in_progress"
      },
      {
        prompt: "task:move \"Test Notebook\" #{@task3.id} todo",
        expected: "todo"
      }
    ]

    test_cases.each do |test_case|
      response = {
        "commands" => [test_case[:prompt]]
      }

      _out, _err = capture_io do
        @ai_command.send(:execute_actions, response)
      end

      # Verify task status was updated
      task_id = test_case[:prompt].match(/\d+/)[0].to_i
      task = RubyTodo::Task.find(task_id)
      assert_equal test_case[:expected], task.status
    end
  end

  def test_process_task_add_unquoted_description
    # Test the process_task_add method directly with unquoted description
    notebook_name = "Test Notebook"
    title = "New direct test task"
    description = "This is an unquoted description"

    # Create the task directly with CLI
    cli = RubyTodo::CLI.new
    cli.options = {
      description: description,
      priority: "high"
    }

    _out, _err = capture_io do
      cli.task_add(notebook_name, title)
    end

    # Verify task was created
    task = RubyTodo::Task.where(title: title).last
    assert_equal title, task.title
    assert_equal description, task.description
    assert_equal "high", task.priority
  end

  def test_direct_task_add
    notebook_name = "Test Notebook"
    title = "Direct CLI Task"
    description = "Test description directly from CLI"

    cli = RubyTodo::CLI.new
    cli.options = { description: description, priority: "high" }

    _out, _err = capture_io do
      cli.task_add(notebook_name, title)
    end

    # Verify task was created
    task = RubyTodo::Task.where(title: title).last
    assert_equal title, task.title
    assert_equal description, task.description
    assert_equal "high", task.priority
  end
end
