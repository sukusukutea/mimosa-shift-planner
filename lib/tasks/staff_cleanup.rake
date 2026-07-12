namespace :staff do
  desc "退職運用で残っている inactive staff を完全削除する"
  task purge_inactive: :environment do
    staffs = Staff.where(active: false)

    puts "対象件数: #{staffs.count}件"

    staffs.find_each do |staff|
      ActiveRecord::Base.transaction do
        ShiftDayAssignment.where(staff_id: staff.id)
                          .update_all(staff_day_time_option_id: nil, updated_at: Time.current)

        puts "削除開始: staff_id=#{staff.id} #{staff.last_name} #{staff.first_name}"
        staff.destroy!
        puts "削除完了: staff_id=#{staff.id}"
      end
    rescue => e
      puts "削除失敗: staff_id=#{staff.id} error=#{e.class} #{e.message}"
      raise
    end

    puts "完了"
  end
end
