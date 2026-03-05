Rails.application.config.session_store :cookie_store,
  key: "_mimosa_shift_planner_session",
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax
