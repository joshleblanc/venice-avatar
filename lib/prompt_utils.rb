module PromptUtils
  # Normalize a prompt into a concise, Civitai-style comma-separated tag list
  # - Lowercase
  # - Remove quotes and most punctuation except commas and hyphens
  # - Split on commas/newlines, trim, dedupe, drop empties
  # - Optionally append always_include tokens if missing
  # - Optionally enforce max_len by adding tokens until the limit is reached
  def self.normalize_tag_list(input, max_len: nil, always_include: [])
    str = (input || "").to_s.downcase
    # Replace newlines and semicolons with commas
    str = str.gsub(/[\n;]+/, ", ")
    # Remove quotes and brackets and other non-essential punctuation, keep commas and hyphens
    # Safe char class: escape only ], \/, and \
    str = str.gsub(/["'`:\[\](){}|\/\\!?]/, "")
    # Collapse multiple spaces and spaces around commas
    str = str.gsub(/\s*,\s*/, ", ").gsub(/\s+/, " ")

    # Split into tokens on commas
    raw_tokens = str.split(/\s*,\s*/)
    tokens = []
    seen = {}

    raw_tokens.each do |tok|
      t = tok.strip
      next if t.empty?
      # Remove trailing periods and trailing commas/spaces
      t = t.gsub(/[\.,]+$/, "")
      next if t.empty?
      next if seen[t]
      seen[t] = true
      tokens << t
    end

    # Ensure always_include tokens are present (at the end, preserving order)
    always_include.each do |tok|
      next if tok.to_s.empty?
      t = tok.downcase.strip
      unless seen[t]
        tokens << t
        seen[t] = true
      end
    end

    # Rebuild within max_len if provided
    if max_len && max_len.to_i > 0
      limited = []
      total = 0
      tokens.each_with_index do |t, i|
        sep = i.zero? ? 0 : 2 # ", " length
        break if total + sep + t.length > max_len
        limited << t
        total += sep + t.length
      end
      tokens = limited
    end

    tokens.join(", ")
  end
end
