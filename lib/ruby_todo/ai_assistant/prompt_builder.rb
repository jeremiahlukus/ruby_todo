# frozen_string_literal: true

module RubyTodo
  # Module for building advanced prompts for OpenAI
  module OpenAIAdvancedPromptBuilder
    # Extract task-related information from the prompt
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

    # Build a more detailed context with task information
    def build_enriched_context(context)
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

    # Build system prompt for specialized task types
    def build_task_creation_prompt(context)
      <<~PROMPT
        You are an AI assistant for the Ruby Todo CLI application.
        Your role is to help users manage their tasks and notebooks using natural language.

        Available commands:
        - task:add [notebook] [title] --description [description] --tags [comma,separated,tags] - Create a new task
        - task:move [notebook] [task_id] [status] - Move a task to a new status (todo/in_progress/done/archived)

        IMPORTANT: When creating tasks, the exact format must be:
        task:add "notebook_name" "task_title" --description "description" --priority level --tags "tags"

        Current context:
        #{context.to_json}
      PROMPT
    end
  end
end
