class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.references :user, null: false, foreign_key: true
      t.string :display_name, null: false
      t.string :sort_key, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :clients, [:user_id, :display_name], unique: true
    add_index :clients, [:user_id, :active, :sort_key]
  end
end
