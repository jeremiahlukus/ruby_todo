# frozen_string_literal: true

module RubyTodo
  module AIAssistant
    # Module for natural language task creation
    module TaskCreator
      # Handle natural language task creation
      def handle_natural_language_task_creation(prompt, api_key)
        # Get the default notebook
        notebook_name = default_notebook_name

        # Extract task description from prompt
        task_description = extract_task_description(prompt)

        # Generate task details using AI
        task_details = generate_task_details(task_description, api_key)

        # Create the task
        create_task_from_details(notebook_name, task_details)
      end

      # Get the default notebook name or fallback to "default"
      def default_notebook_name
        default_notebook = RubyTodo::Notebook.default_notebook
        default_notebook ? default_notebook.name : "default"
      end

      # Extract task description from the prompt
      def extract_task_description(prompt)
        if prompt =~ /create(?:\s+a)?\s+(?:new\s+)?task\s+(?:to|for|about)\s+(.+)/i
          Regexp.last_match(1).strip
        else
          ""
        end
      end

      # Generate task details using AI
      def generate_task_details(task_description, api_key)
        # Build the query for AI
        task_query = build_task_query(task_description)

        # Query OpenAI for task details
        content = query_openai_for_task_details(task_query, api_key)

        # Parse the response
        parse_task_details_response(content, task_description)
      end

      # Build the query to send to OpenAI
      def build_task_query(task_description)
        "Generate a professional task with the following information:\n" \
          "Task description: #{task_description}\n" \
          "Please generate a JSON response with these fields:\n" \
          "- title: A concise, professional title for the task\n" \
          "- description: A detailed description of what the task involves\n" \
          "- priority: Suggested priority (high, medium, or low)\n" \
          "- tags: Relevant tags as a comma-separated string"
      end

      # Query OpenAI for task details
      def query_openai_for_task_details(task_query, api_key)
        # Use mock response for tests
        if ENV["RUBY_TODO_ENV"] == "test"
          return mock_task_details_response(task_query)
        end

        client = OpenAI::Client.new(access_token: api_key)
        messages = [
          { role: "system", content: "You are a task management assistant that generates professional task details." },
          { role: "user", content: task_query }
        ]

        say "Generating professional task details..." if @options[:verbose]

        response = client.chat(parameters: {
                                 model: "gpt-4o-mini",
                                 messages: messages,
                                 temperature: 0.7,
                                 max_tokens: 500
                               })

        response["choices"][0]["message"]["content"]
      end

      # Mock response for task details in tests
      def mock_task_details_response(task_query)
        if task_query.include?("add newrelic to the questions engine app")
          <<~JSON
            ```json
            {
              "title": "Add New Relic monitoring to Questions Engine App",
              "description": "Integrate New Relic performance monitoring into the Questions Engine application to track performance metrics and identify bottlenecks.",
              "priority": "high",
              "tags": "monitoring,newrelic,performance"
            }
            ```
          JSON
        else
          # Generic mock response for other task queries
          <<~JSON
            ```json
            {
              "title": "Task from #{task_query}",
              "description": "Auto-generated task from user query",
              "priority": "medium",
              "tags": "auto-generated"
            }
            ```
          JSON
        end
      end

      # Parse the OpenAI response for task details
      def parse_task_details_response(content, task_description)
        # Try to extract JSON from the response
        json_match = content.match(/```json\n(.+?)\n```/m) || content.match(/\{.+\}/m)
        if json_match
          json_str = json_match[0].gsub(/```json\n|```/, "")
          JSON.parse(json_str)
        else
          extract_task_details_with_regex(content, task_description)
        end
      rescue JSON::ParserError
        extract_task_details_with_regex(content, task_description)
      end

      # Extract task details using regex as a fallback
      def extract_task_details_with_regex(content, task_description)
        title_match = content.match(/title["\s:]+([^"]+)["]/i)
        desc_match = content.match(/description["\s:]+([^"]+)["]/i)
        priority_match = content.match(/priority["\s:]+([^"]+)["]/i)
        tags_match = content.match(/tags["\s:]+([^"]+)["]/i)

        {
          "title" => title_match ? title_match[1] : "Task from #{task_description}",
          "description" => desc_match ? desc_match[1] : task_description,
          "priority" => priority_match ? priority_match[1] : "medium",
          "tags" => tags_match ? tags_match[1] : ""
        }
      end

      # Create a task from the generated details
      def create_task_from_details(notebook_name, task_details)
        # Ensure we have a valid notebook
        notebook = RubyTodo::Notebook.find_by(name: notebook_name)
        unless notebook
          # Try to create the notebook if it doesn't exist
          RubyTodo::CLI.start(["notebook:create", notebook_name])
          notebook = RubyTodo::Notebook.find_by(name: notebook_name)
        end

        # Use default notebook as fallback if we couldn't create or find the specified one
        unless notebook
          default_notebook = RubyTodo::Notebook.default_notebook
          notebook_name = default_notebook ? default_notebook.name : "default"
          # Create default notebook if it doesn't exist
          unless RubyTodo::Notebook.find_by(name: notebook_name)
            RubyTodo::CLI.start(["notebook:create",
                                 notebook_name])
          end
        end

        args = ["task:add", notebook_name, task_details["title"]]
        args << "--description" << task_details["description"] if task_details["description"]
        args << "--priority" << task_details["priority"] if task_details["priority"]
        args << "--tags" << task_details["tags"] if task_details["tags"]

        RubyTodo::CLI.start(args)
      rescue StandardError => e
        say "Error creating task: #{e.message}".red
        say "Attempting simplified task creation...".yellow

        # Fallback to simplified command
        begin
          RubyTodo::CLI.start(["task:add", notebook_name, task_details["title"]])
        rescue StandardError => e2
          say "Failed to create task: #{e2.message}".red
        end
      end
    end
  end
end
