# frozen_string_literal: true

require "test_helper"

module RubyTodo
  class CLITest < Minitest::Test
    def setup
      super
      @cli = CLI.new
      @notebook = Notebook.create(name: "Test Notebook")
      @task = @notebook.tasks.create(
        title: "Test Task",
        description: "Test Description",
        status: "todo",
        priority: "high",
        tags: "test,important"
      )
    end

    def test_task_add
      out, _err = capture_io do
        @cli.task_add("Test Notebook", "New Task")
      end

      task = Task.last
      assert_equal "New Task", task.title
      assert_match(/Added task: New Task/, out)
    end

    def test_task_list
      out, _err = capture_io do
        @cli.task_list("Test Notebook")
      end

      assert_match(/#{@task.id}/, out)
      assert_match(/Test Task/, out)
      assert_match(/todo/, out)
    end

    def test_task_list_with_filters
      out, _err = capture_io do
        @cli.options = { status: "todo" }
        @cli.task_list("Test Notebook")
      end

      assert_match(/#{@task.id}/, out)
      assert_match(/Test Task/, out)
    end

    def test_find_notebook
      notebook = @cli.send(:find_notebook, "Test Notebook")
      assert_equal @notebook, notebook
    end

    def test_find_nonexistent_notebook
      out, _err = capture_io do
        notebook = @cli.send(:find_notebook, "Nonexistent")
        assert_nil notebook
      end

      assert_match(/Notebook 'Nonexistent' not found/, out)
    end

    def test_parse_due_date
      date = @cli.send(:parse_due_date, "2024-01-01 12:00")
      assert_instance_of Time, date
      assert_equal 2024, date.year
      assert_equal 1, date.month
      assert_equal 1, date.day
      assert_equal 12, date.hour
      assert_equal 0, date.min
    end

    def test_parse_invalid_due_date
      out, _err = capture_io do
        date = @cli.send(:parse_due_date, "invalid")
        assert_nil date
      end

      assert_match(/Invalid date format/, out)
    end
  end
end
