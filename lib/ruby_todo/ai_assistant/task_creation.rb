# frozen_string_literal: true

module RubyTodo
  module TaskCreation
    private

    def task_creation_query?(prompt_lower)
      (prompt_lower.include?("create") || prompt_lower.include?("add")) &&
        (prompt_lower.include?("task") || prompt_lower.include?("todo"))
    end

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
        extract_title_from_text(prompt)
      end
    end

    def extract_title_from_text(prompt)
      potential_title = prompt
                        .gsub(/(?:create|add)\s+(?:a\s+)?(?:new\s+)?(?:task|todo)/i, "")
                        .gsub(/(?:in|to)\s+(?:the\s+)?notebook/i, "")
                        .gsub(/(?:with|as)\s+(?:high|medium|low)\s+priority/i, "")
                        .strip

      return nil if potential_title.empty?

      potential_title
    end

    def determine_notebook_name(prompt_lower)
      return nil unless Notebook.default_notebook

      if prompt_lower =~ /(?:in|to)\s+(?:the\s+)?notebook\s+['"]?([^'"]+)['"]?/i
        notebook_name = Regexp.last_match(1).strip
        return notebook_name if Notebook.exists?(notebook_name)
      end

      Notebook.default_notebook.name
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

      notebook = Notebook.find_by_name(notebook_name)
      task = notebook.create_task(title: title)

      if priority
        task.update(tags: priority)
        say "Created task with #{priority} priority: #{title}".green
      else
        say "Created task: #{title}".green
      end

      task
    end
  end
end
