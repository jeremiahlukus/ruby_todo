# frozen_string_literal: true

require "active_record"

module RubyTodo
  class Notebook < ActiveRecord::Base
    has_many :tasks, dependent: :destroy

    validates :name, presence: true, uniqueness: true

    def tasks_by_status(status)
      tasks.where(status: status)
    end

    def tasks_by_priority(priority)
      tasks.where(priority: priority)
    end

    def tasks_with_tag(tag)
      tasks.select { |task| task.has_tag?(tag) }
    end

    def overdue_tasks
      tasks.select(&:overdue?)
    end

    def due_soon_tasks
      tasks.select(&:due_soon?)
    end

    def todo_tasks
      tasks_by_status("todo")
    end

    def in_progress_tasks
      tasks_by_status("in_progress")
    end

    def done_tasks
      tasks_by_status("done")
    end

    def archived_tasks
      tasks_by_status("archived")
    end

    def high_priority_tasks
      tasks_by_priority("high")
    end

    def medium_priority_tasks
      tasks_by_priority("medium")
    end

    def low_priority_tasks
      tasks_by_priority("low")
    end

    def statistics
      {
        total: tasks.count,
        todo: todo_tasks.count,
        in_progress: in_progress_tasks.count,
        done: done_tasks.count,
        archived: archived_tasks.count,
        overdue: overdue_tasks.count,
        due_soon: due_soon_tasks.count,
        high_priority: high_priority_tasks.count,
        medium_priority: medium_priority_tasks.count,
        low_priority: low_priority_tasks.count
      }
    end
  end
end
