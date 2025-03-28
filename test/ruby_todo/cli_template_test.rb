# frozen_string_literal: true

require "test_helper"
require "stringio"

module RubyTodo
  class CLITemplateTest < Minitest::Test
    def setup
      Database.setup
      @notebook = Notebook.create(name: "Test Notebook")
      @cli = CLI.new
    end

    def teardown
      # Clean up database
      Template.delete_all
      Task.delete_all
      Notebook.delete_all
    end

    def test_template_functionality_in_cli
      # Create a template
      template = Template.create(
        name: "Meeting",
        title_pattern: "Meeting with {person}",
        description_pattern: "Discuss {topic} with {person}",
        priority: "medium",
        due_date_offset: "1d"
      )

      # Create a notebook
      notebook = Notebook.create(name: "Work")

      # Create a task using the template directly
      task = template.create_task(notebook, {
                                    "person" => "John",
                                    "topic" => "Project X"
                                  })

      # Verify task was created correctly
      assert_predicate task, :valid?
      assert_equal "Meeting with John", task.title
      assert_equal "Discuss Project X with John", task.description
      assert_equal "medium", task.priority
      assert_equal notebook.id, task.notebook_id

      # Verify template can be found
      found_template = Template.find_by(name: "Meeting")
      assert found_template
      assert_equal template.id, found_template.id

      # Test template deletion
      assert found_template.destroy
      assert_nil Template.find_by(name: "Meeting")
    end

    def test_template_list_functionality
      # Create some templates first
      Template.create(name: "Template 1", title_pattern: "Task 1")
      Template.create(name: "Template 2", title_pattern: "Task 2")

      # Get all templates
      templates = Template.all

      # Verify templates exist
      assert_includes templates.map(&:name), "Template 1"
      assert_includes templates.map(&:name), "Template 2"
      assert_includes templates.map(&:title_pattern), "Task 1"
      assert_includes templates.map(&:title_pattern), "Task 2"
    end

    def test_template_edge_cases
      # Test creation with missing required attributes
      template = Template.new(name: "Invalid")
      refute_predicate template, :valid?
      assert_includes template.errors[:title_pattern], "can't be blank"

      # Test uniqueness constraint
      Template.create(name: "Unique", title_pattern: "Task")
      duplicate = Template.new(name: "Unique", title_pattern: "Another Task")
      refute_predicate duplicate, :valid?
      assert_includes duplicate.errors[:name], "has already been taken"

      # Test with invalid due date offset
      template = Template.create(
        name: "Invalid Due Date",
        title_pattern: "Task",
        due_date_offset: "invalid"
      )

      # Should create valid template but due_date should be nil when task is created
      task = template.create_task(@notebook)
      assert_predicate task, :valid?
      assert_nil task.due_date
    end

    def test_template_with_notebook_association
      notebook = Notebook.create(name: "Project Notebook")
      template = Template.create(
        name: "Project Template",
        title_pattern: "Project Task",
        notebook: notebook
      )

      assert_predicate template, :valid?
      assert_equal notebook.id, template.notebook_id

      # Test creating task with default notebook
      task = template.create_task(notebook)
      assert_equal notebook.id, task.notebook_id

      # Test creating task with different notebook
      another_notebook = Notebook.create(name: "Another Notebook")
      task = template.create_task(another_notebook)
      assert_equal another_notebook.id, task.notebook_id
    end

    def test_template_placeholders
      template = Template.create(
        name: "Placeholders",
        title_pattern: "Task for {weekday}",
        description_pattern: "Created on {today} for {project}"
      )

      # Test with replacements
      task = template.create_task(@notebook, { "project" => "Alpha" })

      assert_predicate task, :valid?
      assert_match(/Task for \w+/, task.title) # Should contain a weekday
      assert_match(/Created on \d{4}-\d{2}-\d{2} for Alpha/, task.description)

      # Test date placeholders
      today = Date.today
      assert_includes task.description, today.strftime("%Y-%m-%d")
    end
  end
end
