# One row per search term. term_key is the lowercased term (productType or
# cleaned title), so one override covers every product sharing that term.
class CreateMappingOverrides < ActiveRecord::Migration[8.1]
  def change
    create_table :mapping_overrides do |t|
      t.string :term_key, null: false
      t.string :article                       # exact Wikipedia title; nil when ignored
      t.boolean :ignored, null: false, default: false

      t.timestamps
    end
    add_index :mapping_overrides, :term_key, unique: true
  end
end
