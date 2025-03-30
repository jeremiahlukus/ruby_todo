# frozen_string_literal: true

require "test_helper"

module RubyTodo
  class TaskTest < Minitest::Test
    def setup
      Database.setup
      @notebook = Notebook.create(name: "Test Notebook")
    end

    def teardown
      Task.delete_all
      Notebook.delete_all
    end

    def test_create_task
      task = Task.create(
        notebook: @notebook,
        title: "Test Task",
        status: "todo"
      )

      assert_predicate task, :valid?
      assert_equal "Test Task", task.title
      assert_equal "todo", task.status
      assert_equal @notebook.id, task.notebook_id
    end

    def test_validates_title_presence
      task = Task.new(
        notebook: @notebook,
        status: "todo"
      )

      refute_predicate task, :valid?
      assert_includes task.errors[:title], "can't be blank"
    end

    def test_validates_status_inclusion
      task = Task.new(
        notebook: @notebook,
        title: "Test Task",
        status: "invalid"
      )

      refute_predicate task, :valid?
      assert_includes task.errors[:status], "is not included in the list"
    end

    def test_validates_priority
      task = Task.new(
        notebook: @notebook,
        title: "Test Task",
        status: "todo",
        priority: "invalid"
      )

      refute_predicate task, :valid?
      assert_includes task.errors[:priority], "is not included in the list"
    end

    def test_overdue_method
      future_task = Task.create(
        notebook: @notebook,
        title: "Future Task",
        status: "todo",
        due_date: Time.now + 24 * 60 * 60
      )

      past_task = Task.create(
        notebook: @notebook,
        title: "Past Task",
        status: "todo",
        due_date: Time.now - 24 * 60 * 60
      )

      completed_past_task = Task.create(
        notebook: @notebook,
        title: "Completed Past Task",
        status: "done",
        due_date: Time.now - 24 * 60 * 60
      )

      refute_predicate future_task, :overdue?
      assert_predicate past_task, :overdue?
      refute_predicate completed_past_task, :overdue?
    end

    def test_due_soon_method
      future_task = Task.create(
        notebook: @notebook,
        title: "Future Task",
        status: "todo",
        due_date: Time.now + 48 * 60 * 60
      )

      soon_task = Task.create(
        notebook: @notebook,
        title: "Soon Task",
        status: "todo",
        due_date: Time.now + 12 * 60 * 60
      )

      completed_soon_task = Task.create(
        notebook: @notebook,
        title: "Completed Soon Task",
        status: "done",
        due_date: Time.now + 12 * 60 * 60
      )

      refute_predicate future_task, :due_soon?
      assert_predicate soon_task, :due_soon?
      refute_predicate completed_soon_task, :due_soon?
    end

    def test_tag_list_method
      task = Task.create(
        notebook: @notebook,
        title: "Tagged Task",
        status: "todo",
        tags: "work, important, project"
      )

      assert_equal %w[work important project], task.tag_list
    end

    def test_has_tag_method
      task = Task.create(
        notebook: @notebook,
        title: "Tagged Task",
        status: "todo",
        tags: "work, important, project"
      )

      assert task.has_tag?("important")
      refute task.has_tag?("personal")
    end
  end
end
