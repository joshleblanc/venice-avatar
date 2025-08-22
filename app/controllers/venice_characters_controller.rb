class VeniceCharactersController < ApplicationController
  # GET /venice_characters
  def index
    authorize Character

    scope = policy_scope(Character.where(user_created: false))

    # Filter: all | adult | non_adult
    allowed_filters = %w[all adult non_adult]
    @filter = allowed_filters.include?(params[:filter]) ? params[:filter] : "all"
    scope = case @filter
            when "adult" then scope.where(adult: true)
            when "non_adult" then scope.where(adult: [false, nil])
            else scope
            end

    # Sorting
    # sort: name_asc | name_desc | imports_desc | imports_asc
    allowed_sorts = %w[name_asc name_desc imports_desc imports_asc recent_desc]
    @sort = allowed_sorts.include?(params[:sort]) ? params[:sort] : "name_asc"
    scope = case @sort
            when "name_desc"
              scope.order(name: :desc)
            when "imports_desc"
              scope.order(Arel.sql(imports_order_sql(direction: :desc)))
            when "imports_asc"
              scope.order(Arel.sql(imports_order_sql(direction: :asc)))
            when "recent_desc"
              scope.order(Arel.sql(recent_order_sql))
            else
              scope.order(name: :asc)
            end

    @venice_characters = scope
  end

  private

  def imports_order_sql(direction: :desc)
    dir = direction.to_s.upcase == "ASC" ? "ASC" : "DESC"
    adapter = ActiveRecord::Base.connection.adapter_name.downcase

    if adapter.include?("sqlite")
      # Uses JSON1 extension functions available in modern SQLite builds
      "COALESCE(CAST(json_extract(stats, '$.imports') AS INTEGER), 0) #{dir}, name ASC"
    elsif adapter.include?("postgres")
      "COALESCE((stats->>'imports')::int, 0) #{dir}, name ASC"
    elsif adapter.include?("mysql") || adapter.include?("maria")
      "COALESCE(CAST(JSON_UNQUOTE(JSON_EXTRACT(stats, '$.imports')) AS UNSIGNED), 0) #{dir}, name ASC"
    else
      # Fallback: just order by name
      "name ASC"
    end
  end

  def recent_order_sql
    # Most recent first by the best available timestamp
    # Prefer external_updated_at, then external_created_at, then created_at
    adapter = ActiveRecord::Base.connection.adapter_name.downcase
    if adapter.include?("sqlite") || adapter.include?("postgres") || adapter.include?("mysql") || adapter.include?("maria")
      "COALESCE(external_updated_at, external_created_at, created_at) DESC, name ASC"
    else
      "created_at DESC, name ASC"
    end
  end
end
