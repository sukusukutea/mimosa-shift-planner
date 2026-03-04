class ShiftMonthsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_organization!
  before_action :set_shift_month, only: [:settings, :update_settings, :update_daily,
                                        :generate_draft, :preview, :edit_draft, :confirm_draft, :show, :add_staff_holiday,
                                        :remove_staff_holiday, :update_weekday_requirements, :update_designation,
                                        :remove_designation, :update_draft_assignment, :start_edit_from_confirmed,
                                        :export_excel, :sync_weekday_requirements]
  before_action :build_calendar_vars, only: [:settings, :preview, :edit_draft, :show]

  def new
    @shift_month = current_user.shift_months.new
    @recent_shift_months = current_user.shift_months.order(created_at: :desc).limit(6)
    @shift_months_count  = current_user.shift_months.count
  end

  def show
    scope = @shift_month.shift_day_assignments.confirmed.where(date: @month_begin..@month_end)
    @saved = build_assignments_hash(scope.select(:id, :date, :shift_kind, :staff_id, :slot, :staff_day_time_option_id))

    prepare_calendar_page(assignments_hash: @saved)

    @holiday_requests_by_date =
      @shift_month.staff_holiday_requests
                  .includes(:staff)
                  .where(date: @calendar_begin..@calendar_end)
                  .group_by(&:date)
  end

  def create
    @shift_month = current_user.shift_months.new(shift_month_params)
    @shift_month.organization = current_user.organization
    @recent_shift_months = current_user.shift_months.order(year: :desc, month: :desc).limit(3)

    year_string = shift_month_params[:year]
    month_string = shift_month_params[:month]
  
    if year_string.blank?
      @shift_month.errors.add(:year, "を選択してください")
    end

    if month_string.blank?
      @shift_month.errors.add(:month, "を選択してください")
    end

    if @shift_month.errors.any?
      render :new, status: :unprocessable_entity
      return
    end

    year = year_string.to_i
    month = month_string.to_i

    unless (1..12).include?(month)
      @shift_month.errors.add(:month, "は1~12で選択してください。")
      render :new, status: :unprocessable_entity
      return
    end

    existing = current_user.shift_months.find_by(year: year, month: month)
    if existing
      if weekday_requirements_changed?(shift_month: existing)
        redirect_to settings_shift_month_path(existing, stale_weekday_req: "1")
      else
        redirect_to settings_shift_month_path(existing), notice: "既に作成済みのため、その月を開きました。"
      end
      return
    end

    @shift_month.year = year
    @shift_month.month = month

    if @shift_month.save
      @shift_month.copy_weekday_requirements_from_base!(user: current_user)
      @shift_month.copy_skill_requirements_from_base!(user: current_user)

      prune_old_shift_months!(user: current_user, keep: 6)

      redirect_to settings_shift_month_path(@shift_month)
    else
      flash.now[:alert] = "作成に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    shift_month = current_user.shift_months.find(params[:id])
    shift_month.destroy!
    redirect_to new_shift_month_path, notice: "削除しました"
  end

  def settings
    preload_staffs_for
    prepare_daily_tab_vars
    prepare_holiday_tab_vars
    @weekday_requirements = build_weekday_requirements_hash
    @day_req = @shift_month.required_counts_for(@selected_date, shift_kind: :day)
    @day_skill_req = @shift_month.required_skill_counts_for(@selected_date)

    @selected_designation_staff =
      if params[:designation_staff_id].present?
        current_user.staffs.find_by(id: params[:designation_staff_id])
      end

    @designations_for_staff =
      if @selected_designation_staff
        @shift_month.shift_day_designations
                    .where(staff: @selected_designation_staff)
                    .order(:date)
      else
        ShiftDayDesignation.none
      end
  end

  def update_settings
    if @shift_month.update(holiday_days_params)
      redirect_to settings_shift_month_path(@shift_month, tab: "holiday")
    else
      redirect_to settings_shift_month_path(@shift_month, tab: "holiday"), alert: "更新に失敗しました。"
    end
  end

  def update_daily
    date = Date.iso8601(params.require(:date))          # フォームからくる[date]は文字列のため、Date.iso8601で厳密にDateに変換。不正ならArgumentErrorになる。
    enabled_hash = params.dig(:day_setting, :enabled) || {}
    roles  = params.dig(:day_requirements, :roles)  || {}
    skills = params.dig(:day_requirements, :skills) || {}

    ActiveRecord::Base.transaction do
      setting = @shift_month.shift_day_settings.find_or_create_by!(date: date)

      if ActiveModel::Type::Boolean.new.cast(enabled_hash["late"])
        late_slots = params.dig(:day_setting, :late_slots).to_i
        late_slots = 1 if late_slots <= 0
        late_slots = 2 if late_slots >= 2
        setting.update!(late_slots: late_slots)
      else
        setting.update!(late_slots: 1)
      end

      ShiftMonth::SHIFT_KINDS.each do |kind|
        enabled = ActiveModel::Type::Boolean.new.cast(enabled_hash[kind.to_s])
        style = setting.shift_day_styles.find_or_initialize_by(shift_kind: kind)
        style.enabled = enabled
        style.save!
      end

      day_enabled = ActiveModel::Type::Boolean.new.cast(enabled_hash["day"])

      if day_enabled
        %w[nurse care].each do |role|
          num = roles[role].to_i
          rec = @shift_month.shift_day_requirements.find_or_initialize_by(
            date: date,
            shift_kind: :day,
            role: role
          )
          rec.required_number = num
          rec.save!
        end

        %w[drive cook].each do |skill|
          num = skills[skill].to_i
          rec = @shift_month.shift_day_skill_requirements.find_or_initialize_by(
            date: date,
            shift_kind: :day,
            skill: skill
          )
          rec.required_number = num
          rec.save!
        end
      else
        @shift_month.shift_day_requirements.where(date: date, shift_kind: :day).delete_all
        @shift_month.shift_day_skill_requirements.where(date: date, shift_kind: :day).delete_all
      end
    end

    # requirements_index を使ってるなら念の為クリア（必要なら）
    @shift_month.clear_day_requirements_cache! if @shift_month.respond_to?(:clear_day_requirements_cache!)
    @shift_month.clear_day_skill_requirements_cache! if @shift_month.respond_to?(:clear_day_skill_requirements_cache!)

    redirect_to settings_shift_month_path(@shift_month, tab: "daily", date: date.iso8601), notice: "保存しました"
  rescue ArgumentError
    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), alert: "日付が不正です"
  rescue ActionController::ParameterMissing
    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), alert: "入力が見つかりません"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_shift_month_path(@shift_month, tab: "daily", date: params[:date]), alert: "保存に失敗しました：#{e.record.errors.full_messages.join(", ")}"
  end

  def update_designation
    force = params[:force].to_s == "1"
    sid   = params.dig(:designation, :staff_id).to_i
    kind  = params.dig(:designation, :shift_kind).to_s
    date  = Date.iso8601(params[:date])

    if sid == 0 || kind.blank?
      redirect_to settings_shift_month_path(@shift_month, tab: "daily", date: date.iso8601),
                  alert: "職員と勤務形態を選択してください"
      return
    end

    holiday = @shift_month.staff_holiday_requests.find_by(date: date, staff_id: sid)
    if !force && holiday.present?
      flash[:conflict] = {
        kind: "designation_over_holiday",
        staff_id: sid,
        date: date.iso8601,
        shift_kind: kind
      }
      redirect_to settings_shift_month_path(
        @shift_month,
        tab: "daily",
        date: date.iso8601,
        designation_staff_id: sid
      )
      return
    end

    holiday&.destroy

    # --- NG曜日チェック（candidateのみ / 日勤系だけ）---
    if !force && %w[day early late].include?(kind)
      staff = current_user.staffs.find_by(id: sid)

      if staff&.assignment_policy.to_s == "candidate"
        wday = ShiftMonth.ui_wday(date)

        if staff&.ng_wday?(date)
          flash[:conflict] = {
            kind: "designation_over_ng_wday",
            staff_id: sid,
            date: date.iso8601,
            shift_kind: kind
          }
          redirect_to settings_shift_month_path(
            @shift_month,
            tab: "daily",
            date: date.iso8601,
            designation_staff_id: sid
          )
          return
        end
      end
    end

    ShiftDayDesignation.transaction do
      if kind == "day"
        # 日勤は複数人OK：同一日・同一職員の既存designationを消してから追加
        @shift_month.shift_day_designations.where(date: date, staff_id: sid).delete_all
        record = @shift_month.shift_day_designations.find_or_initialize_by(date: date, staff_id: sid)
        record.shift_kind = "day"
        record.save!
      else
        if kind == "late"
          limit = @shift_month.late_slots_for(date)

          @shift_month.shift_day_designations.where(date: date, staff_id: sid).delete_all

          existing = @shift_month.shift_day_designations.where(date: date, shift_kind: "late")
          if existing.count >= limit
            # 枠が埋まっているなら先頭(古い方)を上書き
            existing.order(:id).first.update!(staff_id: sid)
          else
            @shift_month.shift_day_designations.create!(date: date, shift_kind: "late", staff_id: sid)
          end
        else
          # 早/夜勤は1人だけ：同一日・同一kindを上書き
          record = @shift_month.shift_day_designations.find_or_initialize_by(date: date, shift_kind: kind)
          record.staff_id = sid
          record.save!
        end
      end 
    end

    redirect_to settings_shift_month_path(@shift_month, tab: "daily", date: date.iso8601)
  rescue ArgumentError
    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), alert: "日付が不正です"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_shift_month_path(@shift_month, tab: "daily" , date: params[:date]),
                alert: "保存に失敗しました: #{e.record.errors.full_messages.join(", ")}"
  end

  def remove_designation
    designation = @shift_month.shift_day_designations.find(params[:designation_id])
    staff_id = designation.staff_id
    designation.destroy!

    redirect_to settings_shift_month_path(@shift_month, tab: "daily", date: params[:date], designation_staff_id: staff_id)
  end

  def add_staff_holiday
    force = params[:force].to_s == "1"
    sid   = params[:staff_id].to_i
    date  = Date.iso8601(params[:date])

    conflicts = @shift_month.shift_day_designations.where(date: date, staff_id: sid)
    if !force && conflicts.exists?
      flash[:conflict] = {
        kind: "holiday_over_designation",
        staff_id: sid,
        date: date.iso8601
      }
      redirect_to settings_shift_month_path(@shift_month, tab: "holiday", staff_id: sid)
      return
    end

    conflicts.delete_all

    staff = current_user.staffs.find(sid)
    @shift_month.staff_holiday_requests.find_or_create_by!(staff: staff, date: date)

    redirect_to settings_shift_month_path(@shift_month, tab: "holiday", staff_id: staff.id), notice: "休日希望を追加しました"
  rescue ArgumentError
    redirect_to settings_shift_month_path(@shift_month, tab: "holiday", staff_id: params[:staff_id]), alert: "日付の形式が正しくありません"
  end

  def remove_staff_holiday
    request = @shift_month.staff_holiday_requests.find(params[:request_id])
    staff_id = request.staff_id
    request.destroy!

    redirect_to settings_shift_month_path(@shift_month, tab: "holiday", staff_id: staff_id), notice: "休日希望を削除しました"
  end

  def update_weekday_requirements
    data = params.require(:weekday_requirements)

    ShiftMonthRequirement.transaction do
      data.each do |dow_str, roles_hash| # dow:day_of_weekの略, str:string
        dow = dow_str.to_i

        %w[nurse care].each do |role|
          num = roles_hash[role].to_i

          rec = @shift_month.shift_month_requirements.find_or_initialize_by(
            shift_kind: :day,
            day_of_week: dow,
            role: role
          )
          rec.required_number = num
          rec.save!
        end

        %w[early late night].each do |kind|
          num = roles_hash[kind].to_i

          rec = @shift_month.shift_month_requirements.find_or_initialize_by(
            shift_kind: kind,
            day_of_week: dow,
            role: :any
          )
          rec.required_number = num
          rec.save!
        end
      end
    end

    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), notice: "曜日別の必要人数を保存しました"
  rescue ActionController::ParameterMissing
    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), alert: "入力が見つかりません"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_shift_month_path(@shift_month, tab: "daily"), alert: "保存に失敗しました：#{e.record.errors.full_messages.join(", ")}"
  end

  def generate_draft
    token = SecureRandom.hex(8)
    @shift_month.shift_day_assignments.draft.delete_all

    draft_hash = ShiftDrafts::RandomGenerator.new(shift_month: @shift_month).call

    ShiftDayAssignment.transaction do
      @shift_month.shift_day_assignments.draft.delete_all # (多重タブの競合対策としてもう一度削除)

      draft_hash.each do |date_str, kinds_hash|
        date = Date.iso8601(date_str)

        kinds_hash.each do |kind_sym_or_str, rows|
          kind = kind_sym_or_str.to_sym
          next unless ShiftMonth::SHIFT_KINDS.include?(kind)
          
          Array(rows).each do |row|
            staff_id = row[:staff_id] || row["staff_id"]
            slot = row[:slot] || row["slot"]
            next if staff_id.blank?

            @shift_month.shift_day_assignments.create!(
              date: date,
              shift_kind: kind,
              staff_id: staff_id,
              slot: slot.to_i,
              source: :draft,
              draft_token: token
            )
          end
        end
      end
    end

    session[draft_token_session_key] = token
    redirect_to preview_shift_month_path(@shift_month), notice: "シフト案を作成しました。"
  rescue ArgumentError
    redirect_to settings_shift_month_path(@shift_month), alert: "日付形式が不正です。"
  end

  def preview
    scope, _token, @draft = load_draft_for_calendar

    unless scope&.exists?
      redirect_to settings_shift_month_path(@shift_month), alert: "シフト案がありません。先に作成してください"
      return
    end

    prepare_calendar_page(assignments_hash: @draft)
  end

  def edit_draft
    scope, _token, @draft = load_draft_for_calendar

    unless scope&.exists?
      redirect_to settings_shift_month_path(@shift_month), alert: "シフト案がありません。先に作成してください"
      return
    end

    prepare_calendar_page(assignments_hash: @draft)
  end

  def update_draft_assignment
    scope, token, _draft = load_draft_for_calendar(require_token: true)

    if token.blank? || scope.nil?
      render json: { ok: false, error: "draft token missing" }, status: :unprocessable_entity
      return
    end

    date  = Date.iso8601(params.require(:date))
    kind_str = params.require(:kind).to_s
    staff_id = params.require(:staff_id).to_i
    ui_wday  = ShiftMonth.ui_wday(date)

    staff_day_time_option_id =
      if params.key?(:staff_day_time_option_id) && params[:staff_day_time_option_id].present?
        params[:staff_day_time_option_id].to_i
      else
        nil
      end

    allowed = %w[day early late night off]
    unless allowed.include?(kind_str)
      render json: { ok: false, error: "kind is invalid" }, status: :unprocessable_entity
      return
    end

    if kind_str != "off" && staff_id <= 0
      render json: { ok: false, error: "staff_id is invalid" }, status: :unprocessable_entity
      return
    end

    if kind_str == "day" && staff_day_time_option_id.present?
      ok = StaffDayTimeOption.where(id: staff_day_time_option_id, staff_id: staff_id, active: true).exists?
      unless ok
        render json: { ok: false, error: "staff_day_time_option_id is invalid" }, status: :unprocessable_entity
        return
      end
    end

    editable_kinds = %i[day early late night]

    month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
    month_end   = month_begin.end_of_month
    calendar_begin = month_begin.beginning_of_week(:monday)
    calendar_end   = month_end.end_of_week(:monday)

    third_day = nil
    affected_days = []

    ShiftDayAssignment.transaction do
      if kind_str == "night"
        # 夜勤は「その日1枠」扱い：誰であっても一旦消してから入れ直す（A→B置換対応）
        scope.where(date: date, shift_kind: :night).delete_all
        scope.where(date: date, staff_id: staff_id, shift_kind: %i[day early late]).delete_all

        next_day = date + 1
        scope.where(date: next_day, staff_id: staff_id, shift_kind: %i[day early late]).delete_all
      elsif kind_str == "off"
        # 「夜勤なし」はstaff_idは0で来るため、当日nightに入っている職員をDBから拾う
        night_row = scope.find_by(date: date, shift_kind: :night)
        night_staff_id = night_row&.staff_id

        # nightを消す
        scope.where(date: date, shift_kind: :night).delete_all

        if night_staff_id.present?
          # 当日・翌日・3日目（3日目は月内だけ）を「日勤」に入れ直す
          d1 = date
          d2 = date + 1
          d3 = date + 2
          days = [d1, d2]
          days << d3 if d3 >= month_begin && d3 <= month_end

          # affected_days を覚えておく（後でHTML差し替え対象に使う）
          affected_days.concat(days)

          days.each do |d|
            # その職員のその日の勤務を一旦全部消す（day/early/late/night）
            scope.where(date: d, staff_id: night_staff_id, shift_kind: %i[day early late night]).delete_all

            d_wday = ShiftMonth.ui_wday(d)

            # 日勤(day)を入れる
            max_slot = scope.where(date: d, shift_kind: :day).maximum(:slot)
            slot = max_slot.to_i + 1

            day_opt_id =
              StaffDayTimeOption.where(staff_id: night_staff_id, active: true)
                                .where("apply_wdays @> ARRAY[?]::int[]", d_wday)
                                .order(:position, :id)
                                .pick(:id) ||
              StaffDayTimeOption.where(staff_id: night_staff_id, active: true, is_default: true).pick(:id) ||
              StaffDayTimeOption.where(staff_id: night_staff_id, active: true).order(:position, :id).pick(:id)

            @shift_month.shift_day_assignments.create!(
              date: d,
              shift_kind: :day,
              staff_id: night_staff_id,
              slot: slot,
              source: :draft,
              draft_token: token,
              staff_day_time_option_id: day_opt_id
            )
          end
        end
      else
        # 日勤系は今のまま
        scope.where(date: date, staff_id: staff_id, shift_kind: editable_kinds).delete_all
      end

      if kind_str != "off"
        kind = kind_str.to_sym
        max_slot = scope.where(date: date, shift_kind: kind).maximum(:slot)
        slot = max_slot.to_i + 1

        opt_id =
          if kind == :day
            if staff_day_time_option_id.present?
              staff_day_time_option_id
            else
              StaffDayTimeOption.where(staff_id: staff_id, active: true)
                                .where("apply_wdays @> ARRAY[?]::int[]", ui_wday)
                                .order(:position, :id)
                                .pick(:id) ||
                StaffDayTimeOption.where(staff_id: staff_id, active: true, is_default: true).pick(:id) ||
                StaffDayTimeOption.where(staff_id: staff_id, active: true).order(:position, :id).pick(:id)
            end
          else
            nil
          end

        @shift_month.shift_day_assignments.create!(
          date: date,
          shift_kind: kind,
          staff_id: staff_id,
          slot: slot,
          source: :draft,
          draft_token: token,
          staff_day_time_option_id: opt_id
        )
      end

      # 夜勤を入れた時だけ：3日目を強制休みにする（その職員の勤務を削除）その職員の3日目勤務を全削除
      if kind_str == "night"
        third_day = date + 2
        if third_day >= month_begin && third_day <= month_end
          scope.where(
            date: third_day,
            staff_id: staff_id,
            shift_kind: %i[day early late night]
          ).delete_all
        else
          third_day = nil
        end
      end
    end

    # 最新状態に再構築して、renderする
    @draft = build_draft_hash(scope)
    preload_staffs_for

    dates = (calendar_begin..calendar_end).to_a

    @unassigned_display_staffs_by_date =
      ShiftDrafts::UnassignedDisplayStaffsBuilder.new(
        dates: dates,
        staff_by_id: @staff_by_id,
        assignments_hash: @draft
      ).call

    @stats_rows = ShiftDrafts::StatsBuilder.new(
      shift_month: @shift_month,
      staff_by_id: @staff_by_id,
      draft: @draft
    ).call

    stats_html = render_to_string(
      partial: "shift_months/draft_sidebar",
      formats: [:html],
      locals: { stats_rows: @stats_rows, shift_month: @shift_month }
    )

    enabled_maps = @shift_month.enabled_map_for_range(dates)
    required_by_date = {}
    dates.each do |d|
      required_by_date[d] = @shift_month.required_counts_for(d, shift_kind: :day)
    end

    alerts_by_date = ShiftDrafts::AlertsBuilder.new(
      dates: dates,
      draft: @draft,
      staff_by_id: @staff_by_id,
      required_by_date: required_by_date,
      enabled_by_date: {
        day: enabled_maps[:day],
        early: enabled_maps[:early],
        late: enabled_maps[:late],
        night: enabled_maps[:night]
      },
      shift_month: @shift_month
    ).call

    holiday_requests_by_date =
      @shift_month.staff_holiday_requests
                  .includes(:staff)
                  .where(date: calendar_begin..calendar_end)
                  .group_by(&:date)

    designations = @shift_month.shift_day_designations.where(date: month_begin..month_end)
    designations_by_date = Hash.new { |h, k| h[k] = {} }
    designations.each do |d|
      kind = d.shift_kind.to_s
      if kind == "day" || kind == "late"
        (designations_by_date[d.date][kind] ||= []) << d.staff_id
      else
        designations_by_date[d.date][kind] = d.staff_id
      end
    end

    alerts_html_by_date = {}
    (month_begin..month_end).each do |d|
      base_msgs = Array(alerts_by_date[d])
      msgs = helpers.augment_alert_messages_for_night_conflicts(
        base_msgs: base_msgs,
        draft: @draft,
        date: d,
        holiday_requests_by_date: holiday_requests_by_date,
        designations_by_date: designations_by_date
      )

      alerts_html_by_date[d.iso8601] = render_to_string(
        partial: "shift_months/calendar_cells/alert_body",
        formats: [:html],
        locals: { msgs: msgs }
      )
    end

    # night-slot(当日＋翌日)
    night_slots_html_by_dom_id = {}
    target_row_keys = %i[nurse care]
    target_dates = [date, date + 1]

    target_row_keys.each do |rk|
      target_dates.each do |d|
        dom_id = "night-slot-#{rk}-#{d.iso8601}"

        night_slots_html_by_dom_id[dom_id] = render_to_string(
          partial: "shift_months/calendar_cells/night_slot",
          formats: [:html],
          locals: {
            date: d,
            in_month: (d >= month_begin && d <= month_end),
            row_key: rk,
            shift_month: @shift_month,
            draft: @draft,
            staff_by_id: @staff_by_id
          }
        )
      end
    end

    # off(夜勤なし) のときは affected_days（=当日/翌日/3日目）を優先して差し替える
    target_days =
      if affected_days.present?
        affected_days
      else
        days = [date, date + 1]
        days << third_day if third_day
        days
      end

    target_days = target_days.compact.uniq

    # day-slot(当日＋翌日＋3日目)を差し替え
    day_slots_html_by_dom_id = {}

    target_row_keys.each do |rk|
      target_days.each do |d|
        dom_id = "day-slot-#{rk}-#{d.iso8601}"

        day_slots_html_by_dom_id[dom_id] = render_to_string(
          partial: "shift_months/calendar_cells/day_slot_body",
          formats: [:html],
          locals: {
            date: d,
            in_month: (d >= month_begin && d <= month_end),
            row_key: rk,
            shift_month: @shift_month,
            day_enabled_by_date: @day_enabled_by_date,
            early_enabled_by_date: @early_enabled_by_date,
            late_enabled_by_date: @late_enabled_by_date,
            required_by_date: @required_by_date,
            required_skill_by_date: @required_skill_by_date,
            alerts_by_date: @alerts_by_date,
            draft: @draft,
            staff_by_id: @staff_by_id,
            unassigned_display_staffs_by_date: @unassigned_display_staffs_by_date,
            holiday_requests_by_date: holiday_requests_by_date,
            designations_by_date: designations_by_date
          }
        )
      end
    end

    render json: {
      ok: true,
      stats_html: stats_html,
      alerts_html_by_date: alerts_html_by_date,
      night_slots_html_by_dom_id: night_slots_html_by_dom_id,
      day_slots_html_by_dom_id: day_slots_html_by_dom_id
    }
  rescue ActionController::ParameterMissing
    render json: { ok: false, error: "param missing" }, status: :unprocessable_entity
  rescue ArgumentError
    render json: { ok: false, error: "date is invalid" }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { ok: false, error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end

  def confirm_draft
    scope, _token, _draft = load_draft_for_calendar

    unless scope&.exists?
      redirect_to preview_shift_month_path(@shift_month), alert: "シフト案がありません。先に作成してください"
      return
    end

    ShiftDayAssignment.transaction do
      @shift_month.shift_day_assignments.confirmed.delete_all

      scope.update_all(
        source: ShiftDayAssignment.sources[:confirmed],
        draft_token: nil,
        updated_at: Time.current
      )
    end

    session.delete(draft_token_session_key)
    redirect_to new_shift_month_path(@shift_month), notice: "シフトを保存しました"
  rescue ArgumentError
    redirect_to preview_shift_month_path(@shift_month), alert: "日付形式が不正です"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to preview_shift_month_path(@shift_month), alert: "保存に失敗しました： #{e.record.errors.full_messages.join(", ")}"
  end

  def start_edit_from_confirmed
    token = SecureRandom.hex(8)

    month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
    month_end   = month_begin.end_of_month

    confirmed_scope =
      @shift_month.shift_day_assignments.confirmed.where(date: month_begin..month_end)

    ShiftDayAssignment.transaction do
      # 既存draftを消す（多重編集の衝突を避ける）
      @shift_month.shift_day_assignments.draft.delete_all

      confirmed_scope.select(:id, :date, :shift_kind, :staff_id, :slot, :staff_day_time_option_id).find_each do |a|
        @shift_month.shift_day_assignments.create!(
          date: a.date,
          shift_kind: a.shift_kind,
          staff_id: a.staff_id,
          slot: a.slot,
          source: :draft,
          draft_token: token,
          staff_day_time_option_id: a.staff_day_time_option_id
        )
      end
    end

    session[draft_token_session_key] = token
    redirect_to edit_draft_shift_month_path(@shift_month), notice: "確定シフトを下書きに複製して、手修正を開始しました。"
  end

  def export_excel
    exporter = ShiftExports::MimosaTemplateExporter.new(shift_month: @shift_month)
    xlsx_bin = exporter.call

    filename = "shift_#{@shift_month.year}_#{format('%02d', @shift_month.month)}.xlsx"

    send_data(
      xlsx_bin,
      filename: filename,
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      disposition: "attachment"
    )
  end

  def sync_weekday_requirements
  @shift_month.copy_weekday_requirements_from_base!(user: current_user)

  redirect_to settings_shift_month_path(@shift_month),
              notice: "曜日別人員配置（元設定）をこの月に同期しました。"
  end

  private

  def require_organization!
    return if current_user.organization.present?

    redirect_to dashboard_path, alert: "事業所情報が見つかりません。登録情報を確認してください。"
  end

  def set_shift_month
    @shift_month = current_user.shift_months.find(params[:id]) # 他事業所の月を参照できないようにする
  end

  def shift_month_params
    params.require(:shift_month).permit(:year, :month)
  end

  def holiday_days_params
    params.require(:shift_month).permit(:holiday_days)
  end

  def day_setting_params
    params.require(:day_setting).permit(:date, enabled: ShiftMonth::SHIFT_KINDS) # enabled: ShiftMonth::SHIFT_KINDSでday/early/late/night以外を弾く
  end

  def parse_selected_date(str)
    return nil if str.blank?
    Date.iso8601(str)
  rescue ArgumentError
    nil
  end

  def draft_token_session_key
    "shift_draft_token_#{@shift_month.id}"
  end

  # draftのscopeとtokenをまとめて返す
  # require_token: true のとき token がなければ [nil, nil] を返す
  def draft_scope_and_token(require_token: false)
    token = session[draft_token_session_key]

    if require_token && token.blank?
      return [nil, nil]
    end

    month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
    month_end   = month_begin.end_of_month

    scope = @shift_month.shift_day_assignments.draft.where(date: month_begin..month_end)
    scope = scope.where(draft_token: token) if token.present?

    [scope, token]
  end

  # draft用：selectを揃えてhash化（preview/edit/update/confirmで共通）
  def build_draft_hash(scope)
    build_assignments_hash(scope.select(:id, :date, :shift_kind, :staff_id, :slot, :staff_day_time_option_id))
  end

  def load_draft_for_calendar(require_token: false)
    scope, token = draft_scope_and_token(require_token: require_token)
    return [nil, nil, nil] if scope.nil?

    draft_hash = build_draft_hash(scope)
    [scope, token, draft_hash]
  end

  # カレンダー用の変数(vars:変数達の略)
  def build_calendar_vars
    @month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
    @month_end = @month_begin.end_of_month
    @calendar_begin = @month_begin.beginning_of_week(:monday)
    @calendar_end = @month_end.end_of_week(:monday)
    @dates = (@calendar_begin..@calendar_end).to_a
    @weeks = @dates.each_slice(7).to_a # １週間毎に区切る

    @occupation_order = [
      { key: :nurse, label: "看護", row_class: "occ-row-nurse" },
      { key: :care_mgr, label: "ケアマネ", row_class: "occ-row-small" },
      { key: :care, label: "介護", row_class: "occ-row-care" },
      { key: :cook, label: "調理", row_class: "occ-row-small" },
      { key: :clerk, label: "事務", row_class: "occ-row-small" },
      { key: :req, label: "人員設定", row_class: "occ-row-req" },
    ]

    enabled_maps = @shift_month.enabled_map_for_range(@dates)
    @day_enabled_by_date   = enabled_maps[:day]
    @early_enabled_by_date = enabled_maps[:early]
    @late_enabled_by_date  = enabled_maps[:late]
    @night_enabled_by_date = enabled_maps[:night]

    @day_effective_by_date = {}
    @required_by_date = {}

    @dates.each do |date|
      day_on = @day_enabled_by_date[date]

      req = @shift_month.required_counts_for(date, shift_kind: :day)
      @required_by_date[date] = req

      has_staff = req[:nurse].to_i > 0 || req[:care].to_i > 0
      @day_effective_by_date[date] = day_on && has_staff
    end

    load_holidays

    rows = @shift_month.shift_day_designations
                      .where(date: @month_begin..@month_end)
                      .includes(:staff)

    @designations_by_date = Hash.new { |h, k| h[k] = {} }
    rows.each do |d|
      kind = d.shift_kind.to_s
      if kind == "day"
        (@designations_by_date[d.date]["day"] ||= []) << d.staff_id
      elsif kind == "late"
        (@designations_by_date[d.date]["late"] ||= []) << d.staff_id
      else
        @designations_by_date[d.date][kind] = d.staff_id
      end
    end
  end

  def load_holidays
    holidays = HolidayJp.between(@calendar_begin, @calendar_end)
    @holiday_by_date = holidays.index_by(&:date)
  end

  # 表示・集計用に全職員を preload（draft / confirmed 共通）
  def preload_staffs_for # staff_id→Staffをまとめて引く（N+1防止）staff.idをキーにした、ActiveRecordオブジェクトのhashを作っている。
    @staff_by_id = current_user.staffs
                               .includes(:occupation, :staff_workable_wdays, :staff_unworkable_wdays, :staff_day_time_options)
                               .index_by(&:id)
  end

  def prepare_daily_tab_vars
    @selected_date = parse_selected_date(params[:date]) || @month_begin #日別調整の「選択日」
    @enabled_map = @shift_month.enabled_map_for(@selected_date)
  end

  def prepare_holiday_tab_vars
    @all_staffs = current_user.staffs.order(:last_name_kana, :first_name_kana)

    @selected_staff = 
      if params[:staff_id].present?
        current_user.staffs.find_by(id: params[:staff_id])
      else
        nil
      end

    @selected_staff_holidays =
      if @selected_staff
        @shift_month.staff_holiday_requests.where(staff_id: @selected_staff.id).order(:date)
      else
        StaffHolidayRequest.none
      end

    @holiday_requests_by_date = @shift_month.staff_holiday_requests.includes(:staff).group_by(&:date)
  end

  def build_weekday_requirements_hash
    hash = (0..6).index_with { { "nurse" => 0, "care" => 0 } } # ここで{ 0 => { "nurse" => 0, "care" => 0 }, ..}をつくる

    @shift_month.shift_month_requirements.day.each do |r| # dayはshift_kind: :day　なので使える
      hash[r.day_of_week][r.role] = r.required_number # hash[曜日][役割] = 必要人数　という構成　例）hash[0]["nurse"] = 2
    end

    hash
  end

  #ShiftDayAssignmentのrelationから、{ "YYYY-MM-DD" => { "day" => [{"slot"=>..,"staff_id"=>..}, ...], ... } } を作る
  def build_assignments_hash(scope)
    h = Hash.new { |hh, dkey| hh[dkey] = Hash.new { |hhh, kind| hhh[kind] = [] } }

    scope.find_each do |a|
      dkey = a.date.iso8601
      kind = a.shift_kind.to_s
      h[dkey][kind] << { 
        "slot" => a.slot,
        "staff_id" => a.staff_id,
        "staff_day_time_option_id" => a.staff_day_time_option_id
      }
    end

    h.each_value do |kinds_hash|
      kinds_hash.each_value do |rows|
        rows.sort_by! { |r| r["slot"].to_i }
      end
    end

    h
  end

   # preview/edit_draft/show で共通の「集計・アラート・未割当表示」などをまとめてセットする
  def prepare_calendar_page(assignments_hash:)
    preload_staffs_for

    @unassigned_display_staffs_by_date =
      ShiftDrafts::UnassignedDisplayStaffsBuilder
        .new(dates: @dates, staff_by_id: @staff_by_id, assignments_hash: assignments_hash)
        .call

    @required_skill_by_date = build_required_skill_by_date

    @stats_rows = ShiftDrafts::StatsBuilder.new(
      shift_month: @shift_month,
      staff_by_id: @staff_by_id,
      draft: assignments_hash
    ).call

    alert_dates = (@month_begin..@month_end).to_a
    @alerts_by_date = ShiftDrafts::AlertsBuilder.new(
      dates: alert_dates,
      draft: assignments_hash,
      staff_by_id: @staff_by_id,
      required_by_date: @required_by_date,
      enabled_by_date: {
        day: @day_enabled_by_date,
        early: @early_enabled_by_date,
        late: @late_enabled_by_date,
        night: @night_enabled_by_date
      },
      shift_month: @shift_month
    ).call

    @occupation_order_with_alert = @occupation_order + [
      { key: :alert, label: "アラート", row_class: "occ-row-alert" }
    ]
  end

  def build_required_skill_by_date
    @dates.index_with { |date| @shift_month.required_skill_counts_for(date) }
  end

  def prune_old_shift_months!(user:, keep:)
    extra = user.shift_months.order(created_at: :desc).offset(keep)

    extra.destroy_all
  end

  def weekday_requirements_changed?(shift_month:)
    base_rows =
      current_user.base_weekday_requirements
                  .select(:shift_kind, :day_of_week, :role, :required_number)
                  .map { |r| [r.shift_kind.to_s, r.day_of_week.to_i, r.role.to_s, r.required_number.to_i] }
                  .sort

    month_rows =
      shift_month.shift_month_requirements
                .select(:shift_kind, :day_of_week, :role, :required_number)
                .map { |r| [r.shift_kind.to_s, r.day_of_week.to_i, r.role.to_s, r.required_number.to_i] }
                .sort

    base_rows != month_rows
  end
end
