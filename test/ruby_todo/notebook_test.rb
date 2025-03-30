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
      Task.create(
        notebook: @notebook,
        title: "Todo Task",
        status: "todo",
        priority: "high"
      )

      Task.create(
        notebook: @notebook,
        title: "In Progress Task",
        status: "in_progress",
        priority: "medium"
      )

      Task.create(
        notebook: @notebook,
        title: "Done Task",
        status: "done",
        priority: "low"
      )

      stats = @notebook.statistics

      assert_equal 3, stats[:total]
      assert_equal 1, stats[:todo]
      assert_equal 1, stats[:in_progress]
      assert_equal 1, stats[:done] # Done tasks are no longer auto-archived
      assert_equal 0, stats[:archived]
      assert_equal 1, stats[:high_priority]
      assert_equal 1, stats[:medium_priority]
      assert_equal 1, stats[:low_priority]
    end
  end
end
