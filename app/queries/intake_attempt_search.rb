class IntakeAttemptSearch
  DEFAULT_PER_PAGE = 50

  def initialize(params)
    @params = params
  end

  def results
    scope = IntakeAttempt.order(created_at: :desc)
    scope = scope.where(status: @params[:status]) if present?(:status)
    scope = scope.where(club: @params[:club]) if present?(:club)

    if present?(:q)
      q = @params[:q].to_s.strip
      scope = scope.where(
        "(to_tsvector('simple', coalesce(email,'') || ' ' || coalesce(status,'') || ' ' || coalesce(error_message,'') || ' ' || coalesce(request_payload::text,'') || ' ' || coalesce(response_payload::text,'')) @@ plainto_tsquery('simple', ?)
         OR email ILIKE ? OR status ILIKE ? OR error_message ILIKE ?)",
        q,
        "%#{q}%",
        "%#{q}%",
        "%#{q}%"
      )
    end

    scope
  end

  def page
    (@params[:page] || 1).to_i
  end

  def per_page
    (@params[:per_page] || DEFAULT_PER_PAGE).to_i
  end

  def paged_results
    results.limit(per_page).offset((page - 1) * per_page)
  end

  private

  def present?(key)
    value = @params[key]
    value.respond_to?(:strip) ? value.strip.present? : value.present?
  end
end
