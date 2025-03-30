# frozen_string_literal: true

require "thor"
require "json"
require "openai"
require "dotenv/load"
require_relative "../ai_assistant/openai_integration"

module RubyTodo
  class AIAssistantCommand < Thor
    include OpenAIIntegration

    desc "ask [PROMPT]", "Ask the AI assistant to perform tasks using natural language"
    method_option :api_key, type: :string, desc: "OpenAI API key"
    method_option :verbose, type: :boolean, default: false, desc: "Show detailed response"
    def ask(*prompt_args, **options)
      prompt = prompt_args.join(" ")
      validate_prompt(prompt)
      @options = options || {}
      say "\n=== Starting AI Assistant with prompt: '#{prompt}' ===" if @options[:verbose]

      process_ai_query(prompt)
    end

    desc "configure", "Configure the AI assistant settings"
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
      say "\nAPI key loaded successfully" if @options[:verbose]

      # Create a CLI instance for executing commands
      cli = RubyTodo::CLI.new

      # Special case for "add task to notebook with attributes"
      if (task_title_match = prompt.match(/add\s+(?:a\s+)?task\s+(?:titled|called|named)\s+["']([^"']+)["']\s+(?:to|in)\s+(\w+)/i))
        title = task_title_match[1]
        notebook_name = task_title_match[2]

        options = {}
        # Check for priority
        case prompt
        when /priority\s+high/i
          options[:priority] = "high"
        when /priority\s+medium/i
          options[:priority] = "medium"
        when /priority\s+low/i
          options[:priority] = "low"
        end

        # Check for tags
        if (tags_match = prompt.match(/tags?\s+(\w+)/i))
          options[:tags] = tags_match[1]
        end

        # Check for description
        if (desc_match = prompt.match(/description\s+["']([^"']+)["']/i))
          options[:description] = desc_match[1]
        end

        # Create the task using the extracted info
        args = ["task:add", notebook_name, title]
        options.each do |key, value|
          args << "--#{key}" << value
        end
        RubyTodo::CLI.start(args)
        return
      end

      # Check for various export task patterns
      if prompt.match?(/export.*tasks.*done.*last\s+\d+\s+weeks?/i) ||
         prompt.match?(/export.*done.*tasks.*last\s+\d+\s+weeks?/i) ||
         prompt.match?(/export.*all.*done.*tasks/i) ||
         prompt.match?(/export.*tasks.*with.*done.*status/i) ||
         prompt.match?(/export.*tasks.*to.*csv/i) ||
         prompt.match?(/export.*tasks.*to.*json/i) ||
         prompt.match?(/export.*tasks.*to\s+[^\.]+\.[json|cv]/i) ||
         prompt.match?(/save.*done.*tasks.*to.*file/i)
        handle_export_recent_done_tasks(prompt)
        return
      # Check for notebook creation requests
      elsif (match = prompt.match(/(?:create|add|make|new)\s+(?:a\s+)?notebook\s+(?:called\s+|named\s+)?["']?([^"'\s]+(?:\s+[^"'\s]+)*)["']?/i))
        notebook_name = match[1]
        cli.notebook_create(notebook_name)
        return
      # Check for notebook listing requests
      elsif prompt.match?(/list.*notebooks/i) ||
            prompt.match?(/show.*notebooks/i) ||
            prompt.match?(/get.*notebooks/i) ||
            prompt.match?(/display.*notebooks/i)
        cli.notebook_list
        return
      # Check for task creation with additional attributes (priority, tags, etc.)
      elsif (match = prompt.match(/(?:create|add|make|new)\s+(?:a\s+)?task\s+(?:called\s+|named\s+|titled\s+)?["']([^"']+)["']\s+(?:in|to|for)\s+(?:the\s+)?(?:notebook\s+)?["']?([^"'\s]+)["']?(?:\s+notebook)?(?:\s+with\s+|\s+having\s+|\s+and\s+|\s+that\s+has\s+)?/i))
        title = match[1]
        notebook_name = match[2].sub(/\s+notebook$/i, "")

        # Get the rest of the prompt to extract attributes
        attributes_part = prompt.split(/\s+(?:with|having|and|that has)\s+/).last

        options = {}

        # Parse additional attributes
        if attributes_part
          # Check for priority
          if (priority_match = attributes_part.match(/(?:priority|importance)\s+(high|medium|low)/i))
            options[:priority] = priority_match[1].downcase
          end

          # Check for tags
          if (tags_match = attributes_part.match(/tags?\s+["']?([^"',]+)["']?/i) || attributes_part.match(/tags?\s+([^\s,]+)/i))
            options[:tags] = tags_match[1]
          end

          # Check for due date
          if (due_date_match = attributes_part.match(/due(?:\s+date)?\s+["']?([^"']+)["']?/i))
            options[:due_date] = due_date_match[1]
          end

          # Check for description
          if (desc_match = attributes_part.match(/description\s+["']([^"']+)["']/i))
            options[:description] = desc_match[1]
          end
        end

        # Call task:add with the extracted attributes
        args = ["task:add", notebook_name, title]
        options.each do |key, value|
          args << "--#{key}" << value
        end

        RubyTodo::CLI.start(args)
        return
      # Check for task listing requests for a specific notebook
      elsif (match = prompt.match(/(?:list|show|get|display).*tasks.*(?:in|from|of)\s+(?:the\s+)?(?:notebook\s+)?["']?([^"'\s]+(?:\s+[^"'\s]+)*)["']?(?:\s+notebook)?/i))
        notebook_name = match[1].sub(/\s+notebook$/i, "")
        cli.task_list(notebook_name)
        return
      # Check for general task listing without a notebook specified
      elsif prompt.match?(/(?:list|show|get|display).*(?:all)?\s*tasks/i)
        # Get the default notebook or first available
        notebooks = RubyTodo::Notebook.all
        if notebooks.any?
          default_notebook = notebooks.first
          cli.task_list(default_notebook.name)
        else
          say "No notebooks found. Create a notebook first.".yellow
        end
        return
      # Check for task movement requests (changing status)
      elsif (match = prompt.match(/(?:move|change|set|mark)\s+task\s+(?:with\s+id\s+)?(\d+)\s+(?:in|from|of)\s+(?:the\s+)?(?:notebook\s+)?["']?([^"'\s]+(?:\s+[^"'\s]+)*)["']?(?:\s+notebook)?\s+(?:to|as)\s+(todo|in_progress|done|archived)/i))
        task_id = match[1]
        notebook_name = match[2].sub(/\s+notebook$/i, "")
        status = match[3].downcase
        cli.task_move(notebook_name, task_id, status)
        return
      # Check for task deletion requests
      elsif (match = prompt.match(/(?:delete|remove)\s+task\s+(?:with\s+id\s+)?(\d+)\s+(?:in|from|of)\s+(?:the\s+)?(?:notebook\s+)?["']?([^"'\s]+(?:\s+[^"'\s]+)*)["']?(?:\s+notebook)?/i))
        task_id = match[1]
        notebook_name = match[2].sub(/\s+notebook$/i, "")
        cli.task_delete(notebook_name, task_id)
        return
      # Check for task details view requests
      elsif (match = prompt.match(/(?:show|view|get|display)\s+(?:details\s+(?:of|for)\s+)?task\s+(?:with\s+id\s+)?(\d+)\s+(?:in|from|of)\s+(?:the\s+)?(?:notebook\s+)?["']?([^"'\s]+(?:\s+[^"'\s]+)*)["']?(?:\s+notebook)?/i))
        task_id = match[1]
        notebook_name = match[2].sub(/\s+notebook$/i, "")
        cli.task_show(notebook_name, task_id)
        return
      end

      context = build_context
      say "\nInitial context built" if @options[:verbose]

      # Get AI response for commands and explanation
      say "\n=== Querying OpenAI ===" if @options[:verbose]
      response = query_openai(prompt, context, api_key)
      say "\nOpenAI Response received" if @options[:verbose]

      # Execute actions based on response
      execute_actions(response)
    end

    def execute_actions(response)
      return unless response && response["commands"]

      say "\n=== Executing Commands ===" if @options[:verbose]
      response["commands"].each do |cmd|
        execute_command(cmd)
      end

      # Display the explanation from the AI
      if response["explanation"]
        say "\n=== AI Explanation ===" if @options[:verbose]
        say "\n#{response["explanation"]}"
      end
    end

    def execute_command(cmd)
      return unless cmd

      say "\nExecuting command: #{cmd}" if @options[:verbose]

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
      # Match notebook name and title in quotes, followed by optional parameters
      if cmd =~ /task:add\s+"([^"]+)"\s+"([^"]+)"(?:\s+(.*))?/
        notebook_name = Regexp.last_match(1)
        title = Regexp.last_match(2)
        params = Regexp.last_match(3)

        cli_args = ["task:add", notebook_name, title]

        # Extract optional parameters
        if params
          # Description
          if params =~ /--description\s+"([^"]+)"/
            cli_args.push("--description", Regexp.last_match(1))
          end

          # Priority
          if params =~ /--priority\s+(\w+)/
            cli_args.push("--priority", Regexp.last_match(1))
          end

          # Tags
          if params =~ /--tags\s+"([^"]+)"/
            cli_args.push("--tags", Regexp.last_match(1))
          end

          # Due date
          if params =~ /--due_date\s+"([^"]+)"/
            cli_args.push("--due_date", Regexp.last_match(1))
          end
        end

        RubyTodo::CLI.start(cli_args)
      else
        say "Invalid task:add command format".red
      end
    end

    def execute_task_move_command(cmd)
      # Match notebook name in quotes, task ID, and status
      if cmd =~ /task:move\s+"([^"]+)"\s+(\d+)\s+(\w+)/
        notebook_name = Regexp.last_match(1)
        task_id = Regexp.last_match(2)
        status = Regexp.last_match(3)
        cli_args = ["task:move", notebook_name, task_id, status]
        RubyTodo::CLI.start(cli_args)
      # Also try matching without quotes
      elsif cmd =~ /task:move\s+([^\s"]+)\s+(\d+)\s+(\w+)/
        notebook_name = Regexp.last_match(1)
        task_id = Regexp.last_match(2)
        status = Regexp.last_match(3)
        cli_args = ["task:move", notebook_name, task_id, status]
        RubyTodo::CLI.start(cli_args)
      else
        say "Invalid task:move command format".red
      end
    end

    def execute_task_list_command(cmd)
      # Match notebook name in quotes
      if cmd =~ /task:list\s+"([^"]+)"(?:\s+(.*))?/
        notebook_name = Regexp.last_match(1)
        filters = Regexp.last_match(2)
        cli_args = ["task:list", notebook_name]

        # Add any filters that were specified
        cli_args.concat(filters.split(/\s+/)) if filters

        RubyTodo::CLI.start(cli_args)
      else
        say "Invalid task:list command format".red
      end
    end

    def execute_task_delete_command(cmd)
      # Match notebook name in quotes and task ID
      if cmd =~ /task:delete\s+"([^"]+)"\s+(\d+)/
        notebook_name = Regexp.last_match(1)
        task_id = Regexp.last_match(2)
        cli_args = ["task:delete", notebook_name, task_id]
        RubyTodo::CLI.start(cli_args)
      else
        say "Invalid task:delete command format".red
      end
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
      @options[:api_key] || ENV["OPENAI_API_KEY"] || load_api_key_from_config
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

    def handle_export_recent_done_tasks(prompt)
      # Parse the number of weeks from the prompt
      weeks = prompt.match(/last\s+(\d+)\s+weeks?/i) ? ::Regexp.last_match(1).to_i : 2 # Default to 2 weeks if not specified

      # Allow specifying output format
      format = prompt.match?(/csv/i) ? "csv" : "json"

      # Check if a custom filename is specified
      custom_filename = nil
      if prompt.match(/to\s+(?:file\s+|filename\s+)?["']?([^"']+)["']?/i)
        custom_filename = ::Regexp.last_match(1).strip
      end

      # Get current time
      current_time = Time.now

      # Calculate the time from X weeks ago
      weeks_ago = current_time - (weeks * 7 * 24 * 60 * 60)

      # Format filename with date and format
      if custom_filename
        # Ensure the filename has the correct extension
        unless custom_filename.end_with?(".#{format}")
          custom_filename = "#{custom_filename}.#{format}"
        end
        filename = custom_filename
      else
        filename = "done_tasks_export_#{current_time.strftime("%Y%m%d")}.#{format}"
      end

      say "Exporting tasks marked as 'done' from the last #{weeks} weeks..."

      # Collect all notebooks
      notebooks = RubyTodo::Notebook.all

      # Filter for done tasks within the time period
      exported_data = {
        "notebooks" => notebooks.map do |notebook|
          {
            "name" => notebook.name,
            "created_at" => notebook.created_at,
            "updated_at" => notebook.updated_at,
            "tasks" => notebook.tasks.select do |task|
              task.status == "done" &&
                task.updated_at &&
                task.updated_at >= weeks_ago
            end.map { |task| task_to_hash(task) }
          }
        end
      }

      # Filter out notebooks with no matching tasks
      exported_data["notebooks"].select! { |nb| nb["tasks"].any? }

      if exported_data["notebooks"].empty?
        say "No 'done' tasks found from the last #{weeks} weeks."
        return
      end

      # Count tasks
      total_tasks = exported_data["notebooks"].sum { |nb| nb["tasks"].size }

      # Export based on format
      case format
      when "json"
        File.write(filename, JSON.pretty_generate(exported_data))
      when "csv"
        require "csv"
        CSV.open(filename, "wb") do |csv|
          # Add headers - Note: "Completed At" is the date when the task was moved to the "done" status
          csv << ["Notebook", "ID", "Title", "Description", "Tags", "Priority", "Created At", "Completed At"]

          # Add data rows
          exported_data["notebooks"].each do |notebook|
            notebook["tasks"].each do |task|
              # Handle tags that might be arrays or comma-separated strings
              tag_value = if task["tags"].nil?
                            ""
                          elsif task["tags"].is_a?(Array)
                            task["tags"].join(",")
                          else
                            task["tags"].to_s
                          end

              csv << [
                notebook["name"],
                task["id"] || "N/A",
                task["title"],
                task["description"] || "",
                tag_value,
                task["priority"] || "normal",
                task["created_at"],
                task["updated_at"]
              ]
            end
          end
        end
      end

      say "Successfully exported #{total_tasks} 'done' tasks from the last #{weeks} weeks to #{filename}."
    end

    def task_to_hash(task)
      {
        "id" => task.id,
        "title" => task.title,
        "description" => task.description,
        "status" => task.status,
        "priority" => task.priority,
        "tags" => task.tags,
        "due_date" => task.due_date&.iso8601,
        "created_at" => task.created_at&.iso8601,
        "updated_at" => task.updated_at&.iso8601
      }
    end
  end
end
