# frozen_string_literal: true

module RubyTodo
  module OpenAIDocumentation
    CLI_DOCUMENTATION = <<~DOCS
      Available ruby_todo commands:

      Task Management:
      1. List tasks:
         ruby_todo task:list [NOTEBOOK]
         - Lists all tasks in a notebook or all notebooks if no name provided
         - To filter by status: ruby_todo task:list [NOTEBOOK] --status STATUS
         - Example: ruby_todo task:list ExampleNotebook --status in_progress

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

      say "\nSystem prompt:\n#{messages.first[:content]}\n" if @options && @options[:verbose]
      say "\nUser prompt:\n#{prompt}\n" if @options && @options[:verbose]

      messages
    end

    def build_system_prompt(context)
      prompt = build_base_prompt
      prompt += build_command_examples
      prompt += build_json_format_requirements

      if context[:matching_tasks]&.any?
        prompt += build_matching_tasks_info(context)
      end

      prompt += build_final_instructions
      prompt
    end

    def build_base_prompt
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
      prompt
    end

    def build_command_examples
      prompt = "\n\nImportant command formats for common requests:"
      prompt += "\n- To list high priority tasks: ruby_todo task:list [NOTEBOOK] --priority high"
      prompt += "\n- To list tasks with a specific status: ruby_todo task:list [NOTEBOOK] --status [STATUS]"
      prompt += "\n- To list all notebooks: ruby_todo notebook:list"
      prompt += "\n- To create a task: ruby_todo task:add [NOTEBOOK] [TITLE]"
      prompt += "\n- To move a task to a status: ruby_todo task:move [NOTEBOOK] [TASK_ID] [STATUS]"

      prompt += "\n\nExamples of specific requests and corresponding commands:"
      prompt += "\n- 'show me all high priority tasks' → ruby_todo task:list ExampleNotebook --priority high"
      prompt += "\n- 'list tasks that are in progress' → ruby_todo task:list ExampleNotebook --status in_progress"
      prompt += "\n- 'show me all notebooks' → ruby_todo notebook:list"
      prompt += "\n- 'move task 5 to done' → ruby_todo task:move ExampleNotebook 5 done"
      prompt
    end

    def build_json_format_requirements
      prompt = "\n\nYou MUST respond with a JSON object containing:"
      prompt += "\n- 'commands': an array of commands to execute"
      prompt += "\n- 'explanation': a brief explanation of what the commands will do"
      prompt
    end

    def build_matching_tasks_info(context)
      prompt = "\n\nRelevant tasks found in the system:\n"
      context[:matching_tasks].each do |task|
        task_info = format_task_info(task)
        prompt += "- #{task_info}\n"
      end

      if context[:target_status] && context[:search_term]
        # Break this into multiple lines to avoid exceeding line length
        prompt += "\n\nI will move these tasks matching "
        prompt += "'#{context[:search_term]}' to "
        prompt += "'#{context[:target_status]}' status."
      end
      prompt
    end

    def build_final_instructions
      # Get the default notebook name
      default_notebook = RubyTodo::Notebook.default_notebook&.name || "YourNotebook"

      prompt = "\n\nEven if no tasks match a search or if your request isn't about task movement, "
      prompt += "I still need you to return a JSON response with commands and explanation."
      prompt += "The following examples use the current default notebook '#{default_notebook}'."
      prompt += "\n\nExample JSON Response:"
      prompt += "\n```json"
      prompt += "\n{"
      prompt += "\n  \"commands\": ["
      prompt += "\n    \"ruby_todo task:list #{default_notebook}\","
      prompt += "\n    \"ruby_todo stats #{default_notebook}\""
      prompt += "\n  ],"
      prompt += "\n  \"explanation\": \"Listing all tasks and statistics for the #{default_notebook} notebook\""
      prompt += "\n}"
      prompt += "\n```"

      prompt += "\n\nNote that all commands use colons, not underscores (e.g., 'task:list', not 'task_list')."
      prompt += "\n\nIf no notebook is specified in the user's request, use the default notebook '#{default_notebook}'."
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
      # Build the context for the AI
      combined_context = enrich_context_with_tasks(context)

      # Add example commands to context
      command_examples = "\nExample commands you can use:\n" \
                         "- task:add \"notebook_name\" \"task_title\" --priority high --tags \"tag1,tag2\"   " \
                         "--description \"detailed description\"\n" \
                         "- task:list \"notebook_name\"\n" \
                         "- task:move \"notebook_name\" task_id new_status (todo, in_progress, done)\n" \
                         "- task:delete \"notebook_name\" task_id\n" \
                         "- notebook:create notebook_name\n" \
                         "- notebook:list\n"
      combined_context += command_examples

      # Add special handling for task creation requests
      if prompt.match?(/add|create/i) && prompt.match?(/task|to-?do/i)
        # Extract potential task information from the prompt
        task_info = extract_task_info_from_prompt(prompt)
        task_context = "\nDetected task creation intent. Here's the extracted information:\n" \
                       "- Notebook: #{task_info[:notebook]}\n" \
                       "- Title: #{task_info[:title]}\n" \
                       "- Priority: #{task_info[:priority]}\n" \
                       "- Tags: #{task_info[:tags]}\n" \
                       "Please use this information to create a valid task:add command."
        combined_context += task_context
      end

      # Prepare the messages for the API call
      messages = [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: combined_context }
      ]

      # Additional user message with the actual prompt
      messages << { role: "user", content: prompt }

      # Make the API call with retry
      try_count = 0
      begin
        client = OpenAI::Client.new(access_token: api_key)
        response = client.chat(parameters: {
                                 model: "gpt-4o-mini",
                                 messages: messages,
                                 temperature: 0.7,
                                 max_tokens: 1000
                               })

        handle_openai_response(response)
      rescue OpenAI::Error => e
        try_count += 1
        if try_count <= 3
          say "OpenAI API error (retry #{try_count}/3): #{e.message}".yellow
          sleep(2 * try_count) # Exponential backoff
          retry
        else
          error_msg = "Failed to connect to OpenAI API after 3 attempts: #{e.message}"
          say error_msg.red
          { "explanation" => "Error connecting to OpenAI: #{e.message}", "commands" => [] }
        end
      end
    end

    # Extract potential task information from the prompt
    def extract_task_info_from_prompt(prompt)
      info = {
        notebook: nil,
        title: nil,
        priority: nil,
        tags: nil
      }

      # Extract notebook name
      if prompt =~ /(?:in|to)\s+(?:(?:the|my)\s+)?(?:notebook\s+)?["']?([^"'\s]+(?:\s+[^"'\s]+)*)["']?/i
        info[:notebook] = Regexp.last_match(1)
      end

      # Extract task title
      task_title_regex = /
        (?:titled|called|named)\s+["']([^"']+)["']|
        (?:add|create)\s+(?:a\s+)?(?:task|to-?do)\s+(?:to|for|about)\s+["']?([^"']+?)["']?(?:\s+to|\s+in|$)
      /xi

      if prompt =~ task_title_regex
        info[:title] = Regexp.last_match(1) || Regexp.last_match(2)
      end

      # Extract priority
      if prompt =~ /priority\s+(high|medium|low)/i
        info[:priority] = Regexp.last_match(1)
      end

      # Extract tags
      if prompt =~ /tags?\s+["']?([^"']+)["']?/i
        info[:tags] = Regexp.last_match(1)
      end

      # Set defaults for missing information
      info[:notebook] ||= "test_notebook" # Default notebook for tests
      info[:title] ||= "Task from prompt" # Default title

      info
    end

    private

    def build_messages(prompt, context)
      [
        {
          role: "system",
          content: system_prompt(context)
        },
        {
          role: "user",
          content: prompt
        }
      ]
    end

    def system_prompt(context)
      <<~PROMPT
        You are an AI assistant for the Ruby Todo CLI application. Your role is to help users manage their tasks and notebooks using natural language.

        Available commands:
        - task:add [notebook] [title] --description [description] --tags [comma,separated,tags] - Create a new task
        - task:move [notebook] [task_id] [status] - Move a task to a new status (todo/in_progress/done/archived)
        - task:list [notebook] [--status status] [--priority priority] - List tasks
        - task:delete [notebook] [task_id] - Delete a task
        - notebook:create [name] - Create a new notebook
        - notebook:list - List all notebooks
        - stats [notebook] - Show statistics

        IMPORTANT: When creating tasks, the exact format must be:
        task:add "notebook_name" "task_title" --description "description" --priority level --tags "tags"

        Make sure to:
        1. Format titles professionally (e.g., "Implement New Relic Monitoring" instead of "add new relic")
        2. Always include a detailed description that explains the task's scope and objectives
        3. Add relevant tags to categorize the task
        4. For technical tasks, include implementation details and considerations
        5. Always wrap notebook names and task titles in double quotes

        Example task creation:
        Input: "create a task to add new relic to questions-engine"
        Output command: 'task:add "default" "Implement New Relic Monitoring in Questions Engine" --description "Set up and configure New Relic APM for the Questions Engine application. Include performance monitoring, error tracking, and custom metrics. Configure alerts for critical issues and set up custom dashboards." --tags "monitoring,newrelic,performance,apm,backend"'

        Other examples:
        - 'task:add "default" "Research Competitor Products" --priority high --tags "research,marketing"'
        - 'task:move "default" 123 done'
        - 'task:list "default" --status todo'

        Current context:
        #{JSON.pretty_generate(context)}

        Your task is to:
        1. Understand the user's natural language request
        2. Convert it into one or more CLI commands with EXACT formatting as shown above
        3. Provide a brief explanation of what you're doing

        Respond with a JSON object containing:
        {
          "commands": ["command1", "command2", ...],
          "explanation": "Brief explanation of what you're doing"
        }
      PROMPT
    end

    def handle_openai_response(response)
      return nil unless response&.dig("choices", 0, "message", "content")

      content = response["choices"][0]["message"]["content"]
      parse_json_from_content(content)
    end

    def parse_json_from_content(content)
      # Extract JSON from the content (it might be wrapped in ```json blocks)
      json_match = content.match(/```json\n(.+?)\n```/m) || content.match(/\{.+\}/m)
      return nil unless json_match

      json_str = json_match[0].gsub(/```json\n|```/, "")
      JSON.parse(json_str)
    rescue JSON::ParserError
      nil
    end

    # Enrich context with task information
    def enrich_context_with_tasks(context)
      rich_context = "Current context:\n"

      if context && context[:notebooks] && !context[:notebooks].empty?
        rich_context += "Available notebooks:\n"
        context[:notebooks].each do |notebook|
          rich_context += "- #{notebook[:name]}#{notebook[:is_default] ? " (default)" : ""}\n"
        end
      else
        rich_context += "No notebooks available.\n"
      end

      if context && context[:tasks] && !context[:tasks].empty?
        rich_context += "\nRecent tasks:\n"
        context[:tasks].each do |task|
          task[:notebook] || "unknown"
          status = task[:status] || "todo"
          priority = task[:priority] ? " [priority: #{task[:priority]}]" : ""
          tags = task[:tags] ? " [tags: #{task[:tags]}]" : ""

          rich_context += "- Task #{task[:id]}: #{task[:title]} (#{status})#{priority}#{tags}\n"
        end
      else
        rich_context += "\nNo tasks available.\n"
      end

      rich_context
    end
  end
end
