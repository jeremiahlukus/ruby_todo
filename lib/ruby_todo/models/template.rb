# frozen_string_literal: true

require "active_record"

module RubyTodo
  class Template < ActiveRecord::Base
    belongs_to :notebook, optional: true

    validates :name, presence: true, uniqueness: true
    validates :title_pattern, presence: true

    # Create a task from this template
    def create_task(notebook, replacements = {})
      # Process the title with replacements
      title = process_pattern(title_pattern, replacements)

      # Process the description with replacements if it exists
      description = description_pattern ? process_pattern(description_pattern, replacements) : nil

      # Process tags if they exist
      tags = tags_pattern ? process_pattern(tags_pattern, replacements) : nil

      # Calculate due date
      due_date = calculate_due_date(due_date_offset) if due_date_offset

      # Create the task
      Task.create(
        notebook: notebook,
        title: title,
        description: description,
        status: "todo",
        priority: priority,
        tags: tags,
        due_date: due_date
      )
    end

    private

    def process_pattern(pattern, replacements)
      result = pattern.dup

      # Replace placeholders with values
      replacements.each do |key, value|
        placeholder = "{#{key}}"
        result.gsub!(placeholder, value.to_s)
      end

      # Replace date placeholders
      today = Date.today
      result.gsub!("{today}", today.strftime("%Y-%m-%d"))
      result.gsub!("{tomorrow}", (today + 1).strftime("%Y-%m-%d"))
      result.gsub!("{yesterday}", (today - 1).strftime("%Y-%m-%d"))
      result.gsub!("{weekday}", today.strftime("%A"))
      result.gsub!("{month}", today.strftime("%B"))
      result.gsub!("{year}", today.strftime("%Y"))

      result
    end

    def calculate_due_date(offset_string)
      return nil unless offset_string

      # Parse the offset string (e.g., "2d", "1w", "3h")
      if offset_string =~ /^(\d+)([dwmhy])$/
        amount = ::Regexp.last_match(1).to_i
        unit = ::Regexp.last_match(2)

        case unit
        when "d" # days
          Time.now + amount * 24 * 60 * 60
        when "w" # weeks
          Time.now + amount * 7 * 24 * 60 * 60
        when "m" # months (approximate)
          Time.now + amount * 30 * 24 * 60 * 60
        when "h" # hours
          Time.now + amount * 60 * 60
        when "y" # years (approximate)
          Time.now + amount * 365 * 24 * 60 * 60
        end
      end
    end
  end
end
