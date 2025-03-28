# frozen_string_literal: true

module RubyTodo
  module TaskStatusMapping
    private

    def status_map
      @status_map ||= {
        "in_progress" => "in_progress",
        "in progress" => "in_progress",
        "inprogress" => "in_progress",
        "in porgress" => "in_progress", # Common misspelling
        "in pogress" => "in_progress",  # Another misspelling
        "in prog" => "in_progress",     # Abbreviation
        "in-progress" => "in_progress", # With hyphen
        "n prgrs" => "in_progress",     # Very abbreviated
        "todo" => "todo",
        "to do" => "todo",
        "to-do" => "todo",
        "done" => "done",
        "complete" => "done",
        "completed" => "done",
        "finish" => "done",
        "finished" => "done",
        "archived" => "archived",
        "arch" => "archived",           # Abbreviation
        "pending" => "todo"
      }.freeze
    end

    def find_status_in_map(potential_status, pattern_name)
      status_map.each_key do |key|
        if potential_status.include?(key)
          say "Found status '#{key}' in #{pattern_name}, mapping to '#{status_map[key]}'" if options[:verbose]
          return status_map[key]
        end
      end

      # If we didn't find a match in the status map, log the attempted matches
      if options[:verbose]
        say "No direct status match found in status_map. Attempted matches:"
        status_map.each_key do |key|
          say "  - Checking '#{key}' against '#{potential_status}'"
        end
      end

      nil
    end

    def find_status_in_prompt(prompt)
      # Try exact matches first anywhere in the prompt
      status_map.each_key do |key|
        if prompt.include?(key)
          say "Found status '#{key}' mapping to '#{status_map[key]}'" if options[:verbose]
          return status_map[key]
        end
      end
      nil
    end
  end

  module TaskStatusExtraction
    include TaskStatusMapping

    def extract_target_status(prompt)
      prompt = prompt.downcase.strip
      say "\n=== Extracting Target Status ===" if options[:verbose]
      say "Looking for status in: '#{prompt}'" if options[:verbose]

      # Try each pattern matcher in sequence
      status = extract_status_from_related_to_pattern(prompt) ||
               extract_status_from_set_status_pattern(prompt) ||
               extract_status_from_to_pattern(prompt) ||
               extract_status_from_as_pattern(prompt) ||
               extract_status_from_general_pattern(prompt)

      say "No status found in the prompt" if options[:verbose] && status.nil?
      status
    end

    private

    def extract_status_from_related_to_pattern(prompt)
      return unless prompt =~ /\b(?:related\s+to|about)\b.*\bto\s+([a-z_\s]+)\b/i

      potential_status = Regexp.last_match(1).strip
      say "Found potential status in 'related to' pattern: '#{potential_status}'" if options[:verbose]
      say "Full match: #{Regexp.last_match(0)}" if options[:verbose]
      say "Captured group: #{Regexp.last_match(1)}" if options[:verbose]

      find_status_in_map(potential_status, "'related to' pattern")
    end

    def extract_status_from_set_status_pattern(prompt)
      return unless prompt =~ /\bset\s+(?:the\s+)?status\s+of\s+(?:tasks|task).*\bto\s+([a-z_\s]+)\b/i

      potential_status = Regexp.last_match(1).strip
      say "Found potential status in 'set status of tasks' pattern: '#{potential_status}'" if options[:verbose]
      say "Full match: #{Regexp.last_match(0)}" if options[:verbose]
      say "Captured group: #{Regexp.last_match(1)}" if options[:verbose]

      find_status_in_map(potential_status, "'set status of tasks' pattern")
    end

    def extract_status_from_to_pattern(prompt)
      return unless prompt =~ /\b(?:to|into|as)\s+([a-z_\s]+)\b/i

      potential_status = Regexp.last_match(1).strip
      say "Found potential status indicator: '#{potential_status}'" if options[:verbose]
      say "Full match: #{Regexp.last_match(0)}" if options[:verbose]
      say "Captured group: #{Regexp.last_match(1)}" if options[:verbose]

      status = find_status_in_map(potential_status, "status indicator")
      return status if status

      # If we have a potential status but no exact match, try fuzzy matching
      if potential_status =~ /\bin\s*p|\bn\s*p/i
        say "Found fuzzy match for 'in_progress' in potential status: '#{potential_status}'" if options[:verbose]
        return "in_progress"
      end

      nil
    end

    def extract_status_from_as_pattern(prompt)
      return unless prompt =~ /\bas\s+([a-z_\s]+)\b/i

      potential_status = Regexp.last_match(1).strip
      say "Found 'as X' pattern with potential status: '#{potential_status}'" if options[:verbose]

      find_status_in_map(potential_status, "'as X' pattern")
    end

    def extract_status_from_general_pattern(prompt)
      find_status_in_prompt(prompt) ||
        find_status_from_fuzzy_match(prompt) ||
        find_status_from_special_chars(prompt) ||
        find_status_from_final_check(prompt)
    end

    def find_status_from_fuzzy_match(prompt)
      # Advanced fuzzy matching for progress with typos
      if prompt =~ /\bin\s*p[o|r][r|o]?g(?:r?e?s{1,2})\b/i
        say "Found advanced fuzzy match for 'in_progress'" if options[:verbose]
        return "in_progress"
      end

      # Even more flexible matching for progress
      if prompt =~ /\bn\s*p[r|o]?g|\bin\s*p[r|o]?g|\bn\s*p|\bin\s*p/i
        say "Found flexible fuzzy match for 'in_progress'" if options[:verbose]
        return "in_progress"
      end
      nil
    end

    def find_status_from_special_chars(prompt)
      return nil unless prompt.end_with?(" in", " to", "\"", "'", "\n")

      clean_prompt = prompt.gsub(/["'\n]/, " ").strip
      say "Cleaned prompt for status detection: '#{clean_prompt}'" if options[:verbose]

      case clean_prompt
      when /prog|porg|p[o|r]g/i
        say "Inferring in_progress from context" if options[:verbose]
        "in_progress"
      when /\btodo\b|\bto do\b|pending/i
        say "Inferring todo from context" if options[:verbose]
        "todo"
      when /\bdone\b|complete/i
        say "Inferring done from context" if options[:verbose]
        "done"
      end
    end

    def find_status_from_final_check(prompt)
      # Final attempt to match "in progress" pattern
      if prompt =~ /\b(?:to|into|as)\s+(?:in\s+progress|in-progress|inprogress)\b/i
        say "Found 'in progress' pattern in final check" if options[:verbose]
        return "in_progress"
      end
      nil
    end
  end

  module TaskMovementDetection
    def should_handle_task_movement?(prompt)
      prompt = prompt.downcase
      say "\nChecking if should handle task movement for prompt: '#{prompt}'" if options[:verbose]

      result = (prompt.include?("move") && !prompt.include?("task")) ||
               (prompt.include?("move") && prompt.include?("task")) ||
               (prompt.include?("change") && prompt.include?("status")) ||
               (prompt.include?("change") && prompt.include?("to")) ||
               (prompt.include?("set") && prompt.include?("status")) ||
               (prompt =~ /\bset\s+(?:the\s+)?status\b/) ||
               (prompt =~ /\bupdate\s+(?:the\s+)?(?:task|tasks).+\bto\s+\w+\b/) ||
               (prompt =~ /\bmark\s+(?:all\s+)?(?:the\s+)?(?:task|tasks)?.+\b(?:as|to)\s+\w+\b/)

      say "Should handle task movement: #{result}" if options[:verbose]
      result
    end
  end

  module TaskProcessing
    def handle_matching_tasks(matching_tasks, context)
      return unless matching_tasks && !matching_tasks.empty?

      context[:matching_tasks] = matching_tasks
      return unless options[:verbose]

      say "Found #{matching_tasks.size} matching tasks:".blue
      matching_tasks.each do |task|
        say "  - Notebook: #{task[:notebook]}, ID: #{task[:task_id]}, " \
            "Title: #{task[:title]}, Status: #{task[:status]}".blue
      end
    end

    def process_search_term(search_term, prompt, context)
      say "\nSearching for tasks matching: '#{search_term}'" if options[:verbose]
      say "Current context: #{context.inspect}" if options[:verbose]

      matching_tasks = pre_search_tasks(search_term, prompt)
      say "Pre-search returned #{matching_tasks&.size || 0} tasks" if options[:verbose]

      if matching_tasks&.any?
        process_matching_tasks(matching_tasks, prompt, context, search_term)
      else
        say "\nNo tasks found matching: '#{search_term}'".yellow
        say "Context at failure: #{context.inspect}" if options[:verbose]
        context[:matching_tasks] = []
      end
    end

    def process_matching_tasks(matching_tasks, prompt, context, search_term)
      target_status = extract_target_status(prompt)
      say "\nProcessing matching tasks with target status: '#{target_status}'" if options[:verbose]

      if target_status
        handle_matching_tasks(matching_tasks, context)
        context[:target_status] = target_status
        context[:search_term] = search_term
        say "\nFound #{matching_tasks.size} tasks to move to #{target_status}" if options[:verbose]
        say "Updated context: #{context.inspect}" if options[:verbose]
      else
        say "\nCould not determine target status from prompt".yellow
        say "Current context: #{context.inspect}" if options[:verbose]
      end
    end
  end

  module TaskStatusUpdate
    def move_tasks_to_status(tasks, status)
      if tasks && !tasks.empty?
        display_tasks_to_move(tasks)
        move_tasks(tasks, status)
      else
        say "\nNo tasks to move".yellow
      end
    end

    private

    def display_tasks_to_move(tasks)
      return unless options[:verbose]

      say "\nMoving tasks:".blue
      tasks.each do |task|
        say "  - Task #{task[:task_id]} in notebook #{task[:notebook]}".blue
      end
    end

    def move_tasks(tasks, status)
      tasks.each do |task|
        move_single_task(task, status)
      end
    end

    def move_single_task(task, status)
      say "\nMoving task #{task[:task_id]} in notebook #{task[:notebook]} to #{status}".blue if options[:verbose]

      # Try to find the notebook, first by name, then use default if not found
      notebook = RubyTodo::Notebook.find_by(name: task[:notebook]) || RubyTodo::Notebook.default_notebook
      unless notebook
        say "No notebook found (neither specified nor default)".red
        return
      end

      task_record = notebook.tasks.find_by(id: task[:task_id])
      return say "Task #{task[:task_id]} not found in notebook '#{notebook.name}'".red unless task_record

      if task_record.update(status: status)
        say "Moved task #{task[:task_id]} to #{status}".green
      else
        say "Error moving task #{task[:task_id]}: #{task_record.errors.full_messages.join(", ")}".red
      end
    end
  end

  module TaskManagement
    include TaskSearch
    include TaskStatusExtraction
    include TaskMovementDetection
    include TaskProcessing
    include TaskStatusUpdate

    def handle_task_request(prompt, context)
      say "\nHandling task request for prompt: '#{prompt}'" if options[:verbose]

      return unless should_handle_task_movement?(prompt)

      say "Task movement request confirmed" if options[:verbose]

      search_term = extract_search_term(prompt)
      say "Extracted search term: '#{search_term}'" if options[:verbose]

      # Extract target status early to ensure we have it
      target_status = extract_target_status(prompt)
      say "Early status extraction result: '#{target_status}'" if options[:verbose]

      if search_term
        process_search_term(search_term, prompt, context)

        # If we have a target status but it wasn't set in context, set it now
        if target_status && !context[:target_status]
          say "Setting target status from early extraction: '#{target_status}'" if options[:verbose]
          context[:target_status] = target_status
        end
      end
    end
  end
end
