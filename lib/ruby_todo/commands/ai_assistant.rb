# frozen_string_literal: true

require "thor"
require "json"
require "openai"
require "dotenv/load"
require_relative "../ai_assistant/openai_integration"

module RubyTodo
  class AIAssistantCommand < Thor
    include OpenAIIntegration

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
      
      # Extract additional parameters if present
      description = nil
      priority = nil
      tags = nil
      due_date = nil
      
      # Look for --description parameter
      if title =~ /--description\s+"([^"]+)"/
        description = $1
        title = title.gsub(/\s*--description\s+"[^"]+"/, '')
      end
      
      # Look for --priority parameter
      if title =~ /--priority\s+(\w+)/
        priority = $1
        title = title.gsub(/\s*--priority\s+\w+/, '')
      end
      
      # Look for --tags parameter
      if title =~ /--tags\s+"([^"]+)"/
        tags = $1
        title = title.gsub(/\s*--tags\s+"[^"]+"/, '')
      end
      
      # Look for --due_date parameter
      if title =~ /--due_date\s+"([^"]+)"/
        due_date = $1
        title = title.gsub(/\s*--due_date\s+"[^"]+"/, '')
      end
      
      # Clean up any extra whitespace
      title = title.strip
      
      # Create the task with all parameters
      cli_args = ["task:add", notebook_name, title]
      cli_args.push("--description", description) if description
      cli_args.push("--priority", priority) if priority
      cli_args.push("--tags", tags) if tags
      cli_args.push("--due_date", due_date) if due_date
      
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
      
      # Get the notebook name
      notebook_name = parts[1] if parts.size > 1
      notebook = RubyTodo::Notebook.find_by(name: notebook_name)
      
      unless notebook
        say "Notebook '#{notebook_name}' not found".red
        return
      end

      tasks = notebook.tasks

      # Apply any filters from the command
      tasks = apply_task_filters(tasks, parts[2..])

      if tasks.empty?
        say "No tasks found in notebook '#{notebook_name}'".yellow
        return
      end

      # Prepare rows with wrapped text
      rows = tasks.map do |t|
        [
          t.id,
          wrap_text(t.title, 48),
          format_status(t.status),
          format_priority(t.priority),
          format_due_date(t.due_date),
          truncate_text(t.tags, 18),
          wrap_text(t.description, 28)
        ]
      end

      # Display the table with proper formatting
      puts format_table_with_wrapping(
        ["ID", "Title", "Status", "Priority", "Due Date", "Tags", "Description"],
        rows
      )
    end

    def apply_task_filters(tasks, args)
      return tasks if args.empty?

      args.each_with_index do |arg, i|
        case arg
        when "--status"
          tasks = tasks.where(status: args[i + 1]) if args[i + 1]
        when "--priority"
          tasks = tasks.where(priority: args[i + 1]) if args[i + 1]
        when "--tags"
          if args[i + 1]
            tag_filters = args[i + 1].split(",").map(&:strip)
            tasks = tasks.select { |t| t.tags && tag_filters.any? { |tag| t.tags.include?(tag) } }
          end
        end
      end

      tasks
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
      return "None" unless priority

      case priority
      when "high" then priority.red
      when "medium" then priority.yellow
      when "low" then priority.green
      else priority
      end
    end

    def format_due_date(date)
      return "No due date" unless date
      date.strftime("%Y-%m-%d %H:%M")
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

    def truncate_text(text, max_length = 50, ellipsis = "...")
      return "" unless text
      return text if text.length <= max_length

      text[0...(max_length - ellipsis.length)] + ellipsis
    end

    def wrap_text(text, width = 50)
      return "" unless text
      return text if text.length <= width

      text.gsub(/(.{1,#{width}})(\s+|$)/, "\\1\n").strip
    end

    def format_table_with_wrapping(headers, rows)
      table = TTY::Table.new(
        header: headers,
        rows: rows
      )

      table.render(:ascii, padding: [0, 1], width: 150, resize: true) do |renderer|
        renderer.border.separator = :each_row
        renderer.multiline = true
        
        # Configure column widths
        renderer.column_widths = [
          5,  # ID
          50, # Title
          12, # Status
          10, # Priority
          20, # Due Date
          20, # Tags
          30  # Description
        ]
      end
    end
  end
end
