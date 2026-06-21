module ShiftDrafts
  class AlertsBuilder
    def initialize(dates:, draft:, staff_by_id:, required_by_date:, enabled_by_date:, shift_month:)
      @dates = dates
      @draft = draft
      @staff_by_id = staff_by_id
      @required_by_date = required_by_date
      @enabled_by_date = enabled_by_date
      @shift_month = shift_month
    end

    def call
      alerts = {}

      @dates.each do |date|
        list = []

        dkey = date.iso8601
        kinds_hash = @draft[dkey] || {}

        # ---- 日勤不足（dayのみで看護/介護を数える）----
        if enabled?(:day, date)
          req = @required_by_date[date] || { nurse: 0, care: 0 }
          req_nurse = req[:nurse].to_i
          req_care = req[:care].to_i

          if req_nurse > 0 || req_care > 0
            actual = day_actual_counts(kinds_hash)
            lack_nurse = [req_nurse - actual[:nurse], 0].max
            lack_care  = [req_care - actual[:care],   0].max

            if lack_nurse > 0 || lack_care > 0
              parts = []
              parts << "看#{lack_nurse}不足" if lack_nurse > 0
              parts << "介#{lack_care}不足"  if lack_care  > 0
              list << "日勤：#{parts.join(' ')}"
            end
          end
        end

        # 日勤スキル不足(dayのみで運転/調理を数える)
        if enabled?(:day, date)
          req_skill = @shift_month.required_skill_counts_for(date) || { drive: 0, cook: 0 }
          actual_skill = day_actual_skill_counts(kinds_hash)
          lack_drive = [req_skill[:drive].to_i - actual_skill[:drive], 0].max
          lack_cook  = [req_skill[:cook].to_i  - actual_skill[:cook],  0].max

          if lack_drive > 0 || lack_cook > 0
            parts = []
            parts << "運転#{lack_drive}不足" if lack_drive > 0
            parts << "調理#{lack_cook}不足"  if lack_cook  > 0
            list << parts.join(' ')
          end
        end

        # ---- 早番/遅番/夜勤不足（ONなのに1人も入っていない）----
        list << "早番不足" if enabled?(:early, date) && blank_kind?(kinds_hash, "early")

        if enabled?(:late, date)
          required = @shift_month.late_slots_for(date).to_i
          required = 1 if required <= 0
          required = 2 if required >= 2

          late_rows = (kinds_hash["late"] || kinds_hash[:late])
          actual = Array(late_rows).size
          lack = [required - actual, 0].max

          list << "遅番:#{lack}不足" if lack > 0
        end

        list << "夜勤不足" if enabled?(:night, date) && blank_kind?(kinds_hash, "night")

        alerts[date] = list
      end

      append_consecutive_work_alerts!(alerts)
      append_night_conflict_alerts!(alerts)
      append_monthly_holiday_shortage_alerts!(alerts)
      alerts
    end

    private

    # 連勤系アラート
    # 6連勤が入った日にアラート/５連勤後の２連休に勤務指定が入って休みにならなかった場合のアラート
    def append_consecutive_work_alerts!(alerts)
      return if @dates.blank?

      designations = @shift_month.shift_day_designations.where(date: @dates.first..@dates.last)

      designations_by_date = Hash.new { |h, k| h[k] = {} }

      designations.each do |d|
        kind = d.shift_kind.to_s

        if kind == "day" || kind == "late"
          (designations_by_date[d.date][kind] ||= []) << d.staff_id
        else
          designations_by_date[d.date][kind] = d.staff_id
        end
      end

      staff_ids = @staff_by_id.keys.map(&:to_i)

      staff_ids.each do |sid|
        streak = 0 # streak : 連続勤務のカウント

        @dates.each_with_index do |date, idx|
          if worked_dayish?(sid, date)
            streak += 1

            max_days = max_consecutive_work_days_for(sid)

            # 個別の最大連勤日数を超えた日に表示
            if streak == max_days + 1
              (alerts[date] ||= []) << "#{staff_label(sid)}#{max_days}連勤超"
            end

            # 5連勤に到達した日に、翌日/翌々日の「２連休が成立しているか」チェック
            if streak == 5
              [1, 2].each do |offset|
                d = @dates[idx + offset]
                break if d.nil?

                next unless worked_any_kind?(sid, d) # 本来休みの日に何か勤務が入ってしまった



                msg = "2連休未成立"
                if designated_any_kind?(designations_by_date, sid, d)
                  msg = "2連休未成立(指定優先)"
                end

                (alerts[d] ||= []) << "#{staff_label(sid)}#{msg}"
              end
            end
          else
            streak = 0
          end
        end
      end
    end

    # そのstaffがその日に「日勤系」に入っているか？
    def worked_dayish?(staff_id, date)
      dkey = date.iso8601
      kinds_hash = @draft[dkey] || {}

      %w[day early late].any? do |kind|
        rows = kinds_hash[kind] || kinds_hash[kind.to_sym]
        Array(rows).any? { |row| extract_staff_id(row).to_i == staff_id.to_i }
      end
    end

    # そのstaffがその日に何か勤務が入っているか？
    def worked_any_kind?(staff_id, date)
      dkey = date.iso8601
      kinds_hash = @draft[dkey] || {}

      %w[day early late night].any? do |kind|
        rows = kinds_hash[kind] || kinds_hash[kind.to_sym]
        Array(rows).any? { |row| extract_staff_id(row).to_i == staff_id.to_i }
      end
    end

    # そのstaffがその日に勤務指定されているか？
    def designated_any_kind?(designations_by_date, staff_id, date)
      h = designations_by_date[date]
      return false if h.blank?

      sid = staff_id.to_i

      day = h["day"]
      return true if Array(day).any? { |x| x.to_i == sid }

      late = h["late"]
      return true if Array(late).any? { |x| x.to_i == sid }

      return true if h["early"].to_i == sid
      return true if h["night"].to_i == sid

      false
    end

    def staff_label(staff_id)
      s = @staff_by_id[staff_id.to_i]
      return "職員#{staff_id}" if s.nil?
      s.last_name.to_s
    end

    # 夜勤明けに勤務や休日指定が重なっていたらアラート
    # 夜勤3日目の休みに勤務や休日指定が重なっていたらアラート
    def append_night_conflict_alerts!(alerts)
      return if @dates.blank?
      # holiday request を日付 => Set[staff_id]にして引けるようにする
      holiday_ids_by_date =
        @shift_month.staff_holiday_requests
                    .where(date: @dates.first..@dates.last)
                    .group_by(&:date)
                    .transform_values { |rows| rows.map(&:staff_id).map(&:to_i).to_set }

      staff_ids = @staff_by_id.keys.map(&:to_i)

      @dates.each do |date|
        prev  = date - 1
        prev2 = date - 2

        staff_ids.each do |sid|
          if worked_kind?(sid, prev, :night)
            if worked_any_kind?(sid, date) || holiday_ids_by_date.fetch(date, Set.new).include?(sid)
              (alerts[date] ||= []) << "#{staff_label(sid)}夜勤明け衝突"
            end
          end

          if worked_kind?(sid, prev2, :night)
            if worked_any_kind?(sid, date) || holiday_ids_by_date.fetch(date, Set.new).include?(sid)
              (alerts[date] ||= []) << "#{staff_label(sid)}夜勤休み衝突"
            end
          end
        end
      end
    end

    def worked_kind?(staff_id, date, kind_sym)
      return false if date.nil?
      dkey = date.iso8601
      kinds_hash = @draft[dkey] || {}
      rows = kinds_hash[kind_sym.to_s] || kinds_hash[kind_sym.to_sym]
      Array(rows).any? { |row| extract_staff_id(row).to_i == staff_id.to_i }
    end

    def append_monthly_holiday_shortage_alerts!(alerts)
      required = @shift_month.holiday_days.to_i
      return if required <= 0

      free_staffs = @staff_by_id.values.select { |s| s.workday_constraint.to_s == "free" }
      return if free_staffs.empty?

      total_days = @dates.length
      worked_days = Hash.new(0)

      @dates.each do |date|
        dkey = date.iso8601
        kinds_hash = @draft[dkey] || {}

        assigned_ids = kinds_hash.values
                                 .flat_map { |rows| Array(rows).map { |row| extract_staff_id(row) } }
                                 .compact
                                 .uniq

        assigned_ids.each { |sid| worked_days[sid] += 1 }
      end
    end

    def enabled?(kind_sym, date)
      map = @enabled_by_date[kind_sym]
      return false if map.nil?
      map[date] == true
    end

    def blank_kind?(kinds_hash, kind_str)
      rows = kinds_hash[kind_str] || kinds_hash[kind_str.to_sym]
      Array(rows).empty?
    end

    # day の rows から occupation をみて nurse/care を数える
    def day_actual_counts(kinds_hash)
      nurse = 0
      care = 0

      Array(kinds_hash["day"]).each do |row|
        sid = extract_staff_id(row)
        next if sid.nil?

        staff = @staff_by_id[sid.to_i]
        next if staff.nil?
        next unless staff.counts_toward_requirements?

        occ_name = staff.occupation&.name.to_s

        nurse += 1 if occ_name.include?("看護")
        care  += 1 if occ_name.include?("介護")
      end

      { nurse: nurse, care: care }
    end

    # dayのrowsからstaff.can_drive/ staff.can_cookを見てスキル充足を数える

    def day_actual_skill_counts(kinds_hash)
      drive = 0
      cook  = 0

      Array(kinds_hash["day"]).each do |row|
        sid = extract_staff_id(row)
        next if sid.nil?

        staff = @staff_by_id[sid.to_i]
        next if staff.nil?
        next unless staff.counts_toward_requirements?

        drive += 1 if staff.respond_to?(:can_drive) && staff.can_drive
        cook  += 1 if staff.respond_to?(:can_cook)  && staff.can_cook
      end

      { drive: drive, cook: cook }
    end

    def extract_staff_id(row)
      return nil if row.nil?
      return row.to_i unless row.is_a?(Hash)

      v = row["staff_id"] || row[:staff_id]
      v.present? ? v.to_i : nil
    end

    def max_consecutive_work_days_for(staff_id)
      staff = @staff_by_id[staff_id.to_i]
      return 5 if staff.nil?
      return 5 unless staff.workday_constraint.to_s == "free"

      days = staff.max_consecutive_work_days.to_i
      days.clamp(1, 5)
    end
  end
end
