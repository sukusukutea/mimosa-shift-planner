class CreateShiftDayStyles < ActiveRecord::Migration[8.1]
  def change
    create_table :shift_day_styles do |t|
      t.references :shift_day_setting, null: false, foreign_key: true
      t.integer :shift_kind, null: false
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :shift_day_styles, [ :shift_day_setting_id, :shift_kind ],  unique: true
  end
end
