# Implementation Guide: Adding AI Assistant to Ruby Todo

This guide outlines the specific steps to add AI assistant functionality to the Ruby Todo gem, allowing users to interact with the application using natural language through Claude or OpenAI.

## Step 1: Update the gemspec file

Edit `ruby_todo.gemspec` to add the required dependencies:

```ruby
# Runtime dependencies
spec.add_dependency "anthropic", "~> 0.1.0"  # For Claude API
spec.add_dependency "ruby-openai", "~> 6.3.0" # For OpenAI API
spec.add_dependency "dotenv", "~> 2.8"  # For API key management
```

## Step 2: Create the folder structure

```bash
mkdir -p lib/ruby_todo/commands
```

## Step 3: Create the AI Assistant command file

Create a new file at `lib/ruby_todo/commands/ai_assistant.rb` with the implementation from the plan document.

## Step 4: Update the CLI class

Edit `lib/ruby_todo/cli.rb` to add the AI Assistant command:

1. Add the require statement at the top:
```ruby
require_relative "commands/ai_assistant"
```

2. Register the subcommand inside the CLI class:
```ruby
# Register AI Assistant subcommand
desc "ai SUBCOMMAND", "Use AI assistant"
subcommand "ai", AIAssistantCommand
```

## Step 5: Create .env template

Create a `.env.template` file in the project root:

```
# Claude API key (if using Claude)
ANTHROPIC_API_KEY=your_claude_api_key_here

# OpenAI API key (if using OpenAI)
OPENAI_API_KEY=your_openai_api_key_here
```

Add `.env` to `.gitignore` to prevent accidental check-in of API keys.

## Step 6: Update README

Add the AI Assistant documentation to the README.md file:

1. Add "AI Assistant" to the Features list at the top
2. Add the full AI Assistant section after the Templates section

## Step 7: Create tests

Create tests for the AI Assistant functionality:

1. Create a new file `test/ai_assistant_test.rb`
2. Add unit tests for the AI Assistant command class
3. Add integration tests for the CLI integration
4. Add mock tests for API interactions

## Step 8: Install and test

1. Install the updated gem: `bundle exec rake install`
2. Run `ruby_todo ai configure` to set up your API key
3. Test with a simple prompt: `ruby_todo ai ask "Create a task in the Work notebook"`

## Usage Examples

Here are some examples of how to use the AI assistant:

1. Configure the AI assistant:
```bash
ruby_todo ai configure
```

2. Create a task using natural language:
```bash
ruby_todo ai ask "Add a high priority task to update documentation in my Work notebook due next Friday"
```

3. Move tasks to a different status:
```bash
ruby_todo ai ask "Move all tasks related to documentation in my Work notebook to in_progress"
```

4. Generate a JSON import file:
```bash
ruby_todo ai ask "Create a JSON file with 5 tasks for my upcoming vacation planning"
```

5. Get task statistics:
```bash
ruby_todo ai ask "Give me a summary of my Work notebook"
```

6. Search for specific tasks:
```bash
ruby_todo ai ask "Find all high priority tasks that are overdue"
```

## Troubleshooting

1. API key issues:
   - Ensure your API key is correctly configured
   - Try passing the API key directly: `ruby_todo ai ask "..." --api-key=your_key`

2. JSON parsing errors:
   - Enable verbose mode to see the raw response: `ruby_todo ai ask "..." --verbose`
   - Check if the model is generating valid JSON

3. Permission issues:
   - Check file permissions on `~/.ruby_todo/ai_config.json`

4. Missing dependencies:
   - Run `bundle install` to ensure all gems are installed

5. Command not found:
   - Ensure the gem is properly installed: `gem list ruby_todo`
   - Reinstall if necessary: `gem uninstall ruby_todo && bundle exec rake install` 