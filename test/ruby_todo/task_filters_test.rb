# frozen_string_literal: true

require "test_helper"

module RubyTodo
  class TaskFiltersTest < Minitest::Test
    include TaskFilters

    def setup
      super
      @notebook = Notebook.create(name: "Test Notebook")
      @task1 = @notebook.tasks.create(
        title: "High Priority Task",
        status: "todo",
        priority: "high",
        tags: "important,urgent"
      )
      @task2 = @notebook.tasks.create(
        title: "Low Priority Task",
        status: "in_progress",
        priority: "low",
        tags: "normal"
      )
      @task3 = @notebook.tasks.create(
        title: "Done Task",
        status: "done",
        priority: "medium",
        tags: "completed"
      )
      @options = {}
    end

    attr_reader :options

    def test_apply_filters_without_options
      filtered_tasks = apply_filters(@notebook.tasks)
      assert_equal 3, filtered_tasks.count
    end

    def test_apply_status_filter
      @options[:status] = "todo"
      filtered_tasks = apply_filters(@notebook.tasks)
      assert_equal 1, filtered_tasks.count
      assert_equal @task1, filtered_tasks.first
    end

    def test_apply_priority_filter
      @options[:priority] = "high"
      filtered_tasks = apply_filters(@notebook.tasks)
      assert_equal 1, filtered_tasks.count
      assert_equal @task1, filtered_tasks.first
    end

    def test_apply_tag_filter
      @options[:tags] = "important"
      filtered_tasks = apply_filters(@notebook.tasks)
      assert_equal 1, filtered_tasks.count
      assert_equal @task1, filtered_tasks.first
    end

    def test_apply_multiple_filters
      @options[:status] = "todo"
      @options[:priority] = "high"
      @options[:tags] = "important"
      filtered_tasks = apply_filters(@notebook.tasks)
      assert_equal 1, filtered_tasks.count
      assert_equal @task1, filtered_tasks.first
    end

    def test_apply_filters_with_no_matches
      @options[:status] = "archived"
      filtered_tasks = apply_filters(@notebook.tasks)
      assert_equal 0, filtered_tasks.count
    end
  end
end
