# AI Assistant Integration for Ruby Todo

This document outlines the implementation plan for adding AI assistant functionality to the Ruby Todo gem, enabling users to interact with the application using natural language through Claude or OpenAI's APIs.

## Overview

The AI assistant will allow users to:
1. Create tasks using natural language
2. Move tasks between statuses 
3. Create and import task JSON files
4. Get summaries of tasks and notebooks
5. Ask questions about their tasks
6. Perform bulk operations with simple instructions

## Implementation Plan

### 1. Add Dependencies

Add the following gems to the gemspec:
```ruby
spec.add_dependency "anthropic", "~> 0.1.0" # For Claude API
spec.add_dependency "ruby-openai", "~> 6.3.0" # For OpenAI API
spec.add_dependency "dotenv", "~> 2.8" # For API key management
```

### 2. Create AI Assistant Command Class

Create a new class in `lib/ruby_todo/commands/ai_assistant.rb` to handle AI-related commands:

```ruby
# frozen_string_literal: true

require "thor"
require "json"
require "anthropic"
require "openai"
require "dotenv/load"

module RubyTodo
  class AIAssistantCommand < Thor
    desc "ask [PROMPT]", "Ask the AI assistant to perform tasks using natural language"
    method_option :api, type: :string, default: "claude", desc: "API to use (claude or openai)"
    method_option :api_key, type: :string, desc: "API key for the selected service"
    method_option :model, type: :string, desc: "Model to use (claude-3-opus-20240229, gpt-4, etc.)"
    method_option :verbose, type: :boolean, default: false, desc: "Show detailed response"
    def ask(*prompt_args)
      prompt = prompt_args.join(" ")
      unless prompt && !prompt.empty?
        say "Please provide a prompt for the AI assistant".red
        return
      end

      # Get API key from options, env var, or config file
      api_key = options[:api_key] || ENV["ANTHROPIC_API_KEY"] || ENV["OPENAI_API_KEY"] || load_api_key_from_config
      unless api_key
        say "No API key found. Please provide an API key using --api-key or set ANTHROPIC_API_KEY or OPENAI_API_KEY environment variable".red
        return
      end

      # Set up context for the AI
      context = build_context

      response = if options[:api] == "openai"
                  query_openai(prompt, context, api_key, options[:model] || "gpt-4")
                else
                  query_claude(prompt, context, api_key, options[:model] || "claude-3-opus-20240229")
                end

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
      api = prompt.select("Which AI provider would you like to use?", %w[Claude OpenAI])
      
      api_key = prompt.mask("Enter your API key:")
      
      model = "gpt-4o-mini"
      
      save_config(api.downcase, api_key, model)
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
          notebook_commands: ["create", "list"],
          task_commands: ["add", "list", "show", "edit", "delete", "move", "search"],
          export_commands: ["export", "import"],
          template_commands: ["create", "list", "show", "use", "delete"]
        },
        app_version: RubyTodo::VERSION
      }
    end

    def query_claude(prompt, context, api_key, model)
      client = Anthropic::Client.new(api_key: api_key)
      
      # Prepare system message with context
      system_message = <<~SYSTEM
        You are an AI assistant for Ruby Todo, a command-line task management application.
        
        Application Information:
        #{JSON.pretty_generate(context)}
        
        Your job is to help the user manage their tasks through natural language.
        You can create tasks, move tasks between statuses, and more.
        
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
        - create_task: Create a new task in a notebook
        - move_task: Move a task to a different status
        - create_notebook: Create a new notebook
        - generate_import_json: Generate JSON for importing tasks
        - list_tasks: List tasks in a notebook
        - search_tasks: Search for tasks
        
        Always respond in valid JSON format.
      SYSTEM
      
      begin
        response = client.messages.create(
          model: model,
          system: system_message,
          messages: [
            { role: "user", content: prompt }
          ],
          max_tokens: 1024
        )
        
        return { content: response.content.first.text }
      rescue => e
        return { error: e.message }
      end
    end

    def query_openai(prompt, context, api_key, model)
      client = OpenAI::Client.new(access_token: api_key)
      
      # Prepare system message with context
      system_message = <<~SYSTEM
        You are an AI assistant for Ruby Todo, a command-line task management application.
        
        Application Information:
        #{JSON.pretty_generate(context)}
        
        Your job is to help the user manage their tasks through natural language.
        You can create tasks, move tasks between statuses, and more.
        
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
        - create_task: Create a new task in a notebook
        - move_task: Move a task to a different status
        - create_notebook: Create a new notebook
        - generate_import_json: Generate JSON for importing tasks
        - list_tasks: List tasks in a notebook
        - search_tasks: Search for tasks
        
        Always respond in valid JSON format.
      SYSTEM
      
      begin
        response = client.chat(
          parameters: {
            model: model,
            messages: [
              { role: "system", content: system_message },
              { role: "user", content: prompt }
            ],
            max_tokens: 1024
          }
        )
        
        return { content: response.dig("choices", 0, "message", "content") }
      rescue => e
        return { error: e.message }
      end
    end

    def parse_and_execute_actions(response)
      begin
        # Parse the JSON response
        data = JSON.parse(response)
        
        # Print explanation
        say data["explanation"].green if data["explanation"]
        
        # Execute each action
        if data["actions"] && data["actions"].is_a?(Array)
          data["actions"].each do |action|
            execute_action(action)
          end
        end
      rescue JSON::ParserError => e
        say "Couldn't parse AI response: #{e.message}".red
        say "Raw response: #{response}" if options[:verbose]
      end
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
      # Validate required fields
      unless action["notebook"] && action["title"]
        say "Missing required fields for create_task".red
        return
      end
      
      # Find notebook
      notebook = Notebook.find_by(name: action["notebook"])
      unless notebook
        say "Notebook '#{action["notebook"]}' not found".red
        return
      end
      
      # Parse due date if present
      due_date = action["due_date"] ? parse_due_date(action["due_date"]) : nil
      
      # Create task
      task = Task.create(
        notebook: notebook,
        title: action["title"],
        description: action["description"],
        due_date: due_date,
        priority: action["priority"],
        tags: action["tags"],
        status: "todo"
      )
      
      if task.valid?
        say "Added task: #{action["title"]}".green
      else
        say "Error creating task: #{task.errors.full_messages.join(", ")}".red
      end
    end

    def move_task(action)
      # Validate required fields
      unless action["notebook"] && action["task_id"] && action["status"]
        say "Missing required fields for move_task".red
        return
      end
      
      # Find notebook
      notebook = Notebook.find_by(name: action["notebook"])
      unless notebook
        say "Notebook '#{action["notebook"]}' not found".red
        return
      end
      
      # Find task
      task = notebook.tasks.find_by(id: action["task_id"])
      unless task
        say "Task with ID #{action["task_id"]} not found".red
        return
      end
      
      # Update task status
      if task.update(status: action["status"])
        say "Moved task #{action["task_id"]} to #{action["status"]}".green
      else
        say "Error moving task: #{task.errors.full_messages.join(", ")}".red
      end
    end
    
    def create_notebook(action)
      # Validate required fields
      unless action["name"]
        say "Missing required field 'name' for create_notebook".red
        return
      end
      
      # Create notebook
      notebook = Notebook.create(name: action["name"])
      if notebook.valid?
        say "Created notebook: #{action["name"]}".green
      else
        say "Error creating notebook: #{notebook.errors.full_messages.join(", ")}".red
      end
    end
    
    def generate_import_json(action)
      # Validate required fields
      unless action["notebook"] && action["tasks"] && action["tasks"].is_a?(Array)
        say "Missing required fields for generate_import_json".red
        return
      end
      
      # Create JSON structure
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
      
      # Write JSON to file
      filename = action["filename"] || "#{action["notebook"].downcase.gsub(/\s+/, '_')}_tasks.json"
      File.write(filename, JSON.pretty_generate(data))
      say "Generated import JSON file: #{filename}".green
      
      # Offer to import the file
      if @prompt.yes?("Do you want to import these tasks now?")
        import_result = RubyTodo::CLI.new.import(filename)
        say "Import complete: #{import_result}"
      end
    end

    def list_tasks(action)
      # Validate required fields
      unless action["notebook"]
        say "Missing required field 'notebook' for list_tasks".red
        return
      end
      
      # Find notebook
      notebook = Notebook.find_by(name: action["notebook"])
      unless notebook
        say "Notebook '#{action["notebook"]}' not found".red
        return
      end
      
      # Apply filters
      tasks = notebook.tasks
      tasks = tasks.where(status: action["status"]) if action["status"]
      tasks = tasks.where(priority: action["priority"]) if action["priority"]
      
      # Display tasks
      if tasks.empty?
        say "No tasks found".yellow
        return
      end
      
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
      # Validate required fields
      unless action["query"]
        say "Missing required field 'query' for search_tasks".red
        return
      end
      
      # Determine notebooks
      notebooks = if action["notebook"]
                    [Notebook.find_by(name: action["notebook"])].compact
                  else
                    Notebook.all
                  end
      
      if notebooks.empty?
        say "No notebooks found".yellow
        return
      end
      
      # Search for tasks
      results = []
      notebooks.each do |notebook|
        notebook.tasks.each do |task|
          next unless task.title.downcase.include?(action["query"].downcase) ||
                      (task.description && task.description.downcase.include?(action["query"].downcase)) ||
                      (task.tags && task.tags.downcase.include?(action["query"].downcase))
          
          results << [notebook.name, task.id, task.title, format_status(task.status)]
        end
      end
      
      if results.empty?
        say "No tasks matching '#{action["query"]}' found".yellow
        return
      end
      
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
    
    def save_config(api, api_key, model)
      config_dir = File.expand_path("~/.ruby_todo")
      FileUtils.mkdir_p(config_dir)
      
      config_file = File.join(config_dir, "ai_config.json")
      config = {
        "api" => api,
        "api_key" => api_key,
        "model" => model
      }
      
      File.write(config_file, JSON.pretty_generate(config))
      FileUtils.chmod(0600, config_file) # Secure the file with private permissions
    end
    
    # Helper methods for formatting
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
```

### 3. Integrate AI Assistant Command with CLI

Update `lib/ruby_todo/cli.rb` to register the AI Assistant command:

```ruby
# Add the require statement at the top
require_relative "commands/ai_assistant"

module RubyTodo
  class CLI < Thor
    # Existing code...
    
    # Register AI Assistant subcommand
    desc "ai SUBCOMMAND", "Use AI assistant"
    subcommand "ai", AIAssistantCommand
    
    # More existing code...
  end
end
```

### 4. Add Configuration Files

Create sample `.env` file for API key management:

```
ANTHROPIC_API_KEY=your_claude_api_key_here
OPENAI_API_KEY=your_openai_api_key_here
```

### 5. Update README Documentation

Add new section to README.md for AI Assistant usage:

```markdown
### AI Assistant

Ruby Todo includes an AI assistant powered by Claude or OpenAI that can help you manage your tasks using natural language.

#### Configuration

Configure your AI assistant:
```bash
$ ruby_todo ai configure
```

#### Using the AI Assistant

Ask the AI assistant to perform actions:
```bash
$ ruby_todo ai ask "Create a new task in my Work notebook to update the documentation by next Friday"
```

```bash
$ ruby_todo ai ask "Move all tasks related to the API project to in_progress status"
```

```bash
$ ruby_todo ai ask "Create a JSON to import 5 new tasks for my upcoming vacation"
```

Pass in an API key directly (if not configured):
```bash
$ ruby_todo ai ask "What tasks are overdue?" --api-key=your_api_key_here --api=claude
```

Enable verbose mode to see full AI responses:
```bash
$ ruby_todo ai ask "Summarize my Work notebook" --verbose
```
```

## Implementation Timeline

1. Add new dependencies to gemspec
2. Create the AI Assistant command structure
3. Implement API integration (Claude and OpenAI)
4. Add action parsing and execution
5. Create configuration management
6. Update documentation and examples
7. Test with various prompts

## Security Considerations

1. API keys stored in `~/.ruby_todo/ai_config.json` should have appropriate file permissions (0600)
2. Environmental variables can be used instead of configuration files
3. Options for passing API keys directly in CLI should warn about shell history
4. Input validation to prevent command injection
5. Error handling to prevent exposing sensitive information

## Testing Plan

1. Unit tests for AI command class
2. Integration tests for action execution
3. Mock API responses for testing
4. Test with various prompt patterns
5. Test configuration storage and retrieval
6. Test error handling and edge cases 