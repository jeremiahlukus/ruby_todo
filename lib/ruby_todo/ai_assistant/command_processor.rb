# frozen_string_literal: true

require_relative "param_extractor"

module RubyTodo
  module AIAssistant
    # Helper module for processing task-related commands
    module CommandProcessor
      include ParamExtractor

      # Process task add commands
      def process_task_add(cmd)
        # More specific patterns first
        case cmd
        when /task:add\s+"([^"]+)"\s+"([^"]+)"(?:\s+(.*))?/, /task:add\s+'([^']+)'\s+'([^']+)'(?:\s+(.*))?/,
             /task:add\s+([^\s"']+)\s+"([^"]+)"(?:\s+(.*))?/, /task:add\s+([^\s"']+)\s+'([^']+)'(?:\s+(.*))?/

          notebook_name = Regexp.last_match(1)
          title = Regexp.last_match(2)
          params = Regexp.last_match(3)

          cli_args = ["task:add", notebook_name, title]

          # Extract optional parameters
          extract_task_params(params, cli_args) if params

          RubyTodo::CLI.start(cli_args)
        # Handle cases where quotes might be missing or mixed
        when /task:add\s+([^\s]+)\s+([^\s-][^-]+?)(?:\s+(.*))?/
          notebook_name = Regexp.last_match(1).gsub(/["']/, "")  # Remove any quotes
          title = Regexp.last_match(2).gsub(/["']/, "")          # Remove any quotes
          params = Regexp.last_match(3)

          cli_args = ["task:add", notebook_name, title]

          # Process parameters
          extract_task_params(params, cli_args) if params

          RubyTodo::CLI.start(cli_args)
        # Handle missing notebook name by using default notebook
        when /task:add\s+"([^"]+)"(?:\s+(.*))?/, /task:add\s+'([^']+)'(?:\s+(.*))?/
          title = Regexp.last_match(1)
          params = Regexp.last_match(2)

          # Get default notebook
          default_notebook = RubyTodo::Notebook.default_notebook
          notebook_name = default_notebook ? default_notebook.name : "default"

          cli_args = ["task:add", notebook_name, title]

          # Process parameters
          extract_task_params(params, cli_args) if params

          RubyTodo::CLI.start(cli_args)
        else
          say "Invalid task:add command format".red
          message = "Expected: task:add \"notebook_name\" \"task_title\" [--description \"desc\"] " \
                    "[--priority level][--tags \"tags\"]"
          say message.yellow
        end
      end

      # Process task move commands
      def process_task_move(cmd)
        if cmd =~ /task:move\s+"([^"]+)"\s+(\d+)\s+(\w+)/ || cmd =~ /task:move\s+([^\s"]+)\s+(\d+)\s+(\w+)/
          notebook_name = Regexp.last_match(1)
          task_id = Regexp.last_match(2)
          status = Regexp.last_match(3)
          cli_args = ["task:move", notebook_name, task_id, status]
          RubyTodo::CLI.start(cli_args)
        else
          say "Invalid task:move command format".red
        end
      end

      # Process task list commands
      def process_task_list(cmd)
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

      # Process task delete commands
      def process_task_delete(cmd)
        if cmd =~ /task:delete\s+"([^"]+)"\s+(\d+)/
          notebook_name = Regexp.last_match(1)
          task_id = Regexp.last_match(2)
          cli_args = ["task:delete", notebook_name, task_id]
          RubyTodo::CLI.start(cli_args)
        else
          say "Invalid task:delete command format".red
        end
      end

      # Process notebook create commands
      def process_notebook_create(cmd)
        parts = cmd.split(/\s+/)
        return unless parts.size >= 2

        notebook_name = parts[1]
        cli_args = ["notebook:create", notebook_name]
        RubyTodo::CLI.start(cli_args)
      end

      # Process notebook list commands
      def process_notebook_list(_cmd)
        RubyTodo::CLI.start(["notebook:list"])
      end

      # Process stats commands
      def process_stats(cmd)
        parts = cmd.split(/\s+/)
        cli_args = ["stats"] + parts[1..]
        RubyTodo::CLI.start(cli_args)
      end
    end
  end
end
