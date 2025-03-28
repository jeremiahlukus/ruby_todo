# frozen_string_literal: true

require "thor"
require "json"
require "openai"
require "dotenv/load"

module RubyTodo
  module TaskSearch
    def pre_search_tasks(search_term)
      matching_tasks = []
      search_terms = [search_term, "#{search_term} org"]

      Notebook.all.each do |notebook|
        notebook.tasks.each do |task|
          next unless search_terms.any? do |term|
            task.title.downcase.include?(term.downcase) ||
            (task.description && task.description.downcase.include?(term.downcase)) ||
            (task.tags && task.tags.downcase.include?(term.downcase))
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

      if prompt.downcase.include?("barracua")
        say "Falling back to hardcoded 'barracua' search term" if options[:verbose]
        return "barracua"
      end

      say "Could not extract search term from prompt" if options[:verbose]
      nil
    end
  end

  module TaskManagement
    include TaskSearch

    def handle_barracua_tasks(prompt, context)
      if prompt.downcase.include?("barracua") || prompt.downcase.include?("migrating")
        say "Looking for barracua tasks directly" if options[:verbose]
        matching_tasks = pre_search_tasks("barracua")
        handle_matching_tasks(matching_tasks, context)
      elsif prompt.downcase.include?("move") && prompt.downcase.include?("task") ||
            prompt.downcase.include?("change") && prompt.downcase.include?("status")
        handle_task_movement(prompt, context)
      end
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

      say "Pre-searching for tasks matching: '#{search_term}'" if options[:verbose]
      matching_tasks = pre_search_tasks(search_term)
      handle_matching_tasks(matching_tasks, context)
    end

    def move_barracua_tasks_to_status(status)
      say "Special case: Moving barracua tasks to #{status}".green
      matching_tasks = find_barracua_tasks
      process_barracua_tasks(matching_tasks, status)
    end

    def find_barracua_tasks
      pre_search_tasks("barracua")
    end

    def process_barracua_tasks(matching_tasks, status)
      if matching_tasks && !matching_tasks.empty?
        display_tasks_to_move(matching_tasks)
        move_tasks(matching_tasks, status)
        say "\nMoved #{matching_tasks.size} barracua tasks to #{status}".green
      else
        say "No barracua tasks found to move".yellow
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
        cli = RubyTodo::CLI.new
        cli.move(task[:notebook], task[:task_id].to_s, status)
        say "Successfully moved task #{task[:task_id]}".green
      rescue StandardError => e
        say "Error moving task #{task[:task_id]}: #{e.message}".red
      end
    end
  end

  module OpenAIIntegration
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
      prompt = "You are a task management assistant. "
      prompt += "Your role is to help users manage their tasks and notebooks. "
      prompt += "You can move tasks between different statuses. "

      if context[:matching_tasks]&.any?
        prompt += "\nI found these tasks that might be relevant:\n"
        context[:matching_tasks].each do |task|
          task_info = format_task_info(task)
          prompt += "- #{task_info}\n"
        end
      end

      prompt += "\nPlease analyze the user's request and respond with a JSON object containing:"
      prompt += "\n- 'actions': an array of actions to take, where each action is an object with:"
      prompt += "\n  - 'type': the type of action (e.g., 'move_task')"
      prompt += "\n  - 'notebook': the notebook name"
      prompt += "\n  - 'task_id': the task ID"
      prompt += "\n  - 'status': the new status (for move_task actions)"
      prompt += "\n- 'explanation': a brief explanation of what you're doing"
      prompt
    end

    def format_task_info(task)
      "Task #{task[:task_id]} in notebook '#{task[:notebook]}': " \
        "#{task[:title]} (Status: #{task[:status]})"
    end

    def handle_openai_response(response)
      return nil unless response&.dig("choices", 0, "message", "content")

      content = response["choices"][0]["message"]["content"]
      say "\nAI Response:\n#{content}\n" if options[:verbose]

      begin
        JSON.parse(content)
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

    desc "ask [PROMPT]", "Ask the AI assistant to perform tasks using natural language"
    method_option :api_key, type: :string, desc: "OpenAI API key"
    method_option :verbose, type: :boolean, default: false, desc: "Show detailed response"
    def ask(*prompt_args)
      prompt = prompt_args.join(" ")
      validate_prompt(prompt)
      api_key = fetch_api_key
      context = build_context
      handle_barracua_tasks(prompt, context)
      response = query_openai(prompt, context, api_key)
      handle_response(response)
    end

    desc "configure", "Configure the AI assistant settings"
    def configure
      prompt = TTY::Prompt.new
      api_key = prompt.mask("Enter your OpenAI API key:")
      save_config("openai", api_key)
      say "Configuration saved successfully!".green
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
      return unless response && response["actions"]

      response["actions"].each do |action|
        case action["type"]
        when "move_task"
          handle_move_task_action(action)
        else
          say "Unknown action type: #{action["type"]}".yellow
        end
      end

      say "\n#{response["explanation"]}" if response["explanation"]
    end

    def handle_move_task_action(action)
      return unless action["notebook"] && action["task_id"] && action["status"]

      say "Moving task #{action["task_id"]} in notebook #{action["notebook"]} to #{action["status"]}".blue
      begin
        cli = RubyTodo::CLI.new
        cli.move(action["notebook"], action["task_id"].to_s, action["status"])
        say "Successfully moved task #{action["task_id"]}".green
      rescue StandardError => e
        say "Error moving task #{action["task_id"]}: #{e.message}".red
      end
    end
  end
end
