# frozen_string_literal: true

module RubyTodo
  module TemplateDisplay
    def display_template_list(templates)
      if templates.empty?
        puts "No templates found. Create one with 'ruby_todo template create NAME'"
        return
      end

      table = TTY::Table.new(
        header: ["ID", "Name", "Title Pattern", "Notebook", "Priority", "Due Date Offset"],
        rows: templates.map do |template|
          [
            template.id,
            template.name,
            template.title_pattern,
            template.notebook&.name || "None",
            template.priority || "None",
            template.due_date_offset || "None"
          ]
        end
      )

      puts table.render(:unicode, padding: [0, 1])
    end

    def display_template_details(template)
      puts "Template Details:"
      puts "ID: #{template.id}"
      puts "Name: #{template.name}"
      puts "Notebook: #{template.notebook&.name || "None"}"
      puts "Title Pattern: #{template.title_pattern}"
      puts "Description Pattern: #{template.description_pattern || "None"}"
      puts "Tags Pattern: #{template.tags_pattern || "None"}"
      puts "Priority: #{template.priority || "None"}"
      puts "Due Date Offset: #{template.due_date_offset || "None"}"
      puts "Created At: #{template.created_at}"
      puts "Updated At: #{template.updated_at}"
    end
  end

  module TemplateCommands
    include TemplateDisplay

    def template_create(name)
      notebook = nil
      if options[:notebook]
        notebook = RubyTodo::Notebook.find_by(name: options[:notebook])
        unless notebook
          puts "Notebook '#{options[:notebook]}' not found."
          exit 1
        end
      end

      template = RubyTodo::Template.new(
        name: name,
        notebook: notebook,
        title_pattern: options[:title],
        description_pattern: options[:description],
        tags_pattern: options[:tags],
        priority: options[:priority],
        due_date_offset: options[:due]
      )

      if template.save
        puts "Template '#{name}' created successfully."
      else
        puts "Error creating template: #{template.errors.full_messages.join(", ")}"
        exit 1
      end
    end

    def template_list
      templates = RubyTodo::Template.all
      display_template_list(templates)
    end

    def template_show(name)
      template = RubyTodo::Template.find_by(name: name)

      unless template
        puts "Template '#{name}' not found."
        exit 1
      end

      display_template_details(template)
    end

    def template_delete(name)
      template = RubyTodo::Template.find_by(name: name)

      unless template
        puts "Template '#{name}' not found."
        exit 1
      end

      if template.destroy
        puts "Template '#{name}' deleted successfully."
      else
        puts "Error deleting template: #{template.errors.full_messages.join(", ")}"
        exit 1
      end
    end

    def template_use(name, notebook_name)
      template = RubyTodo::Template.find_by(name: name)

      unless template
        puts "Template '#{name}' not found."
        exit 1
      end

      notebook = RubyTodo::Notebook.find_by(name: notebook_name)

      unless notebook
        puts "Notebook '#{notebook_name}' not found."
        exit 1
      end

      replacements = {}
      if options[:replacements]
        options[:replacements].split(",").each do |r|
          key, value = r.split(":")
          replacements[key] = value if key && value
        end
      end

      task = template.create_task(notebook, replacements)

      if task.persisted?
        puts "Task created successfully with ID: #{task.id}"
      else
        puts "Error creating task: #{task.errors.full_messages.join(", ")}"
        exit 1
      end
    end
  end
end
