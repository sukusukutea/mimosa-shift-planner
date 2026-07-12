class CreateStaffDayTimeOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_day_time_options do |t|
      t.references :staff, null: false, foreign_key: true

      t.string  :time_text, null: false          # 例: "9-17"
      t.boolean :is_default, null: false, default: false

      t.integer :position,   null: false, default: 1
      t.boolean :active,     null: false, default: true

      t.timestamps
    end

    add_index :staff_day_time_options, [ :staff_id, :active, :position ],
              name: "idx_sdto_staff_active_position"

    # デフォルトは職員ごとに1つだけ（DBで担保）
    add_index :staff_day_time_options, :staff_id,
              unique: true,
              where: "is_default = true",
              name: "idx_sdto_unique_default_per_staff"
  end
end
