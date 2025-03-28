# frozen_string_literal: true

module RubyTodo
  module TaskStatistics
    private

    def handle_statistics_query(prompt)
      say "\nHandling statistics query" if options[:verbose]

      if prompt =~ /\b(?:show|display|get)\s+(?:me\s+)?(?:the\s+)?stats\b/i
        display_task_statistics
        return true
      end

      false
    end

    def display_task_statistics
      notebooks = RubyTodo::Notebook.all
      total_stats = { todo: 0, in_progress: 0, done: 0, archived: 0 }

      notebooks.each do |notebook|
        stats = notebook.task_statistics
        total_stats.merge!(stats) { |_key, old_val, new_val| old_val + new_val }

        display_notebook_statistics(notebook, stats)
      end

      display_total_statistics(total_stats)
    end

    def display_notebook_statistics(notebook, stats)
      say "\nNotebook: #{notebook.name}".blue
      say "  Todo: #{stats[:todo]}".yellow
      say "  In Progress: #{stats[:in_progress]}".blue
      say "  Done: #{stats[:done]}".green
      say "  Archived: #{stats[:archived]}".gray
    end

    def display_total_statistics(stats)
      say "\nTotal Statistics:".blue
      say "  Todo: #{stats[:todo]}".yellow
      say "  In Progress: #{stats[:in_progress]}".blue
      say "  Done: #{stats[:done]}".green
      say "  Archived: #{stats[:archived]}".gray
    end
  end

  module TaskPriority
    private

    def handle_priority_query(prompt)
      say "\nHandling priority query" if options[:verbose]

      if prompt =~ /\b(?:show|display|get|list)\s+(?:me\s+)?(?:the\s+)?(?:high|medium|low)\s*-?\s*priority\b/i
        display_priority_tasks(prompt)
        return true
      end

      false
    end

    def display_priority_tasks(prompt)
      priority = extract_priority_level(prompt)
      tasks = find_priority_tasks(priority)

      if tasks.any?
        display_tasks_by_priority(tasks, priority)
      else
        say "No #{priority} priority tasks found.".yellow
      end
    end

    def extract_priority_level(prompt)
      if prompt =~ /\b(high|medium|low)\s*-?\s*priority\b/i
        Regexp.last_match(1).downcase
      else
        "high" # Default to high priority
      end
    end

    def find_priority_tasks(priority)
      tasks = []
      RubyTodo::Notebook.all.each do |notebook|
        notebook.tasks.each do |task|
          next unless task_matches_priority?(task, priority)

          tasks << {
            task_id: task.id,
            title: task.title,
            status: task.status,
            notebook: notebook.name
          }
        end
      end
      tasks
    end

    def task_matches_priority?(task, priority)
      return false unless task.tags

      case priority
      when "high"
        task.tags.downcase.include?("high") || task.tags.downcase.include?("urgent")
      when "medium"
        task.tags.downcase.include?("medium") || task.tags.downcase.include?("normal")
      when "low"
        task.tags.downcase.include?("low")
      else
        false
      end
    end

    def display_tasks_by_priority(tasks, priority)
      say "\n#{priority.capitalize} Priority Tasks:".blue
      tasks.each do |task|
        status_color = case task[:status]
                       when "todo" then :yellow
                       when "in_progress" then :blue
                       when "done" then :green
                       else :white
                       end

        say "  [#{task[:notebook]}] Task #{task[:task_id]}: #{task[:title]}".send(status_color)
      end
    end
  end

  module TaskDeadlines
    private

    def handle_deadline_query(prompt)
      say "\nHandling deadline query" if options[:verbose]
      # rubocop:disable Layout/LineLength
      deadline_pattern = /\b(?:show|display|get|list)\s+(?:me\s+)?(?:the\s+)?(?:upcoming|due|overdue)\s+(?:tasks|deadlines)\b/
      # rubocop:enable Layout/LineLength
      if prompt =~ /#{deadline_pattern}/i
        display_deadline_tasks(prompt)
        return true
      end

      false
    end

    def display_deadline_tasks(prompt)
      deadline_type = extract_deadline_type(prompt)
      tasks = find_deadline_tasks(deadline_type)

      if tasks.any?
        display_tasks_by_deadline(tasks, deadline_type)
      else
        say "No #{deadline_type} tasks found.".yellow
      end
    end

    def extract_deadline_type(prompt)
      if prompt =~ /\b(upcoming|due|overdue)\b/i
        Regexp.last_match(1).downcase
      else
        "upcoming" # Default to upcoming
      end
    end

    def find_deadline_tasks(deadline_type)
      tasks = []
      RubyTodo::Notebook.all.each do |notebook|
        notebook.tasks.each do |task|
          next unless task_matches_deadline?(task, deadline_type)

          tasks << {
            task_id: task.id,
            title: task.title,
            status: task.status,
            notebook: notebook.name,
            deadline: task.deadline
          }
        end
      end
      tasks
    end

    def task_matches_deadline?(task, deadline_type)
      return false unless task.deadline

      case deadline_type
      when "upcoming"
        task.deadline > Time.now && task.deadline <= Time.now + (7 * 24 * 60 * 60) # 7 days
      when "due"
        task.deadline <= Time.now + (24 * 60 * 60) # 1 day
      when "overdue"
        task.deadline < Time.now
      else
        false
      end
    end

    def display_tasks_by_deadline(tasks, deadline_type)
      say "\n#{deadline_type.capitalize} Tasks:".blue
      tasks.each do |task|
        deadline_str = task[:deadline].strftime("%Y-%m-%d %H:%M")
        status_color = case task[:status]
                       when "todo" then :yellow
                       when "in_progress" then :blue
                       when "done" then :green
                       else :white
                       end

        say "  [#{task[:notebook]}] Task #{task[:task_id]}: " \
            "#{task[:title]} (Due: #{deadline_str})".send(status_color)
      end
    end
  end

  module TaskCreation
    private

    def handle_task_creation(prompt, prompt_lower)
      say "\n=== Detecting task creation request ===" if options[:verbose]

      title = extract_task_title(prompt)
      return false unless title

      notebook_name = determine_notebook_name(prompt_lower)
      return false unless notebook_name

      priority = determine_priority(prompt_lower)

      create_task(notebook_name, title, priority)
      true
    end

    def extract_task_title(prompt)
      # Try to extract title from quotes first
      title_match = prompt.match(/'([^']+)'|"([^"]+)"/)

      if title_match
        title_match[1] || title_match[2]
      else
        # If no quoted title found, try extracting from the prompt
        extract_title_from_text(prompt)
      end
    end

    def extract_title_from_text(prompt)
      potential_title = prompt
      phrases_to_remove = [
        "create a task", "create task", "add a task", "add task",
        "called", "named", "with", "priority", "high", "medium", "low",
        "in", "notebook"
      ]

      phrases_to_remove.each do |phrase|
        potential_title = potential_title.gsub(/#{phrase}/i, " ")
      end

      result = potential_title.strip
      result.empty? ? nil : result
    end

    def determine_notebook_name(prompt_lower)
      return nil unless Notebook.default_notebook

      notebook_name = Notebook.default_notebook.name

      # Try to extract a specific notebook name from the prompt
      Notebook.all.each do |notebook|
        if prompt_lower.include?(notebook.name.downcase)
          notebook_name = notebook.name
          break
        end
      end

      notebook_name
    end

    def determine_priority(prompt_lower)
      if prompt_lower.include?("high priority") || prompt_lower.match(/priority.*high/)
        "high"
      elsif prompt_lower.include?("medium priority") || prompt_lower.match(/priority.*medium/)
        "medium"
      elsif prompt_lower.include?("low priority") || prompt_lower.match(/priority.*low/)
        "low"
      end
    end

    def create_task(notebook_name, title, priority)
      say "\nCreating task in notebook: #{notebook_name}" if options[:verbose]
      cli_args = ["task:add", notebook_name, title]

      # Add priority if specified
      cli_args.push("--priority", priority) if priority

      RubyTodo::CLI.start(cli_args)

      # Create a simple explanation
      priority_text = priority ? " with #{priority} priority" : ""
      say "\nCreated task '#{title}'#{priority_text} in the #{notebook_name} notebook"
    end
  end

  module CommonQueryHandler
    include TaskStatistics
    include TaskPriority
    include TaskDeadlines
    include TaskCreation

    def handle_common_query(prompt)
      handle_statistics_query(prompt) ||
        handle_priority_query(prompt) ||
        handle_deadline_query(prompt)
    end

    private

    def high_priority_query?(prompt_lower)
      prompt_lower.include?("high priority") ||
        (prompt_lower.include?("priority") && prompt_lower.include?("high"))
    end

    def medium_priority_query?(prompt_lower)
      prompt_lower.include?("medium priority") ||
        (prompt_lower.include?("priority") && prompt_lower.include?("medium"))
    end

    def statistics_query?(prompt_lower)
      (prompt_lower.include?("statistics") || prompt_lower.include?("stats")) &&
        (prompt_lower.include?("notebook") || prompt_lower.include?("tasks"))
    end

    def status_tasks_query?(prompt_lower)
      statuses = { "todo" => "todo", "in progress" => "in_progress", "done" => "done", "archived" => "archived" }
      statuses.keys.any? { |status| prompt_lower.include?(status) }
    end

    def notebook_listing_query?(prompt_lower)
      prompt_lower.include?("list notebooks") ||
        prompt_lower.include?("show notebooks") ||
        prompt_lower.include?("display notebooks")
    end

    def handle_status_tasks(prompt_lower)
      say "\n=== Detecting status tasks request ===" if options[:verbose]

      statuses = { "todo" => "todo", "in progress" => "in_progress", "done" => "done", "archived" => "archived" }
      status = nil

      statuses.each do |name, value|
        if prompt_lower.include?(name)
          status = value
          break
        end
      end

      return false unless status

      tasks = find_tasks_by_status(status)
      display_tasks_by_status(tasks, status)
      true
    end

    def handle_notebook_listing(_prompt_lower)
      say "\n=== Detecting notebook listing request ===" if options[:verbose]

      notebooks = Notebook.all
      if notebooks.empty?
        say "No notebooks found.".yellow
        return true
      end

      say "\nNotebooks:".blue
      notebooks.each do |notebook|
        say "  #{notebook.name}".green
      end

      true
    end
  end
end
