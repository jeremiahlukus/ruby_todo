# frozen_string_literal: true

require "thor"
require "json"
require "openai"
require "dotenv/load"

module RubyTodo
  class AIAssistantCommand < Thor
    desc "ask [PROMPT]", "Ask the AI assistant to perform tasks using natural language"
    method_option :api_key, type: :string, desc: "OpenAI API key"
    method_option :verbose, type: :boolean, default: false, desc: "Show detailed response"
    def ask(*prompt_args)
      prompt = prompt_args.join(" ")
      unless prompt && !prompt.empty?
        say "Please provide a prompt for the AI assistant".red
        return
      end

      # Get API key from options, env var, or config file
      api_key = options[:api_key] || ENV["OPENAI_API_KEY"] || load_api_key_from_config
      unless api_key
        say "No API key found. Please provide an API key using --api-key or set OPENAI_API_KEY environment variable".red
        return
      end

      # Set up context for the AI
      context = build_context

      response = query_openai(prompt, context, api_key)

      if response[:error]
        say "Error: #{response[:error]}".red
        return
      end

      # Parse the AI's response for potential actions
      parse_and_execute_actions(response[:content])

      # Print the AI's response if verbose mode
      if options[:verbose]
        say "\nAI Assistant Response:".blue
        say response[:content]
      end
    end

    desc "configure", "Configure the AI assistant settings"
    def configure
      prompt = TTY::Prompt.new
      api_key = prompt.mask("Enter your OpenAI API key:")
      save_config("openai", api_key)
      say "Configuration saved successfully!".green
    end

    private

    def build_context
      # Build a context object with information about the current state of the app
      notebooks = Notebook.all.map do |notebook|
        {
          id: notebook.id,
          name: notebook.name,
          task_count: notebook.tasks.count,
          todo_count: notebook.tasks.todo.count,
          in_progress_count: notebook.tasks.in_progress.count,
          done_count: notebook.tasks.done.count,
          archived_count: notebook.tasks.archived.count
        }
      end

      {
        notebooks: notebooks,
        commands: {
          notebook_commands: %w[create list],
          task_commands: %w[add list show edit delete move search],
          export_commands: %w[export import],
          template_commands: %w[create list show use delete]
        },
        app_version: RubyTodo::VERSION
      }
    end

    def query_openai(prompt, context, api_key)
      client = OpenAI::Client.new(access_token: api_key)
      system_message = build_system_message(context)
      make_openai_request(client, system_message, prompt)
    end

    def build_system_message(context)
      <<~SYSTEM
        You are an AI assistant for Ruby Todo, a command-line task management application.

        Application Information:
        #{JSON.pretty_generate(context)}

        Your job is to help the user manage their tasks through natural language.
        You can create tasks, move tasks between statuses, and more.

        IMPORTANT FORMATTING REQUIREMENTS:
        - Due dates must be in "YYYY-MM-DD HH:MM" format (e.g., "2024-04-10 14:00")
        - Valid priority values are ONLY: "high", "medium", or "low" (lowercase)
        - Valid status values are ONLY: "todo", "in_progress", "done", "archived" (lowercase)
        - If you're unsure about any values, omit them rather than guessing

        When the user asks you to perform an action, generate a response in this JSON format:
        {
          "explanation": "Brief explanation of what you're doing",
          "actions": [
            {"type": "create_task", "notebook": "Work", "title": "Task title", "description": "Task description", "priority": "high", "tags": "tag1,tag2", "due_date": "2024-04-10 14:00"},
            {"type": "move_task", "notebook": "Work", "task_id": 1, "status": "in_progress"},
            {"type": "create_notebook", "name": "Personal"},
            {"type": "generate_import_json", "notebook": "Work", "tasks": [{...task data...}]}
          ]
        }

        Action types:
        - create_task: Create a new task in a notebook (requires notebook, title; optional: description, priority, tags, due_date)
        - move_task: Move a task to a different status (requires notebook, task_id, status)
        - create_notebook: Create a new notebook (requires name)
        - generate_import_json: Generate JSON for importing tasks (requires notebook, tasks array)
        - list_tasks: List tasks in a notebook (requires notebook; optional: status, priority)
        - search_tasks: Search for tasks (requires query; optional: notebook)

        EXTREMELY IMPORTANT:
        1. Always respond with raw JSON only
        2. DO NOT use markdown code blocks (like ```json)
        3. DO NOT include any explanatory text before or after the JSON
        4. The response must be parseable as JSON

        Always validate all fields according to the requirements before including them in your response.
      SYSTEM
    end

    def make_openai_request(client, system_message, prompt)
      response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            { role: "system", content: system_message },
            { role: "user", content: prompt }
          ],
          max_tokens: 1024
        }
      )
      { content: response.dig("choices", 0, "message", "content") }
    rescue StandardError => e
      { error: e.message }
    end

    def parse_and_execute_actions(response)
      cleaned_response = response.gsub(/```(?:json)?\s*/, "").gsub(/```\s*$/, "")

      data = JSON.parse(cleaned_response)

      say data["explanation"].green if data["explanation"]

      if data["actions"] && data["actions"].is_a?(Array)
        data["actions"].each do |action|
          execute_action(action)
        end
      else
        say "No actions found in response".yellow
      end
    rescue JSON::ParserError => e
      say "Couldn't parse AI response: #{e.message}".red
      say "Response starts with: #{response[0..100]}..." if options[:verbose]
      say "Full response: #{response}" if options[:verbose]
    end

    def execute_action(action)
      case action["type"]
      when "create_task"
        create_task(action)
      when "move_task"
        move_task(action)
      when "create_notebook"
        create_notebook(action)
      when "generate_import_json"
        generate_import_json(action)
      when "list_tasks"
        list_tasks(action)
      when "search_tasks"
        search_tasks(action)
      else
        say "Unknown action type: #{action["type"]}".yellow
      end
    end

    def create_task(action)
      unless action["notebook"] && action["title"]
        say "Missing required fields for create_task".red
        return
      end

      notebook = Notebook.find_by(name: action["notebook"])
      unless notebook
        say "Notebook '#{action["notebook"]}' not found".red
        return
      end

      due_date = parse_task_due_date(action["due_date"])
      priority = validate_task_priority(action["priority"])

      task = Task.create(
        notebook: notebook,
        title: action["title"],
        description: action["description"],
        due_date: due_date,
        priority: priority,
        tags: action["tags"],
        status: "todo"
      )

      if task.valid?
        say "Added task: #{action["title"]}".green
      else
        say "Error creating task: #{task.errors.full_messages.join(", ")}".red
      end
    end

    def parse_task_due_date(due_date_str)
      return nil unless due_date_str

      begin
        Time.parse(due_date_str)
      rescue ArgumentError
        say "Invalid date format '#{due_date_str}'. Using no due date.".yellow
        nil
      end
    end

    def validate_task_priority(priority_str)
      return nil unless priority_str

      if %w[high medium low].include?(priority_str.downcase)
        priority_str.downcase
      else
        msg = "Invalid priority '#{priority_str}'. Valid values are 'high', 'medium', or 'low'."
        say "#{msg} Using default.".yellow
        nil
      end
    end

    def move_task(action)
      unless action["notebook"] && action["task_id"] && action["status"]
        say "Missing required fields for move_task".red
        return
      end

      notebook = Notebook.find_by(name: action["notebook"])
      unless notebook
        say "Notebook '#{action["notebook"]}' not found".red
        return
      end

      task = notebook.tasks.find_by(id: action["task_id"])
      unless task
        say "Task with ID #{action["task_id"]} not found".red
        return
      end

      valid_statuses = %w[todo in_progress done archived]
      status = action["status"].downcase
      unless valid_statuses.include?(status)
        say "Invalid status '#{status}'. Valid values are: #{valid_statuses.join(", ")}".red
        return
      end

      if task.update(status: status)
        say "Moved task #{action["task_id"]} to #{status}".green
      else
        say "Error moving task: #{task.errors.full_messages.join(", ")}".red
      end
    end

    def create_notebook(action)
      unless action["name"]
        say "Missing required field 'name' for create_notebook".red
        return
      end

      notebook = Notebook.create(name: action["name"])
      if notebook.valid?
        say "Created notebook: #{action["name"]}".green
      else
        say "Error creating notebook: #{notebook.errors.full_messages.join(", ")}".red
      end
    end

    def generate_import_json(action)
      unless action["notebook"] && action["tasks"] && action["tasks"].is_a?(Array)
        say "Missing required fields for generate_import_json".red
        return
      end

      data = {
        "name" => action["notebook"],
        "created_at" => Time.now.iso8601,
        "updated_at" => Time.now.iso8601,
        "tasks" => action["tasks"].map do |task|
          {
            "title" => task["title"],
            "description" => task["description"],
            "status" => task["status"] || "todo",
            "priority" => task["priority"],
            "tags" => task["tags"],
            "due_date" => task["due_date"]
          }
        end
      }

      filename = action["filename"] || "#{action["notebook"].downcase.gsub(/\s+/, "_")}_tasks.json"
      File.write(filename, JSON.pretty_generate(data))
      say "Generated import JSON file: #{filename}".green

      if @prompt.yes?("Do you want to import these tasks now?")
        import_result = RubyTodo::CLI.new.import(filename)
        say "Import complete: #{import_result}"
      end
    end

    def list_tasks(action)
      unless action["notebook"]
        say "Missing required field 'notebook' for list_tasks".red
        return
      end

      notebook = Notebook.find_by(name: action["notebook"])
      unless notebook
        say "Notebook '#{action["notebook"]}' not found".red
        return
      end

      tasks = notebook.tasks
      tasks = tasks.where(status: action["status"]) if action["status"]
      tasks = tasks.where(priority: action["priority"]) if action["priority"]

      if tasks.empty?
        say "No tasks found".yellow
        return
      end

      display_tasks_table(tasks)
    end

    def display_tasks_table(tasks)
      rows = tasks.map do |t|
        [
          t.id,
          t.title,
          format_status(t.status),
          t.priority || "None",
          t.due_date ? t.due_date.strftime("%Y-%m-%d %H:%M") : "No due date",
          t.tags || "None"
        ]
      end

      table = TTY::Table.new(
        header: ["ID", "Title", "Status", "Priority", "Due Date", "Tags"],
        rows: rows
      )
      puts table.render(:ascii)
    end

    def search_tasks(action)
      unless action["query"]
        say "Missing required field 'query' for search_tasks".red
        return
      end

      notebooks = if action["notebook"]
                    [Notebook.find_by(name: action["notebook"])].compact
                  else
                    Notebook.all
                  end

      if notebooks.empty?
        say "No notebooks found".yellow
        return
      end

      results = find_matching_tasks(notebooks, action["query"])

      if results.empty?
        say "No tasks matching '#{action["query"]}' found".yellow
        return
      end

      display_search_results(results)
    end

    def find_matching_tasks(notebooks, query)
      results = []
      notebooks.each do |notebook|
        notebook.tasks.each do |task|
          next unless task.title.downcase.include?(query.downcase) ||
                      (task.description && task.description.downcase.include?(query.downcase)) ||
                      (task.tags && task.tags.downcase.include?(query.downcase))

          results << [notebook.name, task.id, task.title, format_status(task.status)]
        end
      end
      results
    end

    def display_search_results(results)
      table = TTY::Table.new(
        header: %w[Notebook ID Title Status],
        rows: results
      )
      puts table.render(:ascii)
    end

    def load_api_key_from_config
      config_file = File.expand_path("~/.ruby_todo/ai_config.json")
      return nil unless File.exist?(config_file)

      config = JSON.parse(File.read(config_file))
      config["api_key"]
    end

    def save_config(api, api_key)
      config_dir = File.expand_path("~/.ruby_todo")
      FileUtils.mkdir_p(config_dir)

      config_file = File.join(config_dir, "ai_config.json")
      config = {
        "api" => api,
        "api_key" => api_key
      }

      File.write(config_file, JSON.pretty_generate(config))
      FileUtils.chmod(0o600, config_file) # Secure the file with private permissions
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

    def parse_due_date(date_string)
      Time.parse(date_string)
    rescue ArgumentError
      say "Invalid date format. Use YYYY-MM-DD HH:MM format.".red
      nil
    end
  end
end
