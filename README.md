# Ruby Todo

A powerful CLI todo list manager with multi-notebook support and automated task management.

## Features

- Multiple notebook support
- Task categorization (todo, in progress, done, archived)
- Advanced task features (descriptions, due dates, priorities, tags)
- Automated task archiving
- Task search and filtering
- Task statistics and analytics
- Task export and import (JSON, CSV)
- Task templates with placeholders
- AI assistant for natural language task management
- Beautiful CLI interface with colored output
- SQLite database for persistent storage

## Installation

Add this line to your application's Gemfile:

```ruby
gem "ruby_todo"
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install ruby_todo
```

## Quick Start

After installing the gem:

1. Initialize the application:
   ```bash
   $ ruby_todo init
   ```

2. Create your first notebook:
   ```bash
   $ ruby_todo notebook create "Personal"
   ```

3. Add your first task:
   ```bash
   $ ruby_todo task add "Personal" "My first task"
   ```

4. List your tasks:
   ```bash
   $ ruby_todo task list "Personal"
   ```

All `ruby_todo` commands can be run from anywhere in your terminal as they're installed globally with the gem.

## Usage

### Initialization

Initialize Ruby Todo:
```bash
$ ruby_todo init
```

### Notebook Management

Create a new notebook:
```bash
$ ruby_todo notebook create "Work"
```

List all notebooks:
```bash
$ ruby_todo notebook list
```

### Task Management

Add a task to a notebook:
```bash
$ ruby_todo task add "Work" "Complete project documentation"
```

Add a task with additional details:
```bash
$ ruby_todo task add "Work" "Complete project documentation" --description "Write the API documentation for the new features" --due_date "2024-04-10 14:00" --priority "high" --tags "project,documentation,urgent"
```

List tasks in a notebook:
```bash
$ ruby_todo task list "Work"
```

Filter tasks by status:
```bash
$ ruby_todo task list "Work" --status "in_progress"
```

Show only overdue tasks:
```bash
$ ruby_todo task list "Work" --overdue
```

Show only high priority tasks:
```bash
$ ruby_todo task list "Work" --priority "high"
```

Filter by tags:
```bash
$ ruby_todo task list "Work" --tags "urgent,important"
```

View detailed information about a task:
```bash
$ ruby_todo task show "Work" 1
```

Edit a task:
```bash
$ ruby_todo task edit "Work" 1 --title "New title" --priority "medium" --due_date "2024-04-15 10:00"
```

Move a task to a different status:
```bash
$ ruby_todo task move "Work" 1 "in_progress"
```

Delete a task:
```bash
$ ruby_todo task delete "Work" 1
```

### Search

Search for tasks across all notebooks:
```bash
$ ruby_todo task search "documentation"
```

Search within a specific notebook:
```bash
$ ruby_todo task search "documentation" --notebook "Work"
```

### Statistics

View statistics for all notebooks:
```bash
$ ruby_todo stats
```

View statistics for a specific notebook:
```bash
$ ruby_todo stats "Work"
```

### Export and Import

Export tasks from a notebook to JSON:
```bash
$ ruby_todo export "Work" "work_export"
```

Export all notebooks:
```bash
$ ruby_todo export --all "full_export"
```

Export to CSV format:
```bash
$ ruby_todo export "Work" "work_export" --format csv
```

Import tasks from a file:
```bash
$ ruby_todo import "work_export.json"
```

Import to a specific notebook:
```bash
$ ruby_todo import "work_export.json" --notebook "New Work"
```

### Task Templates

Create a template:
```bash
$ ruby_todo template create "Weekly Report" --title "Weekly Report {week}" --description "Prepare weekly report for week {week}" --priority "high" --tags "report,weekly" --due_date_offset "5d"
```

List all templates:
```bash
$ ruby_todo template list
```

## Template Placeholders

Templates support the following placeholder types:

- Custom placeholders: `{name}`, `{week}`, etc. (replaced when using template)
- Date placeholders: 
  - `{today}`: Current date
  - `{tomorrow}`: Next day
  - `{yesterday}`: Previous day
  - `{weekday}`: Current day of week
  - `{month}`: Current month
  - `{year}`: Current year

## AI Assistant

Ruby Todo includes an AI assistant powered by OpenAI's gpt-4o-mini model that can help you manage your tasks using natural language.

### Configuration

Configure your AI assistant:
```bash
$ ruby_todo ai configure
```

### API Key Options

There are two ways to provide your OpenAI API key:

1. **Configure once with the setup command** (recommended):
   ```bash
   $ ruby_todo ai configure
   ```
   This prompts you to enter your OpenAI API key and securely saves it in `~/.ruby_todo/ai_config.json`.

2. **Use environment variables**:
   ```bash
   $ export OPENAI_API_KEY=your_api_key_here
   $ ruby_todo ai ask "your prompt"
   ```

3. **Pass the API key directly in the command**:
   ```bash
   $ ruby_todo ai ask "your prompt" --api-key=your_api_key_here
   ```

### Using the AI Assistant

Ask the AI assistant to perform actions:
```bash
$ ruby_todo ai ask "Create a new task in my Work notebook to update the documentation by next Friday"
```

```bash
$ ruby_todo ai ask "Move all tasks related to the API project to in_progress status"
```

```bash
$ ruby_todo ai ask "Show me all high priority tasks"
```

```bash
$ ruby_todo ai ask "Create a JSON to import 5 new tasks for my upcoming vacation"
```

#### Bulk Operations

The AI assistant can perform bulk operations on all tasks:

```bash
$ ruby_todo ai ask "Move all tasks to todo"
```

```bash
$ ruby_todo ai ask "Move all tasks to in_progress"
```

```bash
$ ruby_todo ai ask "Show me all task statistics"
```

Pass in an API key directly (if not configured):
```bash
$ ruby_todo ai ask "What tasks are overdue?" --api-key=your_api_key_here --api=claude
```

Enable verbose mode to see full AI responses:
```bash
$ ruby_todo ai ask "Summarize my Work notebook" --verbose
```

## Development