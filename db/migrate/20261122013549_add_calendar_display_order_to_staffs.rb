class AddCalendarDisplayOrderToStaffs < ActiveRecord::Migration[8.1]
  def change
    add_column :staffs, :calendar_display_order, :integer
  end
end
