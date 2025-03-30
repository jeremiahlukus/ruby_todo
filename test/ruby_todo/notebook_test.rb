# frozen_string_literal: true

require "test_helper"

module RubyTodo
  class NotebookTest < Minitest::Test
    def setup
      Database.setup
      @notebook = Notebook.create(name: "Test Notebook")
    end

    def teardown
      Task.delete_all
      Notebook.delete_all
    end

    def test_create_notebook
      notebook = Notebook.create(name: "Work")
      assert_predicate notebook, :valid?
      assert_equal "Work", notebook.name
    end

    def test_validates_name_presence
      notebook = Notebook.new
      refute_predicate notebook, :valid?
      assert_includes notebook.errors[:name], "can't be blank"
    end

    def test_validates_name_uniqueness
      Notebook.create(name: "Personal")
      duplicate = Notebook.new(name: "Personal")
      refute_predicate duplicate, :valid?
      assert_includes duplicate.errors[:name], "has already been taken"
    end

    def test_has_many_tasks_association
      task1 = Task.create(
        notebook: @notebook,
        title: "Task 1",
        status: "todo"
      )

      task2 = Task.create(
        notebook: @notebook,
        title: "Task 2",
        status: "in_progress"
      )

      assert_equal 2, @notebook.tasks.count
      assert_includes @notebook.tasks, task1
      assert_includes @notebook.tasks, task2
    end

    def test_tasks_by_status
      Task.create(
        notebook: @notebook,
        title: "Todo Task",
        status: "todo"
      )

      Task.create(
        notebook: @notebook,
        title: "In Progress Task",
        status: "in_progress"
      )

      Task.create(
        notebook: @notebook,
        title: "Another Todo Task",
        status: "todo"
      )

      assert_equal 2, @notebook.tasks_by_status("todo").count
      assert_equal 1, @notebook.tasks_by_status("in_progress").count
      assert_equal 0, @notebook.tasks_by_status("done").count
    end

    def test_tasks_by_priority
      Task.create(
        notebook: @notebook,
        title: "High Priority Task",
        status: "todo",
        priority: "high"
      )

      Task.create(
        notebook: @notebook,
        title: "Medium Priority Task",
        status: "todo",
        priority: "medium"
      )

      Task.create(
        notebook: @notebook,
        title: "Another High Priority Task",
        status: "todo",
        priority: "high"
      )

      assert_equal 2, @notebook.tasks_by_priority("high").count
      assert_equal 1, @notebook.tasks_by_priority("medium").count
      assert_equal 0, @notebook.tasks_by_priority("low").count
    end

    def test_tasks_with_tag
      Task.create(
        notebook: @notebook,
        title: "Work Task",
        status: "todo",
        tags: "work,important"
      )

      Task.create(
        notebook: @notebook,
        title: "Personal Task",
        status: "todo",
        tags: "personal,important"
      )

      Task.create(
        notebook: @notebook,
        title: "Other Task",
        status: "todo",
        tags: "other"
      )

      assert_equal 2, @notebook.tasks_with_tag("important").count
      assert_equal 1, @notebook.tasks_with_tag("work").count
      assert_equal 0, @notebook.tasks_with_tag("nonexistent").count
    end

    def test_statistics
      # Clear any existing tasks
      @notebook.tasks.delete_all

      # Create tasks in a transaction to ensure atomicity
      Task.transaction do
        Task.create!(
          notebook: @notebook,
          title: "Todo Task",
          status: "todo",
          priority: "high"
        )

        Task.create!(
          notebook: @notebook,
          title: "In Progress Task",
          status: "in_progress",
          priority: "medium"
        )

        Task.create!(
          notebook: @notebook,
          title: "Done Task",
          status: "done",
          priority: "low"
        )
      end

      # Force reload of tasks to ensure fresh data
      @notebook.reload

      # Debug output
      puts "\nDebug: All tasks in notebook:"
      @notebook.tasks.reload.each do |task|
        puts "Task: #{task.title}, Status: #{task.status}, Priority: #{task.priority}"
      end

      stats = @notebook.statistics
      puts "\nDebug: Statistics:"
      stats.each do |key, value|
        puts "#{key}: #{value}"
      end

      # Verify each statistic individually with descriptive messages
      assert_equal 3, stats[:total], "Expected 3 total tasks"
      assert_equal 1, stats[:todo], "Expected 1 todo task"
      assert_equal 1, stats[:in_progress], "Expected 1 in_progress task"
      # Done tasks are no longer auto-archived
      assert_equal 1, stats[:done], "Expected 1 done task but got #{stats[:done]}"
      assert_equal 0, stats[:archived], "Expected 0 archived tasks"
      assert_equal 1, stats[:high_priority], "Expected 1 high priority task"
      assert_equal 1, stats[:medium_priority], "Expected 1 medium priority task"
      assert_equal 1, stats[:low_priority], "Expected 1 low priority task"
    end

    def test_done_tasks_not_auto_archived
      # Create a task in todo state
      task = Task.create!(
        notebook: @notebook,
        title: "Test Task",
        status: "todo",
        priority: "high"
      )

      # Move it to done
      task.update!(status: "done")
      task.reload

      # Debug output
      puts "\nDebug: Task after marking as done:"
      puts "Task: #{task.title}, Status: #{task.status}"

      # Verify it stays in done status
      assert_equal "done", task.status, "Task should remain in 'done' status and not be auto-archived"

      # Double check through notebook statistics
      stats = @notebook.statistics
      assert_equal 1, stats[:done], "Should have 1 done task"
      assert_equal 0, stats[:archived], "Should have 0 archived tasks"
    end
  end
end
