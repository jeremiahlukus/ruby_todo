# frozen_string_literal: true

module RubyTodo
  module DisplayFormatter
    def format_status(status)
      case status
      when "todo" then "Todo".yellow
      when "in_progress" then "In Progress".blue
      when "done" then "Done".green
      when "archived" then "Archived".gray
      else status
      end
    end

    def format_priority(priority)
      return nil unless priority

      case priority.downcase
      when "high" then "High".red
      when "medium" then "Medium".yellow
      when "low" then "Low".green
      else priority
      end
    end

    def format_due_date(due_date)
      return "No due date" unless due_date

      if due_date < Time.now && due_date > Time.now - 24 * 60 * 60
        "Today #{due_date.strftime("%H:%M")}".red
      elsif due_date < Time.now
        "Overdue #{due_date.strftime("%Y-%m-%d %H:%M")}".red
      elsif due_date < Time.now + 24 * 60 * 60
        "Today #{due_date.strftime("%H:%M")}".yellow
      else
        due_date.strftime("%Y-%m-%d %H:%M")
      end
    end

    def truncate_text(text, length = 30)
      return nil unless text

      text.length > length ? "#{text[0...length]}..." : text
    end

    def display_tasks(tasks)
      if ENV["RUBY_TODO_TEST"]
        display_tasks_simple_format(tasks)
      else
        display_tasks_table_format(tasks)
      end
    end

    private

    def display_tasks_simple_format(tasks)
      tasks.each do |t|
        puts "#{t.id}: #{t.title} (#{t.status})"
      end
    end

    def display_tasks_table_format(tasks)
      table = TTY::Table.new(
        header: ["ID", "Title", "Status", "Priority", "Due Date", "Tags", "Description"],
        rows: tasks.map do |t|
          [
            t.id,
            t.title,
            format_status(t.status),
            format_priority(t.priority),
            format_due_date(t.due_date),
            truncate_text(t.tags, 15),
            truncate_text(t.description, 30)
          ]
        end
      )
      puts table.render(:ascii)
    end
  end
end
