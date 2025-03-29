# frozen_string_literal: true

require "thor"
require "json"
require "openai"
require "dotenv/load"

module RubyTodo
  class AIAssistantCommand < Thor
    desc "ai:ask [PROMPT]", "Ask the AI assistant to perform tasks using natural language"
    method_option :api_key, type: :string, desc: "OpenAI API key"
    method_option :verbose, type: :boolean, default: false, desc: "Show detailed response"
    def ask(*prompt_args)
      prompt = prompt_args.join(" ")
      validate_prompt(prompt)
      say "\n=== Starting AI Assistant with prompt: '#{prompt}' ===" if options[:verbose]

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

      # Get AI response for commands and explanation
      say "\n=== Querying OpenAI ===" if options[:verbose]
      response = query_openai(prompt, context, api_key)
      say "\nOpenAI Response received" if options[:verbose]

      # Execute actions based on response
      execute_actions(response)
    end

    def execute_actions(response)
      return unless response && response["commands"]

      say "\n=== Executing Commands ===" if options[:verbose]
      response["commands"].each do |cmd|
        execute_command(cmd)
      end

      # Display the explanation from the AI
      if response["explanation"]
        say "\n=== AI Explanation ===" if options[:verbose]
        say "\n#{response["explanation"]}"
      end
    end

    def execute_command(cmd)
      return unless cmd

      say "\nExecuting command: #{cmd}" if options[:verbose]
      
      # Split the command into parts
      parts = cmd.split(/\s+/)
      command_type = parts[0]

      case command_type
      when "task:add"
        execute_task_add_command(cmd)
      when "task:move"
        execute_task_move_command(cmd)
      when "task:list"
        execute_task_list_command(cmd)
      when "task:delete"
        execute_task_delete_command(cmd)
      when "notebook:create"
        execute_notebook_create_command(cmd)
      when "notebook:list"
        execute_notebook_list_command(cmd)
      when "stats"
        execute_stats_command(cmd)
      else
        execute_other_command(cmd)
      end
    end

    def execute_task_add_command(cmd)
      parts = cmd.split(/\s+/, 4)
      return unless parts.size >= 4

      notebook_name = parts[1]
      title = parts[3]
      cli_args = ["task:add", notebook_name, title]
      RubyTodo::CLI.start(cli_args)
    end

    def execute_task_move_command(cmd)
      parts = cmd.split(/\s+/)
      return unless parts.size >= 4

      notebook_name = parts[1]
      task_id = parts[2]
      status = parts[3]
      cli_args = ["task:move", notebook_name, task_id, status]
      RubyTodo::CLI.start(cli_args)
    end

    def execute_task_list_command(cmd)
      parts = cmd.split(/\s+/)
      cli_args = ["task:list"] + parts[1..]
      RubyTodo::CLI.start(cli_args)
    end

    def execute_task_delete_command(cmd)
      parts = cmd.split(/\s+/)
      return unless parts.size >= 3

      notebook_name = parts[1]
      task_id = parts[2]
      cli_args = ["task:delete", notebook_name, task_id]
      RubyTodo::CLI.start(cli_args)
    end

    def execute_notebook_create_command(cmd)
      parts = cmd.split(/\s+/)
      return unless parts.size >= 2

      notebook_name = parts[1]
      cli_args = ["notebook:create", notebook_name]
      RubyTodo::CLI.start(cli_args)
    end

    def execute_notebook_list_command(_cmd)
      RubyTodo::CLI.start(["notebook:list"])
    end

    def execute_stats_command(cmd)
      parts = cmd.split(/\s+/)
      cli_args = ["stats"] + parts[1..]
      RubyTodo::CLI.start(cli_args)
    end

    def execute_other_command(cmd)
      cli_args = cmd.split(/\s+/)
      RubyTodo::CLI.start(cli_args)
    end

    def validate_prompt(prompt)
      return if prompt && !prompt.empty?

      say "Please provide a prompt for the AI assistant".red
      raise ArgumentError, "Empty prompt"
    end

    def fetch_api_key
      options[:api_key] || ENV["OPENAI_API_KEY"] || load_api_key_from_config
    end

    def load_api_key_from_config
      config_file = File.expand_path("~/.ruby_todo/ai_config.json")
      return nil unless File.exist?(config_file)

      config = JSON.parse(File.read(config_file))
      config["api_key"]
    end

    def save_config(key, value)
      config_dir = File.expand_path("~/.ruby_todo")
      FileUtils.mkdir_p(config_dir)
      config_file = File.join(config_dir, "ai_config.json")
      
      config = if File.exist?(config_file)
                JSON.parse(File.read(config_file))
              else
                {}
              end

      config[key] = value
      File.write(config_file, JSON.pretty_generate(config))
    end

    def build_context
      {
        notebooks: RubyTodo::Notebook.all.map do |notebook|
          {
            name: notebook.name,
            tasks: notebook.tasks.map do |task|
              {
                id: task.id,
                title: task.title,
                status: task.status,
                tags: task.tags,
                description: task.description,
                due_date: task.due_date
              }
            end
          }
        end
      }
    end
  end
end
