module ShiftMonthsHelper
  # 画面の「固定５行」を寄せるためのキーを返す
  # staff がnillのときはnil
  def row_key_for(staff)
    return nil if staff.nil?

    name = staff.occupation&.name.to_s

    return :nurse     if name.include?("看護")
    return :care_mgr  if name.include?("ケアマネ")
    return :care      if name.include?("介護")
    return :cook      if name.include?("管理栄養士")
    return :clerk     if name.include?("事務")

    nil
  end

   # staff_by_id から row_key ごとの「並び済みスタッフ配列」を返す（1リクエスト内でメモ化）
  def sorted_staffs_for_row(staff_by_id:, row_key:)
    @__sorted_staffs_by_row_key ||= begin
      staff_by_id.values
                 .select { |s| s&.active? }
                 .group_by { |s| row_key_for(s) }
                 .transform_values do |list|
                   list.sort_by do |s|
                     [
                       s.workday_constraint == "free" ? 0 : 1,
                       s.last_name_kana.to_s,
                       s.first_name_kana.to_s,
                       s.id.to_i
                     ]
                   end
                 end
    end

    @__sorted_staffs_by_row_key[row_key] || []
  end

  def alert_badge_class(msg)
    msg = msg.to_s

    if msg.include?("6連勤") || msg.include?("5連勤超")
      "text-bg-danger"
    elsif msg.include?("夜勤明けに勤務が衝突") ||
          msg.include?("夜勤明けに休日指定が衝突") ||
          msg.include?("明け翌日休みに勤務指定が衝突")
      "text-bg-danger"
    elsif msg.include?("2連休未成立")
      "text-bg-warning"
    else
      "text-bg-secondary"
    end
  end

  # data(draft/saved) から date 1日分の rows を取り出す（キー揺れに強く）
  def shift_day_rows(data, date)
    day_hash = (data || {})[date.iso8601] || {}

    {
      day_rows:   day_hash["day"]   || day_hash[:day]   || [],
      early_rows: day_hash["early"] || day_hash[:early] || [],
      late_rows:  day_hash["late"]  || day_hash[:late]  || [],
      night_rows: day_hash["night"] || day_hash[:night] || []
    }
  end

  # night_rows の先頭から staff_id を安全に取り出す
  def shift_first_staff_id(rows)
    first = Array(rows).first
    return nil if first.nil?

    sid = first.is_a?(Hash) ? (first["staff_id"] || first[:staff_id]) : nil
    sid.to_i if sid.present?
  end

  # viewでよく使う「rows + 夜勤/明けID」までまとめて返す
  def shift_day_context(data, date)
    pack = shift_day_rows(data, date)

    night_sid = shift_first_staff_id(pack[:night_rows])

    prev_pack = shift_day_rows(data, date - 1)
    night_off_sid = shift_first_staff_id(prev_pack[:night_rows])

    {
      **pack,
      night_sid: night_sid.to_i,
      night_off_sid: night_off_sid.to_i,
      night_related_ids: [night_sid, night_off_sid].compact.map(&:to_i)
    }
  end

    # rows（draft/savedの各kind配列）から staff_id を全部集める
  def assigned_staff_ids_from_rows(day_rows:, early_rows:, late_rows:, night_rows:)
    ids = []
    { day: day_rows, early: early_rows, late: late_rows, night: night_rows }.each do |_k, rows|
      Array(rows).each do |r|
        sid = r.is_a?(Hash) ? (r["staff_id"] || r[:staff_id]) : nil
        sid = sid.to_i
        ids << sid if sid > 0
      end
    end
    ids
  end

  # holiday_requests_by_date[date] の要素が「request」でも「id」でも吸収して staff_id配列にする
  def holiday_staff_ids_for(holiday_requests_by_date, date)
    list = holiday_requests_by_date && holiday_requests_by_date[date]
    Array(list).map do |x|
      if x.respond_to?(:staff_id)
        x.staff_id
      elsif x.respond_to?(:staff) && x.staff.respond_to?(:id)
        x.staff.id
      else
        x
      end
    end.map(&:to_i).select { |id| id > 0 }
  end

  # preview/edit_draft の alert 行で msgs を増やす（夜勤明け/明け翌日休みの衝突）
  def augment_alert_messages_for_night_conflicts(base_msgs:, draft:, date:, holiday_requests_by_date:, designations_by_date:)
    msgs = Array(base_msgs).dup

    ctx = shift_day_context(draft, date)
    night_off_id = ctx[:night_off_sid].to_i

    today_assigned_ids = assigned_staff_ids_from_rows(
      day_rows: ctx[:day_rows],
      early_rows: ctx[:early_rows],
      late_rows: ctx[:late_rows],
      night_rows: ctx[:night_rows]
    )

    # ① 夜勤明け（前日の夜勤者）が当日に勤務していたら衝突
    if night_off_id > 0 && today_assigned_ids.include?(night_off_id)
      msgs << "夜勤明けに勤務が衝突"
    end

    # ①-2 夜勤明け（前日の夜勤者）が当日に休日指定されていたら衝突
    if night_off_id > 0
      holiday_ids_today = holiday_staff_ids_for(holiday_requests_by_date, date)
      msgs << "夜勤明けに休日指定が衝突" if holiday_ids_today.include?(night_off_id)
    end

    # ② 明け翌日の休み（夜勤入りの2日後）：当日に勤務指定が入ってたら衝突
    if designations_by_date.present?
      night_in_day = date - 2
      night_in_ctx = shift_day_context(draft, night_in_day)
      night_in_sid = night_in_ctx[:night_sid].to_i

      if night_in_sid > 0
        desig = designations_by_date[date] || {}
        desig_staff_ids =
          desig.values
              .flatten
              .map(&:to_i)
              .reject { |x| x <= 0 }
        msgs << "明け翌日休みに勤務指定が衝突" if desig_staff_ids.include?(night_in_sid)
      end
    end

    msgs
  end
end
