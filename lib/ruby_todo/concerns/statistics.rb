# frozen_string_literal: true

module RubyTodo
  module StatisticsDisplay
    private

    def display_priority_distribution(tasks)
      return if tasks.empty?

      total = tasks.count
      high_count = tasks.where(priority: "high").count
      medium_count = tasks.where(priority: "medium").count
      low_count = tasks.where(priority: "low").count

      puts "\nPriority Distribution:"
      puts "High: #{high_count} (#{percentage(high_count, total)}%)"
      puts "Medium: #{medium_count} (#{percentage(medium_count, total)}%)"
      puts "Low: #{low_count} (#{percentage(low_count, total)}%)"
    end

    def display_tag_distribution(tasks)
      return if tasks.empty?

      puts "\nTop Tags:"
      tag_counts = Hash.new(0)
      tasks.each do |task|
        task.tags.split(",").each { |tag| tag_counts[tag.strip] += 1 } if task.tags
      end

      tag_counts.sort_by { |_, count| -count }.first(5).each do |tag, count|
        puts "#{tag}: #{count} tasks (#{percentage(count, tasks.count)}%)"
      end
    end

    def display_overdue_tasks(tasks)
      return if tasks.empty?

      overdue_count = tasks.select(&:overdue?).count
      due_soon_count = tasks.select(&:due_soon?).count
      total = tasks.count

      puts "\nDue Date Status:"
      puts "Overdue: #{overdue_count} (#{percentage(overdue_count, total)}%)"
      puts "Due Soon: #{due_soon_count} (#{percentage(due_soon_count, total)}%)"
    end
  end

  module Statistics
    include StatisticsDisplay

    def display_notebook_stats(notebook)
      total_tasks = notebook.tasks.count
      return puts "No tasks found in notebook '#{notebook.name}'" if total_tasks.zero?

      todo_count = notebook.tasks.where(status: "todo").count
      in_progress_count = notebook.tasks.where(status: "in_progress").count
      done_count = notebook.tasks.where(status: "done").count
      archived_count = notebook.tasks.where(status: "archived").count

      puts "\nStatistics for notebook '#{notebook.name}':"
      puts "Total tasks: #{total_tasks}"
      puts "Todo: #{todo_count} (#{percentage(todo_count, total_tasks)}%)"
      puts "In Progress: #{in_progress_count} (#{percentage(in_progress_count, total_tasks)}%)"
      puts "Done: #{done_count} (#{percentage(done_count, total_tasks)}%)"
      puts "Archived: #{archived_count} (#{percentage(archived_count, total_tasks)}%)"

      display_priority_distribution(notebook.tasks)
      display_tag_distribution(notebook.tasks)
      display_overdue_tasks(notebook.tasks)
    end

    def display_global_stats
      total_tasks = Task.count
      return puts "No tasks found in any notebook" if total_tasks.zero?

      display_global_stats_summary
    end

    def display_top_notebooks
      puts "\nNotebook Statistics:"
      notebook_stats = collect_notebook_stats
      display_notebook_stats_table(notebook_stats)
    end

    private

    def percentage(count, total)
      return 0 if total.zero?

      ((count.to_f / total) * 100).round(1)
    end

    def display_global_stats_summary
      total_tasks = Task.count
      todo_count = Task.where(status: "todo").count
      in_progress_count = Task.where(status: "in_progress").count
      done_count = Task.where(status: "done").count
      archived_count = Task.where(status: "archived").count

      puts "\nGlobal Statistics:"
      puts "Total tasks across all notebooks: #{total_tasks}"
      puts "Todo: #{todo_count} (#{percentage(todo_count, total_tasks)}%)"
      puts "In Progress: #{in_progress_count} (#{percentage(in_progress_count, total_tasks)}%)"
      puts "Done: #{done_count} (#{percentage(done_count, total_tasks)}%)"
      puts "Archived: #{archived_count} (#{percentage(archived_count, total_tasks)}%)"

      display_priority_distribution(Task.all)
      display_tag_distribution(Task.all)
      display_overdue_tasks(Task.all)
      display_top_notebooks
    end

    def collect_notebook_stats
      notebook_data = Notebook.all.map do |notebook|
        calculate_notebook_stats(notebook)
      end
      notebook_data.sort_by! { |data| -data[1] }
    end

    def calculate_notebook_stats(notebook)
      task_count = notebook.tasks.count
      todo_count = notebook.tasks.where(status: "todo").count
      in_progress_count = notebook.tasks.where(status: "in_progress").count
      done_count = notebook.tasks.where(status: "done").count
      archived_count = notebook.tasks.where(status: "archived").count

      [
        notebook.name,
        task_count,
        todo_count,
        in_progress_count,
        done_count,
        archived_count
      ]
    end

    def display_notebook_stats_table(notebook_stats)
      headers = ["Notebook", "Total", "Todo", "In Progress", "Done", "Archived"]
      rows = create_table_rows(notebook_stats)
      render_stats_table(headers, rows)
    end

    def create_table_rows(notebook_stats)
      notebook_stats.map do |stats|
        name, total, todo, in_progress, done, archived = stats
        [
          name,
          total.to_s,
          "#{todo} (#{percentage(todo, total)}%)",
          "#{in_progress} (#{percentage(in_progress, total)}%)",
          "#{done} (#{percentage(done, total)}%)",
          "#{archived} (#{percentage(archived, total)}%)"
        ]
      end
    end

    def render_stats_table(headers, rows)
      table = TTY::Table.new(header: headers, rows: rows)
      puts table.render(:ascii, padding: [0, 1], width: TTY::Screen.width || 80)
    rescue NoMethodError
      # Fallback for non-TTY environments (like tests)
      puts headers.join("\t")
      rows.each { |row| puts row.join("\t") }
    end
  end
end
