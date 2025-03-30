# frozen_string_literal: true

module RubyTodo
  module TaskFilters
    def apply_filters(tasks)
      tasks = apply_status_filter(tasks)
      tasks = apply_priority_filter(tasks)
      tasks = apply_tag_filter(tasks)
      apply_due_date_filters(tasks)
    end

    private

    def apply_status_filter(tasks)
      return tasks unless options[:status]

      tasks.where(status: options[:status])
    end

    def apply_priority_filter(tasks)
      return tasks unless options[:priority]

      tasks.where(priority: options[:priority])
    end

    def apply_tag_filter(tasks)
      return tasks unless options[:tags]

      tag_filters = options[:tags].split(",").map(&:strip)
      tasks.select { |t| t.tags && tag_filters.any? { |tag| t.tags.include?(tag) } }
    end

    def apply_due_date_filters(tasks)
      tasks = tasks.select(&:due_soon?) if options[:due_soon]
      tasks = tasks.select(&:overdue?) if options[:overdue]
      tasks
    end
  end
end
