# frozen_string_literal: true

require_relative "ruby_todo/version"
require_relative "ruby_todo/database"
require_relative "ruby_todo/models/notebook"
require_relative "ruby_todo/models/task"
require_relative "ruby_todo/models/template"
require_relative "ruby_todo/formatters/display_formatter"
require_relative "ruby_todo/concerns/statistics"
require_relative "ruby_todo/concerns/task_filters"
require_relative "ruby_todo/concerns/import_export"
require_relative "ruby_todo/commands/notebook_commands"
require_relative "ruby_todo/commands/template_commands"
require_relative "ruby_todo/commands/ai_commands"
require_relative "ruby_todo/commands/ai_assistant"
require_relative "ruby_todo/ai_assistant/openai_integration"
require_relative "ruby_todo/cli"

module RubyTodo
  class Error < StandardError; end

  def self.start
    CLI.start(ARGV)
  end
end
