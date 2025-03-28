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

      say "\nSystem prompt:\n#{messages.first[:content]}\n" if options[:verbose]
      say "\nUser prompt:\n#{prompt}\n" if options[:verbose]

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
      say "\nMaking OpenAI API call...".blue if options[:verbose]
      client = OpenAI::Client.new(access_token: api_key)
      messages = build_messages(prompt, context)
      say "Sending request to OpenAI..." if options[:verbose]

      response = client.chat(parameters: build_openai_parameters(messages))

      say "\nOpenAI API call completed".green if options[:verbose]

      log_raw_response(response) if options[:verbose]

      parsed_response = handle_openai_response(response)

      log_parsed_response(parsed_response) if options[:verbose] && parsed_response

      parsed_response
    end

    private

    def build_openai_parameters(messages)
      {
        model: "gpt-4o-mini",
        messages: messages,
        temperature: 0.7,
        max_tokens: 500
      }
    end

    def log_raw_response(response)
      say "\n=== RAW OPENAI RESPONSE ==="
      if response && response.dig("choices", 0, "message", "content")
        say response["choices"][0]["message"]["content"]
      else
        say "No content in response"
      end
      say "=== END RAW RESPONSE ===\n"
    end

    def log_parsed_response(parsed_response)
      say "\n=== PARSED RESPONSE DETAILS ==="
      say "Commands array type: #{parsed_response["commands"].class}"
      say "Number of commands: #{parsed_response["commands"].size}"
      parsed_response["commands"].each_with_index do |cmd, i|
        say "Command #{i + 1}: '#{cmd}'"
      end
      say "=== END RESPONSE DETAILS ===\n"
    end

    def handle_openai_response(response)
      return nil unless response&.dig("choices", 0, "message", "content")

      content = response["choices"][0]["message"]["content"]
      say "\nAI Response:\n#{content}\n" if options[:verbose]

      parse_json_from_content(content)
    end

    def parse_json_from_content(content)
      # Process the content to extract JSON
      json_content = process_json_content(content)

      say "\nProcessed JSON content:\n#{json_content}\n" if options[:verbose]

      # Parse the JSON
      result = JSON.parse(json_content)

      # Ensure required keys exist
      validate_and_fix_json_result(result)

      result
    rescue JSON::ParserError => e
      handle_json_parse_error(content, e)
    end

    def process_json_content(content)
      # Remove markdown formatting if present
      json_content = content.gsub(/```(?:json)?\n(.*?)\n```/m, '\1')
      # Strip any leading/trailing whitespace, braces are required
      json_content = json_content.strip
      # Add braces if they're missing
      json_content = "{#{json_content}}" unless json_content.start_with?("{") && json_content.end_with?("}")

      json_content
    end

    def validate_and_fix_json_result(result)
      # Ensure we have the required keys
      if !result.key?("commands") || !result["commands"].is_a?(Array)
        say "Warning: AI response missing 'commands' array. Adding empty array.".yellow if options[:verbose]
        result["commands"] = []
      end

      if !result.key?("explanation") || !result["explanation"].is_a?(String)
        say "Warning: AI response missing 'explanation'. Adding default.".yellow if options[:verbose]
        result["explanation"] = "Command execution completed."
      end
    end

    def handle_json_parse_error(content, error)
      say "Error parsing AI response: #{error.message}".red if options[:verbose]

      # Try to extract commands from plain text as fallback
      commands = extract_commands_from_text(content)

      if commands.any?
        say "Extracted #{commands.size} commands from text response".yellow if options[:verbose]
        return {
          "commands" => commands,
          "explanation" => "Commands extracted from non-JSON response."
        }
      end

      nil
    end

    def extract_commands_from_text(content)
      commands = []
      content.scan(/ruby_todo\s+\S+(?:\s+\S+)*/) do |cmd|
        commands << cmd.strip
      end
      commands
    end
  end
end
