# frozen_string_literal: true

module RubyTodo
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
end
