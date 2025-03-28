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

Show template details:
```bash
$ ruby_todo template show "Weekly Report"
```

Use a template to create a task:
```bash
$ ruby_todo template use "Weekly Report" "Work" --replacements week="12"
```

Delete a template:
```bash
$ ruby_todo template delete "Weekly Report"
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

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `rake test` to run the tests. You can also run `rubocop` to check the code style.

To install this gem onto your local machine, run `bundle exec rake install`.

### CI/CD

This project uses GitHub Actions for continuous integration and delivery:

- **CI Workflow**: Runs tests and RuboCop on multiple Ruby versions for every push and pull request
- **Release Workflow**: Automatically increments version number, updates CHANGELOG, creates a GitHub release, and publishes to RubyGems when code is pushed to the main branch

To release a new version, just merge your changes to the main branch. The automation will:
1. Increment the patch version
2. Update the CHANGELOG.md file
3. Run tests to ensure everything works
4. Build and publish the gem to RubyGems
5. Create a GitHub release

For manual releases or version changes (major or minor), update the version in `lib/ruby_todo/version.rb` before merging to main.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jeremiahparrack/ruby_todo.

## License

The gem is available as open source under the terms of the MIT License.

## Troubleshooting

### Command not found after installation

If you see "command not found" after installing the gem, check the following:

1. Verify the gem is installed:
   ```bash
   $ gem list ruby_todo
   ```

2. Check your gem installation path:
   ```bash
   $ gem environment
   ```

3. Make sure your PATH includes the gem bin directory shown in the environment output.

4. You may need to run:
   ```bash
   $ rbenv rehash  # If using rbenv
   ```
   or
   ```bash
   $ rvm rehash    # If using RVM
   ```

### Database Issues

If you encounter database issues:

1. Try resetting the database:
   ```bash
   $ rm ~/.ruby_todo/ruby_todo.db
   $ ruby_todo init
   ```

2. Check file permissions:
   ```bash
   $ ls -la ~/.ruby_todo/
   ```

### Getting Help

Run any command with `--help` to see available options:

```bash
$ ruby_todo --help
$ ruby_todo task add --help
```
