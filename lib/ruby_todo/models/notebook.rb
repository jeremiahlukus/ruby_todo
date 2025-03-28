# frozen_string_literal: true

require "active_record"

module RubyTodo
  class Notebook < ActiveRecord::Base
    has_many :tasks, dependent: :destroy
    has_many :templates

    validates :name, presence: true
    validates :name, uniqueness: true

    scope :default, -> { where(is_default: true).first }

    before_create :set_default_if_first
    before_save :ensure_only_one_default

    def self.default_notebook
      find_by(is_default: true)
    end

    def make_default!
      transaction do
        Notebook.where.not(id: id).update_all(is_default: false)
        update!(is_default: true)
      end
    end

    def is_default?
      is_default
    end

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
      stats = {
        total: tasks.count,
        todo: tasks.where(status: "todo").count,
        in_progress: tasks.where(status: "in_progress").count,
        done: tasks.where(status: "done").count,
        archived: tasks.where(status: "archived").count,
        overdue: tasks.select(&:overdue?).count,
        due_soon: tasks.select(&:due_soon?).count,
        high_priority: tasks.where(priority: "high").count,
        medium_priority: tasks.where(priority: "medium").count,
        low_priority: tasks.where(priority: "low").count
      }

      stats
    end

    private

    def set_default_if_first
      self.is_default = true if Notebook.count.zero?
    end

    def ensure_only_one_default
      return unless is_default_changed? && is_default?

      Notebook.where.not(id: id).update_all(is_default: false)
    end
  end
end
