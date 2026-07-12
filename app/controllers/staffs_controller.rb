class StaffsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_staff, only: [:edit, :update, :destroy, :leave, :restore]
  before_action :set_occupations, only: [:new, :create, :edit, :update]

  def index
    @staffs = current_user.staffs
                          .includes(:occupation, :staff_workable_wdays, :staff_unworkable_wdays, :staff_day_time_options)
                          .order(:last_name_kana, :first_name_kana) # orderはカナ順の表示
  end

  def new
    @staff = current_user.staffs.build # 入力フォームの受け皿作成
  end

  def create
    @staff = current_user.staffs.build(staff_params)

    ActiveRecord::Base.transaction do
      normalize_weekly_workdays!(@staff)

      if @staff.save
        save_wdays!(@staff)
        redirect_to staffs_path, notice: "職員を登録しました。"
      else
        raise ActiveRecord::Rollback
      end
    end

    unless @staff.persisted?
      flash.now[:alert] = "登録に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @staff.assign_attributes(staff_params)

    success = false
    ActiveRecord::Base.transaction do
      normalize_weekly_workdays!(@staff)

      replace_day_time_option_references_before_delete!

      if @staff.save
        save_wdays!(@staff)
        success = true
      else
        raise ActiveRecord::Rollback
      end
    end

    if success
      redirect_to staffs_path, notice: "職員情報を更新しました"
    else
      flash.now[:alert] = "更新に失敗しました。入力内容を確認してください。"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @staff.destroy!
    redirect_to staffs_path, notice: "職員を削除しました"
  end

  def leave
    @staff.update!(active: false)
    redirect_to staffs_path, notice: "職員を休職にしました（休職設定中、シフト作成でこの職員は使われなくなります）"
  end

  def restore
    @staff.update!(active: true)

    redirect_to staffs_path, notice: "職員を復職しました"
  end

  private

  def set_staff
    @staff = current_user.staffs.includes(:staff_workable_wdays, :staff_unworkable_wdays).find(params[:id])
  end

  def set_occupations
    occupation_order_sql = Arel.sql(<<~SQL.squish)
      CASE occupations.name
      WHEN '管理者' THEN 0
      WHEN '介護士' THEN 1
      WHEN '看護師' THEN 2
      WHEN 'ケアマネ' THEN 3
      WHEN '管理栄養士' THEN 4
      WHEN '事務' THEN 5
      ELSE 999
      END
    SQL

    @occupations = Occupation.order(occupation_order_sql)
  end

  def staff_params
    params.require(:staff).permit(
      :occupation_id,
      :last_name, :first_name,
      :last_name_kana, :first_name_kana,
      :can_day, :can_early, :can_late, :can_night,
      :can_visit, :can_drive, :can_cook,
      :workday_constraint,
      :assignment_policy,
      :weekly_workdays,
      :count_fixed_in_weekday_requirements,
      :max_consecutive_work_days,
      staff_day_time_options_attributes: [
        :id,
        :time_text,
        :position,
        :active,
        :is_default,
        :_destroy,
        { apply_wdays: [] }
      ]
    )
  end

  def normalize_weekly_workdays!(staff)
  staff.weekly_workdays = nil unless staff.workday_constraint == "weekly"
  end

  def save_wdays!(staff)
    workable   = Array(params.dig(:staff, :workable_wdays)).map(&:to_i).uniq
    unworkable = Array(params.dig(:staff, :unworkable_wdays)).map(&:to_i).uniq

    case staff.workday_constraint
    when "fixed"
      staff.staff_unworkable_wdays.delete_all
      staff.staff_workable_wdays.delete_all
      workable.each { |wday| staff.staff_workable_wdays.create!(wday: wday) }

    when "weekly"
      staff.staff_workable_wdays.delete_all
      staff.staff_unworkable_wdays.delete_all
      unworkable.each { |wday| staff.staff_unworkable_wdays.create!(wday: wday) }

    else # "free"
      staff.staff_workable_wdays.delete_all
      staff.staff_unworkable_wdays.delete_all
      unworkable.each { |wday| staff.staff_unworkable_wdays.create!(wday: wday) }
    end
  end

  def replace_day_time_option_references_before_delete!
    # @staff.assign_attributes(staff_params) 後なので、ここにはネストの変更が反映されている前提

    # Railsが「削除予定」と判断した子からIDを拾う（params解析より堅い）
    destroy_ids =
      @staff.staff_day_time_options
            .select(&:marked_for_destruction?)
            .map(&:id)
            .compact

    return if destroy_ids.empty?

    # 念のため：対象スタッフのoptionだけ
    destroy_ids =
      StaffDayTimeOption.where(id: destroy_ids, staff_id: @staff.id).pluck(:id)
    return if destroy_ids.empty?

    scope = ShiftDayAssignment.unscoped.where(staff_day_time_option_id: destroy_ids)
    has_refs = scope.exists?
    return unless has_refs

    confirmed = ActiveModel::Type::Boolean.new.cast(params.dig(:staff, :confirm_day_time_option_delete))

    unless confirmed
      @staff.errors.add(:base, "日勤の表示を削除すると、保存されている日勤表示はすべて時間表記なしに変わります。確認してから保存してください。")
      raise ActiveRecord::Rollback
    end

    # 参照を全部NULLへ（FK回避）
    scope.update_all(staff_day_time_option_id: nil, updated_at: Time.current)

    # 保険：まだ参照が残るなら、ここで止めて原因を可視化する
    remain = ShiftDayAssignment.unscoped.where(staff_day_time_option_id: destroy_ids).count
    if remain > 0
      @staff.errors.add(:base, "削除前の置換に失敗しました（参照が#{remain}件残っています）。")
      raise ActiveRecord::Rollback
    end
  end
end
