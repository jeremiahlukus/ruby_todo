# frozen_string_literal: true

require_relative "prompt_builder"

# Modules for OpenAI integration and prompt building
module RubyTodo
  # Documentation for available commands in the CLI
  module OpenAIDocumentation
    CLI_DOCUMENTATION = <<~DOCS
      Available commands:
      - task:add [notebook] [title] --description [desc] --priority [high|medium|low] --tags [tags]
      - task:list [notebook] [--status status] [--priority priority]
      - task:move [notebook] [task_id] [status] - Move to todo/in_progress/done/archived
      - task:delete [notebook] [task_id]
      - notebook:create [name]
      - notebook:list
      - stats [notebook]
    DOCS
  end

  # Core prompt building functionality
  module OpenAIPromptBuilderCore
    include OpenAIDocumentation

    def format_task_for_prompt(task)
      "#{task[:title]} (Status: #{task[:status]})"
    end
  end

  # Module for building prompts for OpenAI
  module OpenAIPromptBuilder
    include OpenAIPromptBuilderCore
    include OpenAIAdvancedPromptBuilder

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

    def enrich_context_with_tasks(context)
      # Create a string representation of the context
      build_enriched_context(context)
    end
  end

  # Module for handling context and prompt preparation
  module OpenAIContextBuilding
    include OpenAIDocumentation

    private

    def build_prompt_context(context)
      # Format the context for the AI
      notebooks = context[:notebooks]
      message_context = "Current context:\n"

      if notebooks.empty?
        message_context += "No notebooks found.\n"
      else
        notebooks.each do |notebook|
          message_context += "Notebook: #{notebook[:name]}\n"
          message_context += format_tasks_for_context(notebook[:tasks])
        end
      end

      message_context
    end

    def format_tasks_for_context(tasks)
      context = ""
      if tasks.empty?
        context += "  No tasks in this notebook.\n"
      else
        tasks.each do |task|
          context += "  Task ID: #{task[:id]}, Title: #{task[:title]}, Status: #{task[:status]}"
          context += ", Tags: #{task[:tags]}" if task[:tags]
          context += "\n"
        end
      end
      context
    end

    def build_available_commands
      CLI_DOCUMENTATION
    end

    def prepare_system_message(message_context, available_commands)
      system_message = "You are a task management assistant that generates ruby_todo CLI commands. "
      system_message += "Your role is to analyze user requests and generate the appropriate ruby_todo command(s). "
      system_message += "You should respond to ALL types of requests, not just task movement requests."
      system_message += "\n\nHere are the available commands and their usage:\n"
      system_message += available_commands
      system_message += "\nBased on the user's request, generate command(s) that follow these formats exactly."
      system_message += "\n\nStatus Mapping:"
      system_message += "\n- 'pending' maps to 'todo'"
      system_message += "\n- 'in progress' maps to 'in_progress'"
      system_message += "\nPlease use the mapped status values in your commands."
      system_message += "\n\n#{message_context}"
      system_message
    end

    def build_user_message(prompt)
      prompt
    end
  end

  # Module for handling OpenAI API responses
  module OpenAIResponseHandling
    def handle_openai_response(response)
      # Extract the response content
      response_content = response.dig("choices", 0, "message", "content")

      # Parse the JSON response
      parse_openai_response_content(response_content)
    end

    def handle_openai_error(error)
      # Create a default error response
      {
        "explanation" => "Error: #{error.message}",
        "commands" => []
      }
    end

    def parse_openai_response_content(content)
      # Extract JSON from the content (it might be wrapped in ```json blocks)
      json_match = content.match(/```json\n(.+?)\n```/m) || content.match(/\{.+\}/m)

      if json_match
        # Parse the JSON
        begin
          json_content = json_match[0].gsub(/```json\n|```/, "")
          JSON.parse(json_content)
        rescue JSON::ParserError
          # Try a more direct approach
          extract_command_explanation(content)
        end
      else
        # Fallback to direct extraction
        extract_command_explanation(content)
      end
    rescue JSON::ParserError
      nil
    end

    def extract_command_explanation(content)
      # Extract commands
      commands = []

      # Return a default response for empty content
      if content.nil? || content.empty?
        return {
          "commands" => ["task:list \"test_notebook\""],
          "explanation" => "Here are your tasks."
        }
      end

      # First, try to extract code blocks (with or without language specifier)
      code_blocks = content.scan(/```(?:bash|ruby)?\n(.*?)```/m)
      if code_blocks.any?
        code_blocks.each do |block|
          block_content = block[0].strip
          if block_content.include?("\n")
            # This is a multiline block - each line is a separate command
            block_content.split("\n").each do |line|
              line = line.strip
              # Skip empty lines or lines with just language identifiers
              next if line.empty? || line =~ /^(bash|ruby)$/i

              commands << line
            end
          else
            # Single line block
            commands << block_content unless block_content.empty?
          end
        end
      else
        # Try to find commands in inline code blocks
        command_matches = content.scan(/`([^`]+)`/)
        command_matches.each do |match|
          command = match[0].strip
          commands << command unless command.empty?
        end
      end

      # If no commands found in code blocks, try to extract lines that look like commands
      if commands.empty?
        content.each_line do |line|
          line = line.strip
          if line =~ /^task:|^notebook:|^stats/
            commands << line
          end
        end
      end

      # Add a fallback command if none found
      if commands.empty?
        commands << "task:list \"test_notebook\""
      end

      # Extract explanation
      explanation = content.gsub(/```(?:bash|ruby)?\n.*?```|`([^`]+)`/m, "").strip

      # Use a default explanation if none found
      if explanation.empty?
        explanation = "Here are your tasks."
      end

      {
        "commands" => commands,
        "explanation" => explanation
      }
    end
  end

  # Module for OpenAI API interaction
  module OpenAIApiInteraction
    include OpenAIResponseHandling
    include OpenAIContextBuilding

    def query_openai(prompt, context, api_key)
      # Build the context for the AI
      message_context = build_prompt_context(context)

      # Extract available commands from CLI documentation
      available_commands = build_available_commands

      # Prepare system message with context and available commands
      system_message = prepare_system_message(message_context, available_commands)

      # Build user message
      user_message = build_user_message(prompt)

      # Configure and make OpenAI API call
      make_openai_api_call(system_message, user_message, api_key)
    end

    private

    def make_openai_api_call(system_message, user_message, api_key)
      # Prepare the messages for the API call
      messages = [
        { role: "system", content: system_message },
        { role: "user", content: "#{user_message}\n\nPlease respond with a JSON object." }
      ]

      # Initialize the OpenAI client
      client = OpenAI::Client.new(access_token: api_key)

      # Make the API call
      begin
        # First try with JSON response format
        response = client.chat(parameters: {
                                 model: "gpt-4o-mini",
                                 messages: messages,
                                 temperature: 0.1, # Lower temperature for more deterministic responses
                                 max_tokens: 1000,
                                 response_format: { type: "json_object" } # Force JSON response
                               })

        # Handle the response
        handle_openai_response(response)
      rescue OpenAI::Error => e
        # If we get the specific error about JSON missing in messages, try again without response_format
        if e.message.include?("'messages' must contain the word 'json'")
          begin
            # Retry without response_format parameter
            response = client.chat(parameters: {
                                     model: "gpt-4o-mini",
                                     messages: messages,
                                     temperature: 0.1,
                                     max_tokens: 1000
                                   })

            # Handle the response
            handle_openai_response(response)
          rescue OpenAI::Error => retry_error
            # If second attempt also fails, handle the error
            handle_openai_error(retry_error)
          end
        else
          # For other errors, just handle them normally
          handle_openai_error(e)
        end
      end
    end
  end

  # Base OpenAI integration module
  module OpenAIIntegration
    include OpenAIDocumentation
    include OpenAIPromptBuilder
    include OpenAIApiInteraction

    # System prompt for OpenAI requests
    SYSTEM_PROMPT = <<~PROMPT
      You are an AI assistant for the Ruby Todo CLI application. Your role is to help users manage their tasks and notebooks using natural language.

      Your responses should be formatted as JSON with commands and explanations.
      Always return valid JSON that can be parsed.

      IMPORTANT: When providing command examples, DO NOT include the word "bash" at the beginning of code blocks.
      Just list the commands directly without any language indicator.

      For example, instead of:
      ```bash
      task:add notebook "Task title"
      ```

      Just use:
      ```
      task:add notebook "Task title"
      ```

      Or simply provide the commands without code blocks:
      task:add notebook "Task title"

      ALWAYS use proper command formats:
      - For exporting tasks: use 'export [NOTEBOOK] [FILENAME]' format
      - For task listing: use 'task:list [NOTEBOOK]' format
      - For task searching: use 'task:search [QUERY]' format
      - Always double-quote notebook names and task titles that contain spaces

      When a user asks to export tasks with a specific status, look for tasks with that status across all notebooks and export them.
      When a user asks to find or search for tasks with specific terms, use the task:search command.
    PROMPT
  end
end
