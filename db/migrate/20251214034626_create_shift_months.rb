class CreateShiftMonths < ActiveRecord::Migration[8.1]
  def change
    create_table :shift_months do |t|
      t.references :organization, null: false, foreign_key: true
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :holiday_days # 未設定はNULL運用にするため、null: falseはつけない

      t.timestamps
    end

    add_index :shift_months, [ :organization_id, :year, :month ], unique: true
  end
end
