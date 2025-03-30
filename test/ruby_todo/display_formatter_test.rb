# frozen_string_literal: true

require "test_helper"

module RubyTodo
  class DisplayFormatterTest < Minitest::Test
    include DisplayFormatter

    def setup
      super
      @notebook = Notebook.create(name: "Test Notebook")
      @task = @notebook.tasks.create(
        title: "Test Task",
        description: "Test Description",
        status: "todo",
        priority: "high",
        tags: "test,important",
        due_date: Time.now + 24 * 60 * 60
      )
    end

    def test_format_status
      assert_match(/Todo/, format_status("todo"))
      assert_match(/In Progress/, format_status("in_progress"))
      assert_match(/Done/, format_status("done"))
      assert_match(/Archived/, format_status("archived"))
    end

    def test_format_priority
      assert_match(/High/, format_priority("high"))
      assert_match(/Medium/, format_priority("medium"))
      assert_match(/Low/, format_priority("low"))
      assert_nil format_priority(nil)
    end

    def test_format_due_date
      now = Time.now
      assert_equal "No due date", format_due_date(nil)
      assert_match(/Today/, format_due_date(now + 12 * 60 * 60))
      assert_match(/Overdue/, format_due_date(now - 48 * 60 * 60))
    end

    def test_truncate_text
      assert_equal "abc", truncate_text("abc", 5)
      assert_equal "abc...", truncate_text("abcdef", 3)
      assert_nil truncate_text(nil)
    end

    def test_display_tasks
      out, _err = capture_io do
        display_tasks([@task])
      end

      assert_match(/#{@task.id}/, out)
      assert_match(/Test Task/, out)
      assert_match(/todo/, out)
    end
  end
end
