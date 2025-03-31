# frozen_string_literal: true

module RubyTodo
  module NotebookCommands
    def notebook_create(name)
      notebook = Notebook.new(name: name)
      if notebook.save
        puts "Created notebook: #{name}".green
        notebook
      else
        puts "Error creating notebook: #{notebook.errors.full_messages.join(", ")}".red
        nil
      end
    end

    def notebook_list
      notebooks = Notebook.all
      return say "No notebooks found".yellow if notebooks.empty?

      table = TTY::Table.new(
        header: ["ID", "Name", "Tasks", "Created At", "Default"],
        rows: notebooks.map do |notebook|
          [
            notebook.id,
            notebook.name,
            notebook.tasks.count,
            notebook.created_at,
            notebook.is_default? ? "✓" : ""
          ]
        end
      )
      puts table.render(:ascii)
    end

    def notebook_set_default(name)
      notebook = Notebook.find_by(name: name)
      if notebook
        notebook.make_default!
        say "Successfully set '#{name}' as the default notebook".green
      else
        say "Notebook '#{name}' not found".red
      end
    end
  end
end
