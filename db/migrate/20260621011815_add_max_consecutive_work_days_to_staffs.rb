class AddMaxConsecutiveWorkDaysToStaffs < ActiveRecord::Migration[8.1]
  def change
    add_column :staffs, :max_consecutive_work_days, :integer, null: false, default: 5
  end
end
