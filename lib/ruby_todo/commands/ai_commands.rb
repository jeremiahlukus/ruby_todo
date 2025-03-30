# frozen_string_literal: true

module RubyTodo
  module AICommands
    def ai_ask(*prompt_args)
      prompt = prompt_args.join(" ")
      ai_command.ask(prompt, verbose: options[:verbose], api_key: options[:api_key])
    end

    def ai_configure
      ai_command.configure
    end

    private

    def ai_command
      @ai_command ||= AIAssistantCommand.new
    end
  end
end
