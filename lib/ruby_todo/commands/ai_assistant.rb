# frozen_string_literal: true

require "thor"
require "json"
require "openai"
require "dotenv/load"

module RubyTodo
  module TaskSearch
    def pre_search_tasks(search_term)
      say "\n=== Searching Tasks ===" if options[:verbose]
      matching_tasks = []
      
      # Special case for matching all tasks
      if search_term == "*"
        say "Special case: matching ALL tasks" if options[:verbose]
        
        notebooks = Notebook.all
        say "Found #{notebooks.size} notebooks" if options[:verbose]
        
        if notebooks.size > 1 && Notebook.default_notebook
          notebooks = [Notebook.default_notebook]
          say "Using default notebook: #{notebooks.first.name}" if options[:verbose]
        end

        notebooks.each do |notebook|
          next unless notebook
          say "\nSearching in notebook: #{notebook.name}" if options[:verbose]
          
          notebook.tasks.each do |task|
            say "  Adding task #{task.id}: #{task.title}" if options[:verbose]
            matching_tasks << {
              notebook: notebook.name,
              task_id: task.id,
              title: task.title,
              status: task.status
            }
          end
        end
        
        say "\nTotal matching tasks found: #{matching_tasks.size}" if options[:verbose]
        return matching_tasks
      end
      
      # Process search terms - split by "and" or "&" for compound searches
      search_terms = search_term.split(/\s+(?:and|&)\s+/).map(&:strip)
      compound_search = search_terms.size > 1
      
      say "Search terms: #{search_terms.join(', ')}" if options[:verbose]
      say "Compound search: #{compound_search}" if options[:verbose]

      notebooks = Notebook.all
      say "Found #{notebooks.size} notebooks" if options[:verbose]
      
      if notebooks.size > 1 && Notebook.default_notebook
        notebooks = [Notebook.default_notebook]
        say "Using default notebook: #{notebooks.first.name}" if options[:verbose]
      end

      notebooks.each do |notebook|
        next unless notebook
        say "\nSearching in notebook: #{notebook.name}" if options[:verbose]

        notebook.tasks.each do |task|
          say "  Checking task #{task.id}: #{task.title}" if options[:verbose]
          
          # Determine if the task matches each search term
          # For compound searches, we need to be more flexible
          matches = false
          
          if search_terms.include?("barracuda")
            # Special case for barracuda searches - look for repository migration patterns in titles
            # Instead of hardcoding repository names, use a pattern matching approach
            repository_pattern = /(migrate|migration|move).*?(to barracuda org|MAN-\w+\/[\w-]+)/i
            
            result = repository_pattern.match?(task.title)
            say "    Task title matches repository migration pattern: #{result}" if options[:verbose]
            
            if result
              matches = true
              say "    Task matches barracuda organization migration pattern" if options[:verbose]
            end
          else
            # For all other searches, check each term individually
            matching_terms = []
            search_terms.each do |term|
              if matches_task?(task, term)
                matching_terms << term
                say "    Term '#{term}' matches" if options[:verbose]
              else
                say "    Term '#{term}' does not match" if options[:verbose]
              end
            end
            
            matches = matching_terms.any?
          end
          
          if matches
            matching_tasks << {
              notebook: notebook.name,
              task_id: task.id,
              title: task.title,
              status: task.status
            }
            say "    Added to matching tasks" if options[:verbose]
          end
        end
      end
      
      say "\nTotal matching tasks found: #{matching_tasks.size}" if options[:verbose]
      matching_tasks
    end

    def matches_task?(task, term)
      term = term.downcase
      matches = []
      
      title_match = task.title.downcase.include?(term)
      matches << "title" if title_match
      
      desc_match = task.description && task.description.downcase.include?(term)
      matches << "description" if desc_match
      
      tags_match = task.tags && task.tags.downcase.include?(term)
      matches << "tags" if tags_match
      
      say "      Matches in: #{matches.join(', ')}" if options[:verbose] && !matches.empty?
      
      title_match || desc_match || tags_match
    end

    def extract_search_term(prompt)
      say "\n=== Extracting Search Term ===" if options[:verbose]
      say "Original prompt: '#{prompt}'" if options[:verbose]

      # Special case for "all tasks" or similar prompts
      if prompt.downcase.match?(/\b(all tasks|every task|all|everything)\b/)
        say "Detected request to move all tasks" if options[:verbose]
        return "*" # Special token to match all tasks
      end

      # Remove common command words that shouldn't be part of the search
      search_term = prompt.dup
      
      # First remove the status part to find what's being searched
      status_pattern = /\s+(?:to|into|as)\s+(?:todo|done|in[_ ]progress|archived|pending|github actions)\b.*/i
      search_term = search_term.sub(status_pattern, '')
      say "After removing status: '#{search_term}'" if options[:verbose]
      
      # Remove command words
      search_term = search_term.sub(/^(?:move|change|set)\s+/i, '')
      say "After removing command words: '#{search_term}'" if options[:verbose]
      
      # Remove filler words at the start
      search_term = search_term.sub(/^(?:all|tasks?|about)\s+/i, '')
      say "After removing filler words: '#{search_term}'" if options[:verbose]
      
      # Remove filler words at the end
      search_term = search_term.sub(/\s+tasks?\s*$/i, '')
      say "After removing trailing filler words: '#{search_term}'" if options[:verbose]
      
      # Clean up any extra whitespace
      search_term = search_term.strip
      
      # Check for repository migration patterns
      if search_term.match?(/(migrate|migration|move).*?(to.*?org|repositories)/i) ||
         search_term.match?(/.*?\/([\w-]+)/i) # matches organization/repo patterns
        # Extract the organization or primary search term
        org_match = search_term.match(/(?:to\s+)?([\w-]+)(?:\s+org)/i)
        if org_match
          search_term = org_match[1].downcase
          say "Extracted organization from migration pattern: '#{search_term}'" if options[:verbose]
        end
      end
      
      say "Final search term: '#{search_term}'" if options[:verbose]
      search_term unless search_term.empty?
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
      say "\nHandling task request for prompt: '#{prompt}'" if options[:verbose]
      
      if should_handle_task_movement?(prompt)
        search_term = extract_search_term(prompt)
        if search_term
          say "\nSearching for tasks matching: '#{search_term}'" if options[:verbose]
          matching_tasks = pre_search_tasks(search_term)

          if matching_tasks.any?
            target_status = extract_target_status(prompt)
            if target_status
              handle_matching_tasks(matching_tasks, context)
              context[:target_status] = target_status
              context[:search_term] = search_term
              say "\nFound #{matching_tasks.size} tasks to move to #{target_status}" if options[:verbose]
            else
              say "\nCould not determine target status from prompt".yellow
            end
          else
            say "\nNo tasks found matching: '#{search_term}'".yellow
          end
        else
          say "\nCould not extract search term from prompt".yellow
        end
      else
        say "\nNot a task movement request" if options[:verbose]
      end
    end

    def should_handle_task_movement?(prompt)
      prompt = prompt.downcase
      say "\nChecking if should handle task movement for prompt: '#{prompt}'" if options[:verbose]
      result = (prompt.include?("move") && !prompt.include?("task")) ||
        (prompt.include?("move") && prompt.include?("task")) ||
        (prompt.include?("change") && prompt.include?("status")) ||
        (prompt.include?("set") && prompt.include?("status"))
      say "Should handle task movement: #{result}" if options[:verbose]
      result
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

    def extract_target_status(prompt)
      prompt = prompt.downcase
      say "\n=== Extracting Target Status ===" if options[:verbose]
      say "Looking for status in: '#{prompt}'" if options[:verbose]
      
      status_map = {
        "in_progress" => "in_progress",
        "in progress" => "in_progress",
        "todo" => "todo",
        "done" => "done",
        "archived" => "archived",
        "pending" => "todo",
        "github actions" => "in_progress"
      }

      status_map.each do |key, value|
        if prompt.include?(key)
          say "Found status '#{key}' mapping to '#{value}'" if options[:verbose]
          return value
        end
      end

      say "No status found in the prompt" if options[:verbose]
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

      10. Set default notebook:
          ruby_todo notebook:set_default NAME
          - Set a notebook as the default

      Template Management:
      11. List templates:
          ruby_todo template:list
          - List all templates

      12. Show template:
          ruby_todo template:show NAME
          - Show details of a specific template

      13. Create template:
          ruby_todo template:create NAME --title TITLE
          - Create a new task template

      14. Delete template:
          ruby_todo template:delete NAME
          - Delete a template

      15. Use template:
          ruby_todo template:use NAME NOTEBOOK
          - Create a task from a template in the specified notebook

      Other Commands:
      16. Export tasks:
          ruby_todo export [NOTEBOOK] [FILENAME]
          - Export tasks from a notebook to a JSON file

      17. Import tasks:
          ruby_todo import [FILENAME]
          - Import tasks from a JSON or CSV file

      18. Show statistics:
          ruby_todo stats [NOTEBOOK]
          - Show statistics for a notebook or all notebooks

      19. Initialize:
          ruby_todo init
          - Initialize a new todo list

      Note: All commands use colons (e.g., 'task:list', 'notebook:list').
      Available statuses: todo, in_progress, done, archived
    DOCS
  end

  module OpenAIPromptBuilder
    include OpenAIDocumentation

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
      prompt += "Your role is to analyze user requests and generate the appropriate ruby_todo command(s). "
      prompt += "You should respond to ALL types of requests, not just task movement requests."
      prompt += "\n\nHere are the available commands and their usage:\n"
      prompt += CLI_DOCUMENTATION
      prompt += "\nBased on the user's request, generate command(s) that follow these formats exactly."
      prompt += "\n\nStatus Mapping:"
      prompt += "\n- 'pending' maps to 'todo'"
      prompt += "\n- 'in progress' maps to 'in_progress'"
      prompt += "\nPlease use the mapped status values in your commands."
      
      prompt += "\n\nImportant command formats for common requests:"
      prompt += "\n- To list high priority tasks: ruby_todo task:list [NOTEBOOK] --priority high"
      prompt += "\n- To list tasks with a specific status: ruby_todo task:list [NOTEBOOK] --status [STATUS]"
      prompt += "\n- To list all notebooks: ruby_todo notebook:list"
      prompt += "\n- To create a task: ruby_todo task:add [NOTEBOOK] [TITLE]"
      prompt += "\n- To move a task to a status: ruby_todo task:move [NOTEBOOK] [TASK_ID] [STATUS]"
      
      prompt += "\n\nExamples of specific requests and corresponding commands:"
      prompt += "\n- 'show me all high priority tasks' → ruby_todo task:list protectors --priority high"
      prompt += "\n- 'list tasks that are in progress' → ruby_todo task:list protectors --status in_progress"
      prompt += "\n- 'show me all notebooks' → ruby_todo notebook:list"
      prompt += "\n- 'move task 5 to done' → ruby_todo task:move protectors 5 done"
      
      prompt += "\n\nYou MUST respond with a JSON object containing:"
      prompt += "\n- 'commands': an array of commands to execute"
      prompt += "\n- 'explanation': a brief explanation of what the commands will do"

      if context[:matching_tasks]&.any?
        prompt += "\n\nRelevant tasks found in the system:\n"
        context[:matching_tasks].each do |task|
          task_info = format_task_info(task)
          prompt += "- #{task_info}\n"
        end

        if context[:target_status] && context[:search_term]
          prompt += "\n\nI will move these tasks matching '#{context[:search_term]}' to '#{context[:target_status]}' status."
        end
      end
      
      prompt += "\n\nEven if no tasks match a search or if your request isn't about task movement, I still need you to return a JSON response with commands and explanation."
      prompt += "\n\nExample JSON Response:"
      prompt += "\n```json"
      prompt += "\n{"
      prompt += "\n  \"commands\": ["
      prompt += "\n    \"ruby_todo task:list protectors\","
      prompt += "\n    \"ruby_todo stats protectors\""
      prompt += "\n  ],"
      prompt += "\n  \"explanation\": \"Listing all tasks and statistics for the protectors notebook\""
      prompt += "\n}"
      prompt += "\n```"
      
      prompt += "\n\nNote that all commands use colons, not underscores (e.g., 'task:list', not 'task_list')."

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
      say "\nMaking OpenAI API call...".blue if options[:verbose]
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

      say "\nOpenAI API call completed".green if options[:verbose]
      
      # Debug raw response
      if options[:verbose]
        say "\n=== RAW OPENAI RESPONSE ==="
        if response && response.dig("choices", 0, "message", "content")
          say response["choices"][0]["message"]["content"]
        else
          say "No content in response"
        end
        say "=== END RAW RESPONSE ===\n"
      end
      
      parsed_response = handle_openai_response(response)
      
      # Add more detailed debug output about the response
      if options[:verbose] && parsed_response
        say "\n=== PARSED RESPONSE DETAILS ==="
        say "Commands array type: #{parsed_response["commands"].class}"
        say "Number of commands: #{parsed_response["commands"].size}"
        parsed_response["commands"].each_with_index do |cmd, i|
          say "Command #{i+1}: '#{cmd}'"
        end
        say "=== END RESPONSE DETAILS ===\n"
      end
      
      parsed_response
    end

    private

    def handle_openai_response(response)
      return nil unless response&.dig("choices", 0, "message", "content")

      content = response["choices"][0]["message"]["content"]
      say "\nAI Response:\n#{content}\n" if options[:verbose]

      begin
        # Remove markdown formatting if present
        json_content = content.gsub(/```(?:json)?\n(.*?)\n```/m, '\1')
        # Strip any leading/trailing whitespace, braces are required
        json_content = json_content.strip
        # Add braces if they're missing
        json_content = "{#{json_content}}" unless json_content.start_with?('{') && json_content.end_with?('}')
        
        say "\nProcessed JSON content:\n#{json_content}\n" if options[:verbose]
        
        result = JSON.parse(json_content)
        
        # Ensure we have the required keys
        if !result.key?("commands") || !result["commands"].is_a?(Array)
          say "Warning: AI response missing 'commands' array. Adding empty array.".yellow if options[:verbose]
          result["commands"] = []
        end
        
        if !result.key?("explanation") || !result["explanation"].is_a?(String)
          say "Warning: AI response missing 'explanation'. Adding default.".yellow if options[:verbose]
          result["explanation"] = "Command execution completed."
        end
        
        return result
      rescue JSON::ParserError => e
        say "Error parsing AI response: #{e.message}".red if options[:verbose]
        
        # Try to extract commands from plain text as fallback
        commands = []
        content.scan(/ruby_todo\s+\S+(?:\s+\S+)*/) do |cmd|
          commands << cmd.strip
        end
        
        if commands.any?
          say "Extracted #{commands.size} commands from text response".yellow if options[:verbose]
          return {
            "commands" => commands,
            "explanation" => "Commands extracted from non-JSON response."
          }
        end
        
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
      say "\n=== Starting AI Assistant with prompt: '#{prompt}' ===" if options[:verbose]
      
      # Direct handling for common queries
      if handle_common_query(prompt)
        return
      end
      
      api_key = fetch_api_key
      say "\nAPI key loaded successfully" if options[:verbose]
      
      context = build_context
      say "\nInitial context built" if options[:verbose]

      # Check if this is a task movement request
      if should_handle_task_movement?(prompt)
        # Handle task movement and build context
        say "\n=== Processing Task Movement Request ===" if options[:verbose]
        handle_task_request(prompt, context)
      else
        # Handle non-movement requests - just proceed with AI
        say "\n=== Processing Non-Movement Request ===" if options[:verbose]
      end

      # Get AI response for commands and explanation
      say "\n=== Querying OpenAI ===" if options[:verbose]
      response = query_openai(prompt, context, api_key)
      say "\nOpenAI Response received" if options[:verbose]

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

    def execute_commands(response)
      return unless response["commands"].is_a?(Array)

      response["commands"].each do |command|
        say "\nExecuting command: #{command}".blue if options[:verbose]
        
        begin
          # Skip if empty or nil
          next if command.nil? || command.strip.empty?
          
          # Ensure command starts with ruby_todo
          next unless command.start_with?("ruby_todo")
          
          # Remove the ruby_todo prefix
          cmd_without_prefix = command.sub(/^ruby_todo\s+/, '')
          say "\nCommand without prefix: '#{cmd_without_prefix}'".blue if options[:verbose]
          
          # Map task_list format to task:list if needed
          if cmd_without_prefix.start_with?("task_list")
            cmd_without_prefix = cmd_without_prefix.sub("task_list", "task:list")
            say "\nConverted underscores to colons: '#{cmd_without_prefix}'".blue if options[:verbose]
          end
          
          # Handle task:list command format for priority
          if cmd_without_prefix.start_with?("task:list")
            parts = cmd_without_prefix.split(/\s+/)
            say "\nSplit task:list command into parts: #{parts.inspect}".blue if options[:verbose]
            
            if parts.size >= 2
              notebook_name = parts[1]
              # Extract any options
              options_args = []
              parts[2..-1].each do |part|
                options_args << part if part.start_with?("--")
              end
              
              # Execute the task list command with the notebook name and any options
              cli_args = ["task:list", notebook_name] + options_args
              say "\nRunning CLI with args: #{cli_args.inspect}".blue if options[:verbose]
              RubyTodo::CLI.start(cli_args)
            else
              # If no notebook specified, use default
              if Notebook.default_notebook
                cli_args = ["task:list", Notebook.default_notebook.name]
                if parts.size > 1 && parts[1].start_with?("--")
                  cli_args << parts[1]
                end
                say "\nUsing default notebook for task:list with args: #{cli_args.inspect}".blue if options[:verbose]
                RubyTodo::CLI.start(cli_args)
              else
                say "\nNo notebook specified for task:list command".yellow
              end
            end
          else
            # Process all other commands
            cli_args = cmd_without_prefix.split(/\s+/)
            say "\nRunning CLI with args: #{cli_args.inspect}".blue if options[:verbose]
            RubyTodo::CLI.start(cli_args)
          end
          
        rescue StandardError => e
          say "Error executing command: #{e.message}".red
          say e.backtrace.join("\n").red if options[:verbose]
        end
      end
    end

    def handle_common_query(prompt)
      prompt_lower = prompt.downcase
      
      # Handle task creation
      if (prompt_lower.include?("create") || prompt_lower.include?("add")) && 
         (prompt_lower.include?("task") || prompt_lower.include?("todo"))
        say "\n=== Detecting task creation request ===" if options[:verbose]
        
        # Extract task title - assuming it's in quotes
        title_match = prompt.match(/'([^']+)'|"([^"]+)"/)
        
        if title_match
          title = title_match[1] || title_match[2]
          
          # Check for priority specification
          priority = nil
          if prompt_lower.include?("high priority") || prompt_lower.match(/priority.*high/)
            priority = "high"
          elsif prompt_lower.include?("medium priority") || prompt_lower.match(/priority.*medium/)
            priority = "medium"
          elsif prompt_lower.include?("low priority") || prompt_lower.match(/priority.*low/)
            priority = "low"
          end
          
          if Notebook.default_notebook
            notebook_name = Notebook.default_notebook.name
            
            # Try to extract a specific notebook name from the prompt
            Notebook.all.each do |notebook|
              if prompt_lower.include?(notebook.name.downcase)
                notebook_name = notebook.name
                break
              end
            end
            
            say "\nCreating task in notebook: #{notebook_name}" if options[:verbose]
            cli_args = ["task:add", notebook_name, title]
            
            # Add priority if specified
            if priority
              cli_args.push("--priority", priority)
            end
            
            RubyTodo::CLI.start(cli_args)
            
            # Create a simple explanation
            priority_text = priority ? " with #{priority} priority" : ""
            say "\nCreated task '#{title}'#{priority_text} in the #{notebook_name} notebook"
            return true
          end
        else
          # If no quoted title found, try extracting from the prompt
          # Strip common phrases to get at the task title
          potential_title = prompt
          ["create a task", "create task", "add a task", "add task", "called", "named", "with", "priority", "high", "medium", "low", "in", "notebook"].each do |phrase|
            potential_title = potential_title.gsub(/#{phrase}/i, " ")
          end
          potential_title = potential_title.strip
          
          if !potential_title.empty? && Notebook.default_notebook
            notebook_name = Notebook.default_notebook.name
            
            # Try to extract a specific notebook name from the prompt
            Notebook.all.each do |notebook|
              if prompt_lower.include?(notebook.name.downcase)
                notebook_name = notebook.name
                break
              end
            end
            
            # Determine priority
            priority = nil
            if prompt_lower.include?("high priority") || prompt_lower.match(/priority.*high/)
              priority = "high"
            elsif prompt_lower.include?("medium priority") || prompt_lower.match(/priority.*medium/)
              priority = "medium"
            elsif prompt_lower.include?("low priority") || prompt_lower.match(/priority.*low/)
              priority = "low"
            end
            
            say "\nCreating task in notebook: #{notebook_name}" if options[:verbose]
            cli_args = ["task:add", notebook_name, potential_title]
            
            # Add priority if specified
            if priority
              cli_args.push("--priority", priority)
            end
            
            RubyTodo::CLI.start(cli_args)
            
            # Create a simple explanation
            priority_text = priority ? " with #{priority} priority" : ""
            say "\nCreated task '#{potential_title}'#{priority_text} in the #{notebook_name} notebook"
            return true
          end
        end
      end
      
      # Handle high priority tasks
      if prompt_lower.include?("high priority") || 
         (prompt_lower.include?("priority") && prompt_lower.include?("high"))
        say "\n=== Detecting high priority task request ===" if options[:verbose]
        
        if Notebook.default_notebook
          say "\nListing high priority tasks from default notebook" if options[:verbose]
          RubyTodo::CLI.start(["task:list", Notebook.default_notebook.name, "--priority", "high"])
          
          # Create a simple explanation
          say "\nListing all high priority tasks in the #{Notebook.default_notebook.name} notebook"
          return true
        end
      end
      
      # Handle medium priority tasks
      if prompt_lower.include?("medium priority") || 
         (prompt_lower.include?("priority") && prompt_lower.include?("medium"))
        say "\n=== Detecting medium priority task request ===" if options[:verbose]
        
        if Notebook.default_notebook
          say "\nListing medium priority tasks from default notebook" if options[:verbose]
          RubyTodo::CLI.start(["task:list", Notebook.default_notebook.name, "--priority", "medium"])
          
          # Create a simple explanation
          say "\nListing all medium priority tasks in the #{Notebook.default_notebook.name} notebook"
          return true
        end
      end
      
      # Handle statistics commands
      if (prompt_lower.include?("statistics") || prompt_lower.include?("stats")) &&
         (prompt_lower.include?("notebook") || prompt_lower.include?("tasks"))
        say "\n=== Detecting statistics request ===" if options[:verbose]
        
        # Check if a specific notebook is mentioned
        notebook_name = nil
        if Notebook.default_notebook
          notebook_name = Notebook.default_notebook.name
          
          # Try to extract a specific notebook name from the prompt
          Notebook.all.each do |notebook|
            if prompt_lower.include?(notebook.name.downcase)
              notebook_name = notebook.name
              break
            end
          end
          
          say "\nShowing statistics for notebook: #{notebook_name}" if options[:verbose]
          RubyTodo::CLI.start(["stats", notebook_name])
          
          # Create a simple explanation
          say "\nDisplaying statistics for the #{notebook_name} notebook"
          return true
        else
          # Show global stats if no default notebook
          say "\nShowing global statistics" if options[:verbose]
          RubyTodo::CLI.start(["stats"])
          
          # Create a simple explanation
          say "\nDisplaying global statistics for all notebooks"
          return true
        end
      end
      
      # Handle listing tasks by status
      statuses = {"todo" => "todo", "in progress" => "in_progress", "done" => "done", "archived" => "archived"}
      statuses.each do |name, value|
        if prompt_lower.include?("#{name} tasks") || prompt_lower.include?("tasks in #{name}")
          say "\n=== Detecting #{name} task listing request ===" if options[:verbose]
          
          if Notebook.default_notebook
            say "\nListing #{name} tasks from default notebook" if options[:verbose]
            RubyTodo::CLI.start(["task:list", Notebook.default_notebook.name, "--status", value])
            
            # Create a simple explanation
            say "\nListing all #{name} tasks in the #{Notebook.default_notebook.name} notebook"
            return true
          end
        end
      end
      
      # Handle notebook listing
      if prompt_lower.include?("list notebooks") || prompt_lower.include?("show notebooks") || 
         prompt_lower.include?("all notebooks")
        say "\n=== Detecting notebook listing request ===" if options[:verbose]
        RubyTodo::CLI.start(["notebook:list"])
        
        # Create a simple explanation
        say "\nListing all available notebooks"
        return true
      end
      
      # Not a common query
      return false
    end
  end
end
