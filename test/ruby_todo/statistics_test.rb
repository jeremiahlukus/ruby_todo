# frozen_string_literal: true

require "test_helper"

module RubyTodo
  class StatisticsTest < Minitest::Test
    include Statistics

    def setup
      super
      @notebook = Notebook.create(name: "Test Notebook")
      create_test_tasks
    end

    def test_display_notebook_stats
      out, _err = capture_io do
        display_notebook_stats(@notebook)
      end

      assert_match(/Statistics for notebook '#{@notebook.name}'/, out)
      assert_match(/Total tasks: 4/, out)
      assert_match(/Todo: 1/, out)
      assert_match(/In Progress: 1/, out)
      assert_match(/Done: 1/, out)
      assert_match(/Archived: 1/, out)
    end

    def test_display_global_stats
      out, _err = capture_io do
        display_global_stats
      end

      assert_match(/Global Statistics/, out)
      assert_match(/Total tasks across all notebooks: 4/, out)
      assert_match(/Todo: 1/, out)
      assert_match(/In Progress: 1/, out)
      assert_match(/Done: 1/, out)
      assert_match(/Archived: 1/, out)
    end

    def test_percentage_calculation
      assert_equal 0, percentage(0, 0)
      assert_in_delta(50.0, percentage(1, 2))
      assert_in_delta(33.3, percentage(1, 3))
      assert_in_delta(100.0, percentage(5, 5))
    end

    private

    def create_test_tasks
      @notebook.tasks.create(
        title: "Todo Task",
        status: "todo",
        priority: "high"
      )
      @notebook.tasks.create(
        title: "In Progress Task",
        status: "in_progress",
        priority: "medium"
      )
      @notebook.tasks.create(
        title: "Done Task",
        status: "done",
        priority: "low"
      )
      @notebook.tasks.create(
        title: "Archived Task",
        status: "archived",
        priority: "low"
      )
    end

    def say(message)
      puts message
    end
  end
end
