# frozen_string_literal: true

require "thor"
require "colorize"
require "tty-prompt"
require "tty-table"
require "time"
require "json"
require "fileutils"
require "csv"
require_relative "models/notebook"
require_relative "models/task"
require_relative "models/template"
require_relative "database"
require_relative "commands/ai_assistant"
require_relative "formatters/display_formatter"
require_relative "concerns/statistics"
require_relative "concerns/task_filters"
require_relative "concerns/import_export"
require_relative "commands/notebook_commands"
require_relative "commands/template_commands"
require_relative "commands/ai_commands"

module RubyTodo
  class CLI < Thor
    include Thor::Actions
    include DisplayFormatter
    include Statistics
    include TaskFilters
    include ImportExport
    include NotebookCommands
    include TemplateCommands
    include AICommands

    map %w[--version -v] => :version
    desc "version", "Show the Ruby Todo version"
    def version
      puts "Ruby Todo version #{RubyTodo::VERSION}"
    end

    def self.exit_on_failure?
      true
    end

    class_option :notebook, type: :string, desc: "Specify the notebook to use"

    def initialize(*args)
      super
      @prompt = TTY::Prompt.new
      Database.setup
    end

    desc "init", "Initialize a new todo list"
    def init
      say "Initializing Ruby Todo...".green
      Database.setup
      say "Ruby Todo has been initialized successfully!".green
    end

    # Task commands
    desc "task:add [NOTEBOOK] [TITLE]", "Add a new task to a notebook"
    method_option :description, type: :string, desc: "Task description"
    method_option :due_date, type: :string, desc: "Due date (YYYY-MM-DD HH:MM)"
    method_option :priority, type: :string, desc: "Priority (high, medium, low)"
    method_option :tags, type: :string, desc: "Tags (comma-separated)"
    def task_add(notebook_name, title)
      notebook = find_notebook(notebook_name)
      return unless notebook

      description = options[:description]
      due_date = parse_due_date(options[:due_date]) if options[:due_date]
      priority = options[:priority]
      tags = options[:tags]&.split(",")&.map(&:strip)&.join(",")

      task = Task.create(
        notebook: notebook,
        title: title,
        description: description,
        due_date: due_date,
        priority: priority,
        tags: tags,
        status: "todo"
      )

      if task.valid?
        say "Added task: #{title}".green
        say "Description: #{description}" if description
        say "Due date: #{format_due_date(due_date)}" if due_date
        say "Priority: #{priority}" if priority
        say "Tags: #{tags}" if tags
      else
        say "Error adding task: #{task.errors.full_messages.join(", ")}".red
      end
    end

    desc "task:list [NOTEBOOK]", "List all tasks in a notebook"
    method_option :status, type: :string, desc: "Filter by status (todo, in_progress, done, archived)"
    method_option :priority, type: :string, desc: "Filter by priority (high, medium, low)"
    method_option :due_soon, type: :boolean, desc: "Show only tasks due soon (within 24 hours)"
    method_option :overdue, type: :boolean, desc: "Show only overdue tasks"
    method_option :tags, type: :string, desc: "Filter by tags (comma-separated)"
    def task_list(notebook_name)
      notebook = find_notebook(notebook_name)
      return unless notebook

      tasks = apply_filters(notebook.tasks)

      if tasks.empty?
        say "No tasks found in notebook '#{notebook_name}'".yellow
        return
      end

      display_tasks(tasks)
    end

    desc "task:show [NOTEBOOK] [TASK_ID]", "Show detailed information about a task"
    def task_show(notebook_name, task_id)
      notebook = Notebook.find_by(name: notebook_name)
      unless notebook
        say "Notebook '#{notebook_name}' not found".red
        return
      end

      task = notebook.tasks.find_by(id: task_id)
      unless task
        say "Task with ID #{task_id} not found".red
        return
      end

      say "\nTask Details:".green
      say "ID: #{task.id}"
      say "Title: #{task.title}"
      say "Status: #{format_status(task.status)}"
      say "Priority: #{format_priority(task.priority) || "None"}"
      say "Due Date: #{format_due_date(task.due_date)}"
      say "Tags: #{task.tags || "None"}"
      say "Description: #{task.description || "No description"}"
      say "Created: #{task.created_at}"
      say "Updated: #{task.updated_at}"
    end

    desc "task:edit [NOTEBOOK] [TASK_ID]", "Edit an existing task"
    method_option :title, type: :string, desc: "New title"
    method_option :description, type: :string, desc: "New description"
    method_option :due_date, type: :string, desc: "New due date (YYYY-MM-DD HH:MM)"
    method_option :priority, type: :string, desc: "New priority (high, medium, low)"
    method_option :tags, type: :string, desc: "New tags (comma-separated)"
    method_option :status, type: :string, desc: "New status (todo, in_progress, done, archived)"
    def task_edit(notebook_name, task_id)
      notebook = Notebook.find_by(name: notebook_name)
      unless notebook
        say "Notebook '#{notebook_name}' not found".red
        return
      end

      task = notebook.tasks.find_by(id: task_id)
      unless task
        say "Task with ID #{task_id} not found".red
        return
      end

      updates = {}
      updates[:title] = options[:title] if options[:title]
      updates[:description] = options[:description] if options[:description]
      updates[:priority] = options[:priority] if options[:priority]
      updates[:status] = options[:status] if options[:status]
      updates[:tags] = options[:tags] if options[:tags]

      if options[:due_date]
        updates[:due_date] = parse_due_date(options[:due_date])
      end

      if updates.empty?
        say "No updates specified. Use --title, --description, etc. to specify updates.".yellow
        return
      end

      if task.update(updates)
        say "Updated task #{task_id}".green
      else
        say "Error updating task: #{task.errors.full_messages.join(", ")}".red
      end
    end

    desc "task:move [NOTEBOOK] [TASK_ID] [STATUS]", "Move a task to a different status"
    def task_move(notebook_name, task_id, status)
      notebook = Notebook.find_by(name: notebook_name)
      unless notebook
        say "Notebook '#{notebook_name}' not found".red
        return
      end

      task = notebook.tasks.find_by(id: task_id)
      unless task
        say "Task with ID #{task_id} not found".red
        return
      end

      if task.update(status: status)
        say "Moved task #{task_id} to #{status}".green
      else
        say "Error moving task: #{task.errors.full_messages.join(", ")}".red
      end
    end

    desc "task:delete [NOTEBOOK] [TASK_ID]", "Delete a task"
    def task_delete(notebook_name, task_id)
      notebook = Notebook.find_by(name: notebook_name)
      unless notebook
        say "Notebook '#{notebook_name}' not found".red
        return
      end

      task = notebook.tasks.find_by(id: task_id)
      unless task
        say "Task with ID #{task_id} not found".red
        return
      end

      task.destroy
      say "Deleted task #{task_id}".green
    end

    desc "task:search [QUERY]", "Search for tasks across all notebooks"
    method_option :notebook, type: :string, desc: "Limit search to a specific notebook"
    def task_search(query)
      notebooks = if options[:notebook]
                    [Notebook.find_by(name: options[:notebook])].compact
                  else
                    Notebook.all
                  end

      if notebooks.empty?
        say "No notebooks found".yellow
        return
      end

      results = []
      notebooks.each do |notebook|
        notebook.tasks.each do |task|
          next unless task.title.downcase.include?(query.downcase) ||
                      (task.description && task.description.downcase.include?(query.downcase)) ||
                      (task.tags && task.tags.downcase.include?(query.downcase))

          results << [notebook.name, task.id, task.title, format_status(task.status)]
        end
      end

      if results.empty?
        say "No tasks matching '#{query}' found".yellow
        return
      end

      table = TTY::Table.new(
        header: %w[Notebook ID Title Status],
        rows: results
      )
      puts table.render(:ascii)
    end

    desc "stats [NOTEBOOK]", "Show statistics for a notebook or all notebooks"
    def stats(notebook_name = nil)
      if notebook_name
        notebook = Notebook.find_by(name: notebook_name)
        unless notebook
          say "Notebook '#{notebook_name}' not found".red
          return
        end
        display_notebook_stats(notebook)
      else
        display_global_stats
      end
    end

    desc "export [NOTEBOOK] [FILENAME]", "Export tasks from a notebook to a JSON file"
    method_option :format, type: :string, default: "json", desc: "Export format (json or csv)"
    method_option :all, type: :boolean, desc: "Export all notebooks"
    def export(notebook_name = nil, filename = nil)
      # Determine what to export
      if options[:all]
        notebooks = Notebook.all
        if notebooks.empty?
          say "No notebooks found".yellow
          return
        end

        data = export_all_notebooks(notebooks)
        filename ||= "ruby_todo_export_all_#{Time.now.strftime("%Y%m%d_%H%M%S")}"
      else
        unless notebook_name
          say "Please specify a notebook name or use --all to export all notebooks".red
          return
        end

        notebook = Notebook.find_by(name: notebook_name)
        unless notebook
          say "Notebook '#{notebook_name}' not found".red
          return
        end

        data = export_notebook(notebook)
        filename ||= "ruby_todo_export_#{notebook_name}_#{Time.now.strftime("%Y%m%d_%H%M%S")}"
      end

      # Ensure export directory exists
      export_dir = File.expand_path("~/.ruby_todo/exports")
      FileUtils.mkdir_p(export_dir)

      # Determine export format and save
      if options[:format].downcase == "csv"
        filename = "#{filename}.csv" unless filename.end_with?(".csv")
        export_path = File.join(export_dir, filename)
        export_to_csv(data, export_path)
      else
        filename = "#{filename}.json" unless filename.end_with?(".json")
        export_path = File.join(export_dir, filename)
        export_to_json(data, export_path)
      end

      say "Tasks exported to #{export_path}".green
    end

    desc "import [FILENAME]", "Import tasks from a JSON or CSV file"
    method_option :format, type: :string, default: "json", desc: "Import format (json or csv)"
    method_option :notebook, type: :string, desc: "Target notebook for imported tasks"
    def import(filename)
      # Validate file exists
      unless File.exist?(filename)
        expanded_path = File.expand_path(filename)
        if File.exist?(expanded_path)
          filename = expanded_path
        else
          export_dir = File.expand_path("~/.ruby_todo/exports")
          full_path = File.join(export_dir, filename)

          unless File.exist?(full_path)
            say "File '#{filename}' not found".red
            return
          end

          filename = full_path
        end
      end

      # Determine import format from file extension if not specified
      format = options[:format].downcase
      if format != "json" && format != "csv"
        if filename.end_with?(".json")
          format = "json"
        elsif filename.end_with?(".csv")
          format = "csv"
        else
          say "Unsupported file format. Please use .json or .csv files".red
          return
        end
      end

      # Parse the file
      begin
        if format == "json"
          data = JSON.parse(File.read(filename))
        else
          say "CSV import is not yet implemented".red
          return
        end
      rescue JSON::ParserError => e
        say "Error parsing JSON file: #{e.message}".red
        return
      rescue StandardError => e
        say "Error reading file: #{e.message}".red
        return
      end

      # Import the data
      if data.key?("notebooks")
        # This is a full export with multiple notebooks
        imported = import_all_notebooks(data)
        say "Imported #{imported[:notebooks]} notebooks with #{imported[:tasks]} tasks".green
      else
        # This is a single notebook export
        notebook_name = options[:notebook] || data["name"]
        notebook = Notebook.find_by(name: notebook_name)

        unless notebook
          if @prompt.yes?("Notebook '#{notebook_name}' does not exist. Create it?")
            notebook = Notebook.create(name: notebook_name)
          else
            say "Import cancelled".yellow
            return
          end
        end

        count = import_tasks(notebook, data["tasks"])
        say "Imported #{count} tasks into notebook '#{notebook.name}'".green
      end
    end

    # Register command descriptions
    desc "notebook:create NAME", "Create a new notebook"
    desc "notebook:list", "List all notebooks"
    desc "notebook:set_default NOTEBOOK", "Set a notebook as the default"
    desc "template:create NAME", "Create a new task template"
    desc "template:list", "List all templates"
    desc "template:show NAME", "Show details of a specific template"
    desc "template:delete NAME", "Delete a template"
    desc "template:use NAME NOTEBOOK", "Create a task from a template in the specified notebook"
    desc "ai:ask PROMPT", "Ask the AI assistant to perform tasks using natural language"
    desc "ai:configure", "Configure the AI assistant settings"

    # Map commands to use colon format
    map "task:add" => :task_add
    map "task:list" => :task_list
    map "task:show" => :task_show
    map "task:edit" => :task_edit
    map "task:move" => :task_move
    map "task:delete" => :task_delete
    map "task:search" => :task_search
    map "notebook:create" => :notebook_create
    map "notebook:list" => :notebook_list
    map "notebook:set_default" => :notebook_set_default
    map "template:create" => :template_create
    map "template:list" => :template_list
    map "template:show" => :template_show
    map "template:delete" => :template_delete
    map "template:use" => :template_use
    map "ai:ask" => :ai_ask
    map "ai:configure" => :ai_configure

    private

    def display_notebook_stats(notebook)
      stats = notebook.statistics

      say "\nStatistics for notebook: #{notebook.name}".green
      say "\nTask Counts:".blue
      say "Total: #{stats[:total]}"
      say "Todo: #{stats[:todo]}"
      say "In Progress: #{stats[:in_progress]}"
      say "Done: #{stats[:done]}"
      say "Archived: #{stats[:archived]}"

      say "\nDue Dates:".blue
      say "Overdue: #{stats[:overdue]}"
      say "Due Soon: #{stats[:due_soon]}"

      say "\nPriority:".blue
      say "High: #{stats[:high_priority]}"
      say "Medium: #{stats[:medium_priority]}"
      say "Low: #{stats[:low_priority]}"

      if stats[:total] > 0
        say "\nStatus Percentages:".blue
        say "Todo: #{percentage(stats[:todo], stats[:total])}%"
        say "In Progress: #{percentage(stats[:in_progress], stats[:total])}%"
        say "Done: #{percentage(stats[:done], stats[:total])}%"
        say "Archived: #{percentage(stats[:archived], stats[:total])}%"
      end
    end

    def display_global_stats
      notebooks = Notebook.all

      if notebooks.empty?
        say "No notebooks found".yellow
        return
      end

      total_tasks = 0
      total_stats = { todo: 0, in_progress: 0, done: 0, archived: 0,
                      overdue: 0, due_soon: 0,
                      high_priority: 0, medium_priority: 0, low_priority: 0 }

      notebooks.each do |notebook|
        stats = notebook.statistics
        total_tasks += stats[:total]

        total_stats[:todo] += stats[:todo]
        total_stats[:in_progress] += stats[:in_progress]
        total_stats[:done] += stats[:done]
        total_stats[:archived] += stats[:archived]
        total_stats[:overdue] += stats[:overdue]
        total_stats[:due_soon] += stats[:due_soon]
        total_stats[:high_priority] += stats[:high_priority]
        total_stats[:medium_priority] += stats[:medium_priority]
        total_stats[:low_priority] += stats[:low_priority]
      end

      say "\nGlobal Statistics across #{notebooks.count} notebooks:".green
      say "Total Tasks: #{total_tasks}"

      if total_tasks > 0
        say "\nTask Counts:".blue
        say "Todo: #{total_stats[:todo]} (#{percentage(total_stats[:todo], total_tasks)}%)"
        say "In Progress: #{total_stats[:in_progress]} (#{percentage(total_stats[:in_progress], total_tasks)}%)"
        say "Done: #{total_stats[:done]} (#{percentage(total_stats[:done], total_tasks)}%)"
        say "Archived: #{total_stats[:archived]} (#{percentage(total_stats[:archived], total_tasks)}%)"

        say "\nDue Dates:".blue
        say "Overdue: #{total_stats[:overdue]} (#{percentage(total_stats[:overdue], total_tasks)}%)"
        say "Due Soon: #{total_stats[:due_soon]} (#{percentage(total_stats[:due_soon], total_tasks)}%)"

        say "\nPriority:".blue
        say "High: #{total_stats[:high_priority]} (#{percentage(total_stats[:high_priority], total_tasks)}%)"
        say "Medium: #{total_stats[:medium_priority]} (#{percentage(total_stats[:medium_priority], total_tasks)}%)"
        say "Low: #{total_stats[:low_priority]} (#{percentage(total_stats[:low_priority], total_tasks)}%)"
      end

      # Display top notebooks by task count
      table = TTY::Table.new(
        header: ["Notebook", "Tasks", "% of Total"],
        rows: notebooks.sort_by { |n| -n.tasks.count }.first(5).map do |n|
          [n.name, n.tasks.count, percentage(n.tasks.count, total_tasks)]
        end
      )

      say "\nTop Notebooks:".blue
      puts table.render(:ascii)
    end

    def percentage(part, total)
      return 0 if total == 0

      ((part.to_f / total) * 100).round(1)
    end

    def parse_due_date(date_string)
      Time.parse(date_string)
    rescue ArgumentError
      say "Invalid date format. Use YYYY-MM-DD HH:MM format.".red
      nil
    end

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

    def ai_command
      @ai_command ||= AIAssistantCommand.new
    end

    def find_notebook(notebook_name)
      notebook = Notebook.find_by(name: notebook_name)
      unless notebook
        say "Notebook '#{notebook_name}' not found".red
        return nil
      end
      notebook
    end

    def apply_filters(tasks)
      tasks = apply_status_filter(tasks)
      tasks = apply_priority_filter(tasks)
      tasks = apply_tag_filter(tasks)
      apply_due_date_filters(tasks)
    end

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

    def display_tasks(tasks)
      if ENV["RUBY_TODO_TEST"]
        display_tasks_simple_format(tasks)
      else
        display_tasks_table_format(tasks)
      end
    end

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
