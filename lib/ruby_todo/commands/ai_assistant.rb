# frozen_string_literal: true

require "thor"
require "json"
require "openai"
require "dotenv/load"

require_relative "../ai_assistant/task_search"
require_relative "../ai_assistant/task_management"
require_relative "../ai_assistant/openai_integration"
require_relative "../ai_assistant/configuration_management"
require_relative "../ai_assistant/common_query_handler"

module RubyTodo
  class AIAssistantCommand < Thor
    include TaskManagement
    include OpenAIIntegration
    include ConfigurationManagement
    include CommonQueryHandler

    desc "ai:ask [PROMPT]", "Ask the AI assistant to perform tasks using natural language"
    method_option :api_key, type: :string, desc: "OpenAI API key"
    method_option :verbose, type: :boolean, default: false, desc: "Show detailed response"
    def ask(*prompt_args)
      prompt = prompt_args.join(" ")
      validate_prompt(prompt)
      say "\n=== Starting AI Assistant with prompt: '#{prompt}' ===" if options[:verbose]

      # Direct handling for common queries
      return if handle_common_query(prompt)

      process_ai_query(prompt)
    end

    desc "ai:configure", "Configure the AI assistant settings"
    def configure
      prompt = TTY::Prompt.new
      api_key = prompt.mask("Enter your OpenAI API key:")
      save_config("openai", api_key)
      say "Configuration saved successfully!".green
    end

    def self.banner(command, _namespace = nil, _subcommand: false)
      "#{basename} #{command.name}"
    end

    def self.exit_on_failure?
      true
    end

    private

    def process_ai_query(prompt)
      api_key = fetch_api_key
      say "\nAPI key loaded successfully" if options[:verbose]

      context = build_context
      say "\nInitial context built" if options[:verbose]

      # Process based on query type
      process_query_by_type(prompt, context)

      # Get AI response for commands and explanation
      say "\n=== Querying OpenAI ===" if options[:verbose]
      response = query_openai(prompt, context, api_key)
      say "\nOpenAI Response received" if options[:verbose]

      # Execute actions based on response
      execute_actions(response, context)
    end

    def process_query_by_type(prompt, context)
      if should_handle_task_movement?(prompt)
        # Handle task movement and build context
        say "\n=== Processing Task Movement Request ===" if options[:verbose]
        handle_task_request(prompt, context)
      elsif options[:verbose]
        say "\n=== Processing Non-Movement Request ==="
      end
    end

    def execute_actions(response, context)
      # If we have tasks to move, do it now
      if context[:matching_tasks]&.any? && context[:target_status]
        say "\n=== Moving Tasks ===" if options[:verbose]
        move_tasks_to_status(context[:matching_tasks], context[:target_status])
      end

      # Execute any additional commands from the AI
      if response && response["commands"]
        say "\n=== Executing Additional Commands ===" if options[:verbose]
        execute_commands(response)
      end

      # Display the explanation from the AI
      if response && response["explanation"]
        say "\n=== AI Explanation ===" if options[:verbose]
        say "\n#{response["explanation"]}"
      end
    end

    def validate_prompt(prompt)
      return if prompt && !prompt.empty?

      say "Please provide a prompt for the AI assistant".red
      raise ArgumentError, "Empty prompt"
    end

    def fetch_api_key
      api_key = options[:api_key] || ENV["OPENAI_API_KEY"] || load_api_key_from_config
      return api_key if api_key

      say "No API key found. Please provide an API key using --api-key or set OPENAI_API_KEY environment variable".red
      raise ArgumentError, "No API key found"
    end

    def build_context
      { matching_tasks: [] }
    end

    def execute_commands(response)
      return unless response["commands"].is_a?(Array)

      response["commands"].each do |command|
        process_command(command)
      end
    end

    def process_command(command)
      say "\nExecuting command: #{command}".blue if options[:verbose]

      begin
        # Skip if empty or nil
        return if command.nil? || command.strip.empty?

        # Ensure command starts with ruby_todo
        return unless command.start_with?("ruby_todo")

        # Process and execute the command
        process_ruby_todo_command(command)
      rescue StandardError => e
        say "Error executing command: #{e.message}".red
        say e.backtrace.join("\n").red if options[:verbose]
      end
    end

    def process_ruby_todo_command(command)
      # Remove the ruby_todo prefix
      cmd_without_prefix = command.sub(/^ruby_todo\s+/, "")
      say "\nCommand without prefix: '#{cmd_without_prefix}'".blue if options[:verbose]

      # Convert underscores to colons for all task commands
      if cmd_without_prefix =~ /^task_\w+/
        cmd_without_prefix = cmd_without_prefix.sub(/^task_(\w+)/, 'task:\1')
        say "\nConverted underscores to colons: '#{cmd_without_prefix}'".blue if options[:verbose]
      end

      # Convert underscores to colons for notebook commands
      if cmd_without_prefix =~ /^notebook_\w+/
        cmd_without_prefix = cmd_without_prefix.sub(/^notebook_(\w+)/, 'notebook:\1')
        say "\nConverted underscores to colons: '#{cmd_without_prefix}'".blue if options[:verbose]
      end

      # Convert underscores to colons for template commands
      if cmd_without_prefix =~ /^template_\w+/
        cmd_without_prefix = cmd_without_prefix.sub(/^template_(\w+)/, 'template:\1')
        say "\nConverted underscores to colons: '#{cmd_without_prefix}'".blue if options[:verbose]
      end

      # Process different command types
      if cmd_without_prefix.start_with?("task:list")
        execute_task_list_command(cmd_without_prefix)
      elsif cmd_without_prefix.start_with?("task:search")
        execute_task_search_command(cmd_without_prefix)
      elsif cmd_without_prefix.start_with?("task:move")
        execute_task_move_command(cmd_without_prefix)
      else
        execute_other_command(cmd_without_prefix)
      end
    end

    def execute_task_list_command(cmd_without_prefix)
      parts = cmd_without_prefix.split(/\s+/)
      say "\nSplit task:list command into parts: #{parts.inspect}".blue if options[:verbose]

      if parts.size >= 2
        execute_task_list_with_notebook(parts)
      elsif Notebook.default_notebook
        execute_task_list_with_default_notebook(parts)
      else
        say "\nNo notebook specified for task:list command".yellow
      end
    end

    def execute_task_list_with_notebook(parts)
      notebook_name = parts[1]
      # Extract any options
      options_args = []
      parts[2..].each do |part|
        options_args << part if part.start_with?("--")
      end

      # Execute the task list command with the notebook name and any options
      cli_args = ["task:list", notebook_name] + options_args
      say "\nRunning CLI with args: #{cli_args.inspect}".blue if options[:verbose]
      RubyTodo::CLI.start(cli_args)
    end

    def execute_task_list_with_default_notebook(parts)
      cli_args = ["task:list", Notebook.default_notebook.name]
      if parts.size > 1 && parts[1].start_with?("--")
        cli_args << parts[1]
      end
      say "\nUsing default notebook for task:list with args: #{cli_args.inspect}".blue if options[:verbose]
      RubyTodo::CLI.start(cli_args)
    end

    def execute_task_search_command(cmd_without_prefix)
      parts = cmd_without_prefix.split(/\s+/, 2) # Split into command and search term

      if parts.size >= 2
        # Pass the entire search term as a single argument, not individual words
        cli_args = ["task:search", parts[1]]
        say "\nRunning CLI with args: #{cli_args.inspect}".blue if options[:verbose]
        RubyTodo::CLI.start(cli_args)
      else
        say "\nNo search term provided for task:search command".yellow
      end
    end

    def execute_task_move_command(cmd_without_prefix)
      parts = cmd_without_prefix.split(/\s+/)

      # Need at least task:move NOTEBOOK TASK_ID STATUS
      if parts.size >= 4
        notebook_name = parts[1]
        task_id = parts[2]
        status = parts[3]

        cli_args = ["task:move", notebook_name, task_id, status]
        say "\nRunning CLI with args: #{cli_args.inspect}".blue if options[:verbose]
        RubyTodo::CLI.start(cli_args)
      else
        say "\nInvalid task:move command format. Need NOTEBOOK, TASK_ID, and STATUS".yellow
      end
    end

    def execute_other_command(cmd_without_prefix)
      # Process all other commands
      cli_args = cmd_without_prefix.split(/\s+/)
      say "\nRunning CLI with args: #{cli_args.inspect}".blue if options[:verbose]
      RubyTodo::CLI.start(cli_args)
    end

    def handle_common_query(prompt)
      prompt_lower = prompt.downcase

      # Check for different types of common queries
      return handle_task_creation(prompt, prompt_lower) if task_creation_query?(prompt_lower)
      return handle_priority_tasks(prompt_lower, "high") if high_priority_query?(prompt_lower)
      return handle_priority_tasks(prompt_lower, "medium") if medium_priority_query?(prompt_lower)
      return handle_statistics(prompt_lower) if statistics_query?(prompt_lower)
      return handle_status_tasks(prompt_lower) if status_tasks_query?(prompt_lower)
      return handle_notebook_listing(prompt_lower) if notebook_listing_query?(prompt_lower)

      # Not a common query
      false
    end

    def task_creation_query?(prompt_lower)
      (prompt_lower.include?("create") || prompt_lower.include?("add")) &&
        (prompt_lower.include?("task") || prompt_lower.include?("todo"))
    end

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

      statuses.keys.any? do |name|
        prompt_lower.include?("#{name} tasks") || prompt_lower.include?("tasks in #{name}")
      end
    end

    def notebook_listing_query?(prompt_lower)
      prompt_lower.include?("list notebooks") ||
        prompt_lower.include?("show notebooks") ||
        prompt_lower.include?("all notebooks")
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

    def handle_priority_tasks(_prompt_lower, priority)
      say "\n=== Detecting #{priority} priority task request ===" if options[:verbose]

      return false unless Notebook.default_notebook

      say "\nListing #{priority} priority tasks from default notebook" if options[:verbose]
      RubyTodo::CLI.start(["task:list", Notebook.default_notebook.name, "--priority", priority])

      # Create a simple explanation
      say "\nListing all #{priority} priority tasks in the #{Notebook.default_notebook.name} notebook"
      true
    end

    def handle_statistics(prompt_lower)
      say "\n=== Detecting statistics request ===" if options[:verbose]

      notebook_name = determine_notebook_name(prompt_lower)

      if notebook_name
        say "\nShowing statistics for notebook: #{notebook_name}" if options[:verbose]
        RubyTodo::CLI.start(["stats", notebook_name])
        say "\nDisplaying statistics for the #{notebook_name} notebook"
      else
        # Show global stats if no default notebook
        say "\nShowing global statistics" if options[:verbose]
        RubyTodo::CLI.start(["stats"])
        say "\nDisplaying global statistics for all notebooks"
      end

      true
    end

    def handle_status_tasks(prompt_lower)
      statuses = { "todo" => "todo", "in progress" => "in_progress", "done" => "done", "archived" => "archived" }

      statuses.each do |name, value|
        next unless prompt_lower.include?("#{name} tasks") || prompt_lower.include?("tasks in #{name}")

        say "\n=== Detecting #{name} task listing request ===" if options[:verbose]

        return false unless Notebook.default_notebook

        say "\nListing #{name} tasks from default notebook" if options[:verbose]
        RubyTodo::CLI.start(["task:list", Notebook.default_notebook.name, "--status", value])

        # Create a simple explanation
        say "\nListing all #{name} tasks in the #{Notebook.default_notebook.name} notebook"
        return true
      end

      false
    end

    def handle_notebook_listing(_prompt_lower)
      say "\n=== Detecting notebook listing request ===" if options[:verbose]
      RubyTodo::CLI.start(["notebook:list"])

      # Create a simple explanation
      say "\nListing all available notebooks"
      true
    end
  end
end
