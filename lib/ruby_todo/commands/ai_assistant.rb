# frozen_string_literal: true

require "thor"
require "json"
require "openai"
require "dotenv/load"

module RubyTodo
  module TaskSearch
    def pre_search_tasks(search_term)
      matching_tasks = []
      search_terms = search_term.split(/\s+(?:and|&)\s+/).map(&:strip)

      Notebook.all.each do |notebook|
        notebook.tasks.each do |task|
          next unless search_terms.any? do |term|
            matches_task?(task, term)
          end

          matching_tasks << {
            notebook: notebook.name,
            task_id: task.id,
            title: task.title,
            status: task.status
          }
        end
      end
      matching_tasks
    end

    def matches_task?(task, term)
      term = term.downcase
      task.title.downcase.include?(term) ||
        (task.description && task.description.downcase.include?(term)) ||
        (task.tags && task.tags.downcase.include?(term))
    end

    def extract_search_term(prompt)
      say "Extracting search term from prompt: '#{prompt}'" if options[:verbose]

      # Split the regex pattern for readability
      move_pattern = /\b(?:move|change|set)\b/
      task_pattern = /\b(?:tasks?|items?)\b/
      about_pattern = /\b(?:about|related to|containing|with)\b/
      target_pattern = /\b(?:to|into|as)\b/

      # Combine patterns
      full_pattern = /#{move_pattern}.*?#{task_pattern}.*?#{about_pattern}\s+(.+?)\s+#{target_pattern}/i

      if prompt =~ full_pattern
        term = Regexp.last_match(1).strip
        say "Found search term using primary pattern: '#{term}'" if options[:verbose]
        return term
      end

      if prompt =~ /\babout\s+([^"]*?)\s+to\b/i
        term = Regexp.last_match(1).strip
        say "Found search term using 'about X to' pattern: '#{term}'" if options[:verbose]
        return term
      end

      extract_search_term_from_words(prompt)
    end

    def extract_search_term_from_words(prompt)
      words = prompt.split(/\s+/)
      potential_topics = words.reject do |word|
        %w[move change set task tasks all about to status the in into of as].include?(word.downcase)
      end

      if potential_topics.any?
        if potential_topics.size > 1 &&
           words.join(" ") =~ /#{potential_topics[0]}\s+#{potential_topics[1]}/i
          term = "#{potential_topics[0]} #{potential_topics[1]}"
          say "Found multi-word search term: '#{term}'" if options[:verbose]
          return term
        else
          say "Found single-word search term: '#{potential_topics[0]}'" if options[:verbose]
          return potential_topics[0]
        end
      end

      say "Could not extract search term from prompt" if options[:verbose]
      nil
    end
  end

  module TaskManagement
    include TaskSearch

    def handle_task_request(prompt, context)
      if should_handle_task_movement?(prompt)
        handle_task_movement(prompt, context)
      end
    end

    def should_handle_task_movement?(prompt)
      prompt = prompt.downcase
      (prompt.include?("move") && prompt.include?("task")) ||
        (prompt.include?("change") && prompt.include?("status")) ||
        (prompt.include?("set") && prompt.include?("status"))
    end

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

    def handle_task_movement(prompt, context)
      search_term = extract_search_term(prompt)
      return unless search_term

      say "Searching for tasks matching: '#{search_term}'" if options[:verbose]
      matching_tasks = pre_search_tasks(search_term)

      if matching_tasks.any?
        target_status = extract_target_status(prompt)
        if target_status
          handle_matching_tasks(matching_tasks, context)
          move_tasks_to_status(matching_tasks, target_status)
        else
          say "Could not determine target status from prompt".yellow
        end
      else
        say "No tasks found matching: '#{search_term}'".yellow
      end
    end

    def extract_target_status(prompt)
      prompt = prompt.downcase
      status_map = {
        "in_progress" => "in_progress",
        "in progress" => "in_progress",
        "todo" => "todo",
        "done" => "done",
        "archived" => "archived"
      }

      status_map.each do |key, value|
        return value if prompt.include?(key)
      end

      nil
    end

    def move_tasks_to_status(tasks, status)
      if tasks && !tasks.empty?
        display_tasks_to_move(tasks)
        move_tasks(tasks, status)
        say "\nMoved #{tasks.size} tasks to #{status}".green
      else
        say "No tasks found to move".yellow
      end
    end

    def display_tasks_to_move(tasks)
      return unless options[:verbose]

      say "Found #{tasks.size} tasks to move:".blue
      tasks.each do |task|
        say "  - Task #{task[:task_id]}: #{task[:title]}".blue
      end
    end

    def move_tasks(tasks, status)
      tasks.each do |task|
        move_single_task(task, status)
      end
    end

    def move_single_task(task, status)
      say "\nMoving task #{task[:task_id]} in notebook #{task[:notebook]} to #{status}".blue if options[:verbose]
      begin
        notebook = RubyTodo::Notebook.find_by(name: task[:notebook])
        task_obj = notebook.tasks.find(task[:task_id])
        task_obj.update!(status: status)
        task_obj.reload
        say "Successfully moved task #{task[:task_id]}".green
      rescue StandardError => e
        say "Error moving task #{task[:task_id]}: #{e.message}".red
      end
    end
  end

  module OpenAIDocumentation
    CLI_DOCUMENTATION = <<~DOCS
      Available ruby_todo commands:

      Task Management:
      1. List tasks:
         ruby_todo task:list [NOTEBOOK]
         - Lists all tasks in a notebook or all notebooks if no name provided
         - To filter by status: ruby_todo task:list [NOTEBOOK] --status STATUS
         - Example: ruby_todo task:list protectors --status in_progress

      2. Search tasks:
         ruby_todo task:search SEARCH_TERM
         - Searches for tasks containing the search term

      3. Show task details:
         ruby_todo task:show NOTEBOOK TASK_ID
         - Shows detailed information about a specific task

      4. Add task:
         ruby_todo task:add [NOTEBOOK] [TITLE]
         - Add a new task to a notebook
         - Interactive prompts for title, description, priority, due date, and tags

      5. Edit task:
         ruby_todo task:edit [NOTEBOOK] [TASK_ID]
         - Edit an existing task's details

      6. Delete task:
         ruby_todo task:delete [NOTEBOOK] [TASK_ID]
         - Delete a task from a notebook

      7. Move task:
         ruby_todo task:move [NOTEBOOK] [TASK_ID] [STATUS]
         - Move a task to a different status
         - STATUS can be: todo, in_progress, done, archived

      Notebook Management:
      8. List notebooks:
         ruby_todo notebook:list
         - List all notebooks

      9. Create notebook:
         ruby_todo notebook:create NAME
         - Create a new notebook

      Template Management:
      10. List templates:
          ruby_todo template:list
          - List all templates

      11. Show template:
          ruby_todo template:show NAME
          - Show details of a specific template

      12. Create template:
          ruby_todo template:create NAME --title TITLE
          - Create a new task template

      13. Delete template:
          ruby_todo template:delete NAME
          - Delete a template

      14. Use template:
          ruby_todo template:use NAME NOTEBOOK
          - Create a task from a template in the specified notebook

      Other Commands:
      15. Export tasks:
          ruby_todo export [NOTEBOOK] [FILENAME]
          - Export tasks from a notebook to a JSON file

      16. Import tasks:
          ruby_todo import [FILENAME]
          - Import tasks from a JSON or CSV file

      17. Show statistics:
          ruby_todo stats [NOTEBOOK]
          - Show statistics for a notebook or all notebooks

      18. Initialize:
          ruby_todo init
          - Initialize a new todo list

      Note: All commands use colons (e.g., 'task:list', 'notebook:list').
      Available statuses: todo, in_progress, done, archived
    DOCS
  end

  module OpenAIPromptBuilder
    private

    def build_messages(prompt, context)
      messages = [
        { role: "system", content: build_system_prompt(context) },
        { role: "user", content: prompt }
      ]

      say "\nSystem prompt:\n#{messages.first[:content]}\n" if options[:verbose]
      say "\nUser prompt:\n#{prompt}\n" if options[:verbose]

      messages
    end

    def build_system_prompt(context)
      prompt = "You are a task management assistant that generates ruby_todo CLI commands. "
      prompt += "Your role is to analyze user requests and generate the appropriate ruby_todo command. "
      prompt += "\n\nHere are the available commands and their usage:\n"
      prompt += CLI_DOCUMENTATION
      prompt += "\nBased on the user's request, generate a command that follows these formats exactly."

      if context[:matching_tasks]&.any?
        prompt += "\n\nRelevant tasks found in the system:\n"
        context[:matching_tasks].each do |task|
          task_info = format_task_info(task)
          prompt += "- #{task_info}\n"
        end
      end

      prompt += "\nPlease analyze the user's request and respond with a JSON object containing:"
      prompt += "\n- 'command': the ruby_todo command to execute"
      prompt += "\n- 'explanation': a brief explanation of what the command will do"
      prompt
    end

    def format_task_info(task)
      "Task #{task[:task_id]} in notebook '#{task[:notebook]}': " \
        "#{task[:title]} (Status: #{task[:status]})"
    end
  end

  module OpenAIIntegration
    include OpenAIDocumentation
    include OpenAIPromptBuilder

    def query_openai(prompt, context, api_key)
      client = OpenAI::Client.new(access_token: api_key)
      messages = build_messages(prompt, context)
      say "Sending request to OpenAI..." if options[:verbose]

      response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: messages,
          temperature: 0.7,
          max_tokens: 500
        }
      )

      handle_openai_response(response)
    end

    private

    def handle_openai_response(response)
      return nil unless response&.dig("choices", 0, "message", "content")

      content = response["choices"][0]["message"]["content"]
      say "\nAI Response:\n#{content}\n" if options[:verbose]

      begin
        # Remove markdown formatting if present
        json_content = content.gsub(/```(?:json)?\n(.*?)\n```/m, '\1')
        JSON.parse(json_content)
      rescue JSON::ParserError => e
        say "Error parsing AI response: #{e.message}".red if options[:verbose]
        nil
      end
    end
  end

  module ConfigurationManagement
    def load_api_key_from_config
      config = load_config
      config["openai"]
    end

    def load_config
      return {} unless File.exist?(config_file)

      YAML.load_file(config_file) || {}
    end

    def save_config(key, value)
      config = load_config
      config[key] = value
      FileUtils.mkdir_p(File.dirname(config_file))
      File.write(config_file, config.to_yaml)
    end

    def config_file
      File.join(Dir.home, ".config", "ruby_todo", "config.yml")
    end
  end

  class AIAssistantCommand < Thor
    include TaskManagement
    include OpenAIIntegration
    include ConfigurationManagement

    desc "ai:ask [PROMPT]", "Ask the AI assistant to perform tasks using natural language"
    method_option :api_key, type: :string, desc: "OpenAI API key"
    method_option :verbose, type: :boolean, default: false, desc: "Show detailed response"
    def ask(*prompt_args)
      prompt = prompt_args.join(" ")
      validate_prompt(prompt)
      api_key = fetch_api_key
      context = build_context
      handle_task_request(prompt, context)
      response = query_openai(prompt, context, api_key)
      handle_response(response)
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

    def handle_response(response)
      return unless response

      if response["command"]
        execute_command(response["command"])
      end

      say "\n#{response["explanation"]}" if response["explanation"]
    end

    def execute_command(command)
      say "\nExecuting command: #{command}".blue if options[:verbose]
      begin
        # Split the command into parts
        parts = command.split(/\s+(?=(?:[^"]*"[^"]*")*[^"]*$)/)

        # Get the base command and subcommand
        base_cmd = parts[0]
        subcmd = parts[1]&.tr(":", "_")

        # Reconstruct the command with the correct format
        if subcmd && base_cmd == "ruby_todo"
          parts[1] = subcmd
          command = parts.join(" ")
        end

        # Execute the command
        success = system(command)
        raise "Command failed" unless success

        true
      rescue StandardError => e
        say "Error executing command: #{e.message}".red
        nil
      end
    end
  end
end
