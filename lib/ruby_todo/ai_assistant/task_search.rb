# frozen_string_literal: true

module RubyTodo
  module TaskSearchPatterns
    private

    def status_of_pattern
      @status_of_pattern ||= build_status_pattern
    end

    def move_pattern
      @move_pattern ||= build_move_pattern
    end

    def mark_pattern
      @mark_pattern ||= /^mark\s+(?:all\s+)?(?:tasks?\s+)?(?:about\s+|related\s+to\s+|concerning\s+)?/i
    end

    def build_status_pattern
      pattern_parts = []
      pattern_parts << "^(?:the\\s+)?"
      pattern_parts << "status\\s+of\\s+"
      pattern_parts << "(?:the\\s+)?"
      pattern_parts << "(?:tasks?\\s+)?"
      pattern_parts << "(?:about\\s+|related\\s+to\\s+|concerning\\s+)?"
      Regexp.new(pattern_parts.join, Regexp::IGNORECASE)
    end

    def build_move_pattern
      pattern_parts = []
      pattern_parts << "^(?:move|change|update|set)\\s+"
      pattern_parts << "(?:the\\s+)?"
      pattern_parts << "(?:status\\s+of\\s+)?"
      pattern_parts << "(?:all\\s+)?"
      pattern_parts << "(?:tasks?\\s+)?"
      pattern_parts << "(?:about\\s+|related\\s+to\\s+|concerning\\s+)?"
      Regexp.new(pattern_parts.join, Regexp::IGNORECASE)
    end
  end

  module TaskSearchTermCleaner
    private

    def clean_search_term(search_term)
      return "*" if search_term.nil? || search_term.strip.empty?

      # Remove common task-related words and patterns
      cleaned = remove_task_related_words(search_term)
      cleaned = remove_status_related_words(cleaned)
      cleaned = remove_action_words(cleaned)
      cleaned = clean_special_patterns(cleaned)

      cleaned.strip
    end

    def remove_task_related_words(term)
      term.gsub(/\b(?:task|tasks|about|related to|concerning)\b/i, "")
    end

    def remove_status_related_words(term)
      term.gsub(/\b(?:status|state)\b/i, "")
    end

    def remove_action_words(term)
      term.gsub(/\b(?:move|change|update|set|mark)\b/i, "")
    end

    def clean_special_patterns(term)
      # Handle "related to X" pattern
      if term =~ /related\s+to\s+(.+)/i
        term = Regexp.last_match(1)
      end

      # Clean up any remaining special characters and extra whitespace
      term.gsub(/[^\w\s-]/, " ")
          .gsub(/\s+/, " ")
          .strip
    end
  end

  module TaskSearchMatcher
    private

    def task_matches_any_term?(task, search_terms)
      return true if search_terms == ["*"]

      matching_terms = []
      search_terms.each do |term|
        next if term.nil? || term.strip.empty?

        term = term.strip.downcase
        matches = check_task_match(task, term)
        matching_terms << term if matches
      end

      handle_compound_query_matches(task, search_terms, matching_terms)
    end

    def check_task_match(task, term)
      matches = false
      matches ||= task[:task_id].to_s == term
      matches ||= task[:title].downcase.include?(term)
      matches ||= task[:description]&.downcase&.include?(term)
      matches ||= task[:tags]&.downcase&.include?(term)
      matches ||= task[:status].downcase == term
      matches ||= task[:notebook].downcase.include?(term)
      matches
    end

    def handle_compound_query_matches(task, search_terms, matching_terms)
      return true if matching_terms.any? && search_terms.size == 1

      handle_or_query(task, search_terms, matching_terms) ||
        handle_and_query(search_terms, matching_terms) ||
        handle_related_to_query(task, search_terms) ||
        matching_terms.size == search_terms.size
    end

    def handle_or_query(task, search_terms, _matching_terms)
      return false unless or_query?

      matching_terms_for_or = find_matching_terms_for_or(task, search_terms)
      return false unless matching_terms_for_or.any?

      log_or_query_match(matching_terms_for_or)
      true
    end

    def or_query?
      Thread.current[:original_prompt] &&
        Thread.current[:original_prompt].downcase =~ /\bor\b/i
    end

    def find_matching_terms_for_or(task, search_terms)
      matching_terms = []
      search_terms.each do |term|
        if check_task_match(task, term)
          matching_terms << term
        elsif options[:verbose]
          say "    Term '#{term}' does not match in OR compound query"
        end
      end
      matching_terms
    end

    def log_or_query_match(matching_terms)
      return unless options[:verbose]

      say "    Found match for OR condition with term(s): " \
          "#{matching_terms.join(", ")}"
    end

    def handle_and_query(search_terms, matching_terms)
      return false unless and_query?

      matching_terms.size == search_terms.size
    end

    def and_query?
      Thread.current[:original_prompt] &&
        Thread.current[:original_prompt].downcase =~ /\band\b/i
    end

    def handle_related_to_query(task, _search_terms)
      return false unless related_to_query?

      related_terms = extract_related_terms
      return false unless related_terms

      matching_terms = find_matching_terms_for_related(task, related_terms)
      return false unless matching_terms.any?

      log_related_to_match(matching_terms)
      true
    end

    def related_to_query?
      Thread.current[:original_prompt] =~ /related\s+to\s+(.+)/i
    end

    def extract_related_terms
      return unless Thread.current[:original_prompt] =~ /related\s+to\s+(.+)/i

      Regexp.last_match(1).split(/\s+or\s+|\s+and\s+/).map(&:strip)
    end

    def find_matching_terms_for_related(task, related_terms)
      matching_terms = []
      related_terms.each do |term|
        if check_task_match(task, term)
          matching_terms << term
        elsif options[:verbose]
          say "    Term '#{term}' does not match in 'related to' query"
        end
      end
      matching_terms
    end

    def log_related_to_match(matching_terms)
      return unless options[:verbose]

      say "    Found match for 'related to' with term(s): " \
          "#{matching_terms.join(", ")}"
    end
  end

  module TaskSearchCore
    include TaskSearchPatterns
    include TaskSearchTermCleaner
    include TaskSearchMatcher

    def pre_search_tasks(search_term, prompt = nil)
      Thread.current[:original_prompt] = prompt if prompt

      if search_term == "*"
        say "\nSearching for all tasks" if options[:verbose]
        return find_all_tasks
      end

      search_terms = extract_search_terms(search_term)
      find_tasks_by_search_terms(search_terms)
    end

    private

    def find_all_tasks
      # Start with the default notebook if it exists
      notebooks = if RubyTodo::Notebook.default_notebook
                   [RubyTodo::Notebook.default_notebook]
                 else
                   RubyTodo::Notebook.all
                 end

      tasks = []
      notebooks.each do |notebook|
        notebook.tasks.each do |task|
          tasks << {
            notebook: notebook.name,
            task_id: task.id,
            title: task.title,
            status: task.status
          }
        end
      end
      tasks
    end

    def find_tasks_by_search_terms(search_terms)
      matching_tasks = []

      RubyTodo::Notebook.all.each do |notebook|
        notebook.tasks.each do |task|
          task_info = {
            task_id: task.id,
            title: task.title,
            status: task.status,
            notebook: notebook.name
          }

          if task_matches_any_term?(task_info, search_terms)
            matching_tasks << task_info
          end
        end
      end

      matching_tasks
    end

    def extract_search_terms(search_term)
      return [] if search_term.nil?

      search_term = clean_search_term(search_term)

      # Handle special cases
      return ["*"] if search_term == "*" || search_term =~ /\ball\b|\bevery\b/i

      # Extract terms from compound queries
      terms = if search_term =~ /\band\b|\bor\b/i
                search_term.split(/\s+and\s+|\s+or\s+/).map(&:strip)
              else
                [search_term]
              end

      terms.reject(&:empty?)
    end
  end

  module TaskSearch
    include TaskSearchCore

    def extract_search_term(prompt)
      prompt = prompt.downcase.strip
      say "\nExtracting search term from prompt: '#{prompt}'" if options[:verbose]

      # Handle special cases first
      return "*" if prompt =~ /\b(?:all|every)\s+(?:tasks?|things?)\b/i
      return "*" if prompt =~ /\bmove\s+(?:all|everything)\b/i

      # Try to extract terms from different patterns
      extracted_terms = extract_terms_from_patterns(prompt)

      # If no pattern matched, try to extract terms from the remaining text
      if extracted_terms.nil?
        extracted_terms = clean_remaining_text(prompt)
      end

      clean_search_term(extracted_terms)
    end

    private

    def extract_terms_from_patterns(prompt)
      extract_related_to_terms(prompt) ||
        extract_status_terms(prompt) ||
        extract_move_terms(prompt) ||
        extract_mark_terms(prompt)
    end

    def extract_related_to_terms(prompt)
      return unless prompt =~ /related\s+to\s+(.+?)(?:\s+(?:to|into|as)\s+|$)/i

      terms = Regexp.last_match(1)
      say "Found 'related to' pattern with terms: '#{terms}'" if options[:verbose]
      terms
    end

    def extract_status_terms(prompt)
      return unless prompt =~ /#{status_of_pattern}(.+?)(?:\s+(?:to|into|as)\s+|$)/i

      terms = Regexp.last_match(1)
      say "Found status pattern with terms: '#{terms}'" if options[:verbose]
      terms
    end

    def extract_move_terms(prompt)
      # Handle task ID pattern first
      if prompt =~ /\btask\s+(\d+)\s+in\s+([^"']+?)(?:\s+(?:to|into|as)\s+|$)/i
        task_id = Regexp.last_match(1)
        say "Found task ID pattern with ID: '#{task_id}'" if options[:verbose]
        return task_id
      end

      # Handle other move patterns
      return unless prompt =~ /#{move_pattern}(.+?)(?:\s+(?:to|into|as)\s+|$)/i

      terms = Regexp.last_match(1)
      say "Found move pattern with terms: '#{terms}'" if options[:verbose]
      terms
    end

    def extract_mark_terms(prompt)
      return unless prompt =~ /#{mark_pattern}(.+?)(?:\s+(?:to|into|as)\s+|$)/i

      terms = Regexp.last_match(1)
      say "Found mark pattern with terms: '#{terms}'" if options[:verbose]
      terms
    end

    def clean_remaining_text(prompt)
      prompt.gsub(/(?:move|change|update|set|mark)\s+(?:to|into|as)\s+\w+/, "")
            .gsub(/\b(?:status|state)\b/i, "")
            .strip
    end
  end
end
