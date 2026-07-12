class CreateStaffWorkableWdays < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_workable_wdays do |t|
      t.references :staff, null: false, foreign_key: true
      t.integer :wday, null: false
      t.timestamps
    end
    add_index :staff_workable_wdays,
              [ :staff_id, :wday ],
              unique: true
  end
end
