# A merchant's correction to the product -> Wikipedia mapping, keyed by search term.
# Either points the term at a specific article, or marks it "don't track".
class MappingOverride < ApplicationRecord
  # "  Air Fryer " and "air fryer" are the same term.
  normalizes :term_key, with: ->(term) { term.to_s.strip.downcase }

  validates :term_key, presence: true, uniqueness: true
  validates :article, presence: true, unless: :ignored?

  def self.for_term(term)
    find_by(term_key: term.to_s.strip.downcase)
  end
end
