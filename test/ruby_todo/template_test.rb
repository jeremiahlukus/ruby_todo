# frozen_string_literal: true

require "test_helper"

module RubyTodo
  class TemplateTest < Minitest::Test
    def setup
      Database.setup
      @notebook = Notebook.create(name: "Test Notebook")
    end

    def teardown
      Template.delete_all
      Task.delete_all
      Notebook.delete_all
    end

    def test_create_template
      template = Template.create(
        name: "Test Template",
        title_pattern: "Test Task {param1}",
        description_pattern: "Description for {param1}",
        tags_pattern: "test,{param1}",
        priority: "high",
        due_date_offset: "2d"
      )

      assert_predicate template, :valid?
      assert_equal "Test Template", template.name
      assert_equal "Test Task {param1}", template.title_pattern
      assert_equal "Description for {param1}", template.description_pattern
      assert_equal "test,{param1}", template.tags_pattern
      assert_equal "high", template.priority
      assert_equal "2d", template.due_date_offset
    end

    def test_validates_name_presence
      template = Template.new(
        title_pattern: "Test Task"
      )

      refute_predicate template, :valid?
      assert_includes template.errors[:name], "can't be blank"
    end

    def test_validates_title_pattern_presence
      template = Template.new(
        name: "Test Template"
      )

      refute_predicate template, :valid?
      assert_includes template.errors[:title_pattern], "can't be blank"
    end

    def test_validates_name_uniqueness
      Template.create(
        name: "Weekly Report",
        title_pattern: "Weekly Report"
      )

      duplicate = Template.new(
        name: "Weekly Report",
        title_pattern: "Weekly Report"
      )

      refute_predicate duplicate, :valid?
      assert_includes duplicate.errors[:name], "has already been taken"
    end

    def test_create_task_from_template
      template = Template.create(
        name: "Test Template",
        title_pattern: "Task for {project}",
        description_pattern: "Description for {project} on {today}",
        tags_pattern: "test,{project}",
        priority: "high",
        due_date_offset: "2d"
      )

      task = template.create_task(@notebook, { project: "Alpha" })

      assert_predicate task, :valid?
      assert_equal "Task for Alpha", task.title
      assert_includes task.description, "Description for Alpha on"
      assert_includes task.description, Date.today.strftime("%Y-%m-%d")
      assert_equal "test,Alpha", task.tags
      assert_equal "high", task.priority
      assert_equal "todo", task.status
      assert_operator task.due_date, :>, Time.now
      assert_operator task.due_date, :<, Time.now + (3 * 24 * 60 * 60)
    end

    def test_process_pattern_with_date_placeholders
      template = Template.create(
        name: "Date Test",
        title_pattern: "Task for {weekday} on {today}, before {tomorrow}, after {yesterday} in {month} {year}",
        priority: "medium"
      )

      today = Date.today
      task = template.create_task(@notebook)

      assert_predicate task, :valid?
      assert_includes task.title, "Task for #{today.strftime("%A")}"
      assert_includes task.title, "on #{today.strftime("%Y-%m-%d")}"
      assert_includes task.title, "before #{(today + 1).strftime("%Y-%m-%d")}"
      assert_includes task.title, "after #{(today - 1).strftime("%Y-%m-%d")}"
      assert_includes task.title, "in #{today.strftime("%B")}"
      assert_includes task.title, today.strftime("%Y")
    end

    def test_calculate_due_date
      # Test days
      template = Template.create(
        name: "Days Test",
        title_pattern: "Task Due in Days",
        due_date_offset: "3d"
      )
      task = template.create_task(@notebook)
      assert_operator task.due_date, :>, Time.now + (2 * 24 * 60 * 60)
      assert_operator task.due_date, :<, Time.now + (4 * 24 * 60 * 60)

      # Test weeks
      template = Template.create(
        name: "Weeks Test",
        title_pattern: "Task Due in Weeks",
        due_date_offset: "1w"
      )
      task = template.create_task(@notebook)
      assert_operator task.due_date, :>, Time.now + (6 * 24 * 60 * 60)
      assert_operator task.due_date, :<, Time.now + (8 * 24 * 60 * 60)

      # Test hours
      template = Template.create(
        name: "Hours Test",
        title_pattern: "Task Due in Hours",
        due_date_offset: "5h"
      )
      task = template.create_task(@notebook)
      assert_operator task.due_date, :>, Time.now + (4 * 60 * 60)
      assert_operator task.due_date, :<, Time.now + (6 * 60 * 60)
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
      assert_equal "Project Notebook", template.notebook.name
    end

    def test_task_creation_inherits_template_notebook
      notebook = Notebook.create(name: "Default Notebook")
      template = Template.create(
        name: "Default Template",
        title_pattern: "Default Task",
        notebook: notebook
      )

      # Creating a task with a different notebook should use the specified notebook
      another_notebook = Notebook.create(name: "Another Notebook")
      task = template.create_task(another_notebook)

      assert_equal another_notebook.id, task.notebook_id
      assert_equal "Another Notebook", task.notebook.name
    end

    def test_invalid_due_date_offset_format
      template = Template.create(
        name: "Invalid Due Date",
        title_pattern: "Invalid Due Date Task",
        due_date_offset: "invalid"
      )

      task = template.create_task(@notebook)
      assert_predicate task, :valid?
      assert_nil task.due_date
    end

    def test_months_and_years_due_date_offset
      # Test months
      template = Template.create(
        name: "Months Test",
        title_pattern: "Task Due in Months",
        due_date_offset: "1m"
      )
      task = template.create_task(@notebook)
      assert_operator task.due_date, :>, Time.now + (28 * 24 * 60 * 60)
      assert_operator task.due_date, :<, Time.now + (32 * 24 * 60 * 60)

      # Test years
      template = Template.create(
        name: "Years Test",
        title_pattern: "Task Due in Years",
        due_date_offset: "1y"
      )
      task = template.create_task(@notebook)
      assert_operator task.due_date, :>, Time.now + (360 * 24 * 60 * 60)
      assert_operator task.due_date, :<, Time.now + (370 * 24 * 60 * 60)
    end

    def test_complex_replacements
      template = Template.create(
        name: "Complex Template",
        title_pattern: "{prefix}: {item} ({count})",
        description_pattern: "Need to handle {item}. Quantity: {count}, Priority: {priority_level}",
        tags_pattern: "{category},{priority_level}"
      )

      replacements = {
        "prefix" => "TODO",
        "item" => "Buy groceries",
        "count" => "5",
        "priority_level" => "urgent",
        "category" => "shopping"
      }

      task = template.create_task(@notebook, replacements)

      assert_equal "TODO: Buy groceries (5)", task.title
      assert_equal "Need to handle Buy groceries. Quantity: 5, Priority: urgent", task.description
      assert_equal "shopping,urgent", task.tags
    end

    def test_replacements_with_special_characters
      template = Template.create(
        name: "Special Chars",
        title_pattern: "Task: {item} with {special}",
        description_pattern: "{special} details for {item}"
      )

      replacements = {
        "item" => "Project X",
        "special" => "* & $ # @ ! ?"
      }

      task = template.create_task(@notebook, replacements)

      assert_equal "Task: Project X with * & $ # @ ! ?", task.title
      assert_equal "* & $ # @ ! ? details for Project X", task.description
    end

    def test_missing_replacements_leave_placeholders
      template = Template.create(
        name: "Missing Replacements",
        title_pattern: "Task for {project} assigned to {person}",
        description_pattern: "{person} should work on {project} by {deadline}"
      )

      replacements = { "project" => "Alpha Project" }

      task = template.create_task(@notebook, replacements)

      assert_equal "Task for Alpha Project assigned to {person}", task.title
      assert_equal "{person} should work on Alpha Project by {deadline}", task.description
    end
  end
end
