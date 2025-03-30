# frozen_string_literal: true

require "active_record"

module RubyTodo
  class Task < ActiveRecord::Base
    belongs_to :notebook

    validates :title, presence: true
    validates :status, presence: true, inclusion: { in: %w[todo in_progress done archived] }
    validates :due_date, presence: false
    validates :priority, inclusion: { in: %w[high medium low], allow_nil: true }
    validate :due_date_cannot_be_in_past, if: :due_date?
    validate :tags_format, if: :tags?

    before_save :format_tags

    scope :todo, -> { where(status: "todo") }
    scope :in_progress, -> { where(status: "in_progress") }
    scope :done, -> { where(status: "done") }
    scope :archived, -> { where(status: "archived") }
    scope :high_priority, -> { where(priority: "high") }
    scope :medium_priority, -> { where(priority: "medium") }
    scope :low_priority, -> { where(priority: "low") }

    def overdue?
      return false unless due_date?

      due_date < Time.current && status != "done" && status != "archived"
    end

    def due_soon?
      return false unless due_date?

      due_date < Time.current + 24 * 60 * 60 && status != "done" && status != "archived"
    end

    def tag_list
      return [] unless tags

      tags.split(",").map(&:strip)
    end

    def has_tag?(tag)
      return false unless tags

      tag_list.include?(tag.strip)
    end

    private

    def due_date_cannot_be_in_past
      return unless due_date.present? && due_date < Time.current && new_record?

      errors.add(:due_date, "can't be in the past")
    end

    def tags_format
      return unless tags.present?

      unless tags.match?(/^[a-zA-Z0-9,\s\-_]+$/)
        errors.add(:tags, "can only contain letters, numbers, commas, spaces, hyphens and underscores")
      end
    end

    def format_tags
      return unless tags.present?

      self.tags = tags.split(",").map(&:strip).join(",")
    end
  end
end
