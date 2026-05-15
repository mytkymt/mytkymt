#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "date"
require "fileutils"
require "yaml"

ROOT = File.expand_path("..", __dir__)
PUBLICATION_ROOT = File.join(ROOT, "content/en/publication")
OUTPUT_DIR = File.join(PUBLICATION_ROOT, "researchmap")
SITE_BASE_URL = "https://www.miyatakeyama.to"

COMMON_HEADERS = [
  "アクション名",
  "アクションタイプ",
  "類似業績マージ優先度",
  "ID",
  "公開の有無",
  "主要な業績かどうか"
].freeze

PUBLISHED_PAPERS_HEADERS = (COMMON_HEADERS + [
  "タイトル(日本語)",
  "タイトル(英語)",
  "著者(日本語)",
  "著者(英語)",
  "担当区分",
  "概要(日本語)",
  "概要(英語)",
  "出版者・発行元(日本語)",
  "出版者・発行元(英語)",
  "出版年月",
  "誌名(日本語)",
  "誌名(英語)",
  "巻",
  "号",
  "開始ページ",
  "終了ページ",
  "記述言語",
  "査読の有無",
  "招待の有無",
  "掲載種別",
  "国際・国内誌",
  "国際共著",
  "ISSN",
  "eISSN",
  "DOI",
  "URL",
  "URL2"
]).freeze

PRESENTATIONS_HEADERS = (COMMON_HEADERS + [
  "タイトル(日本語)",
  "タイトル(英語)",
  "講演者(日本語)",
  "講演者(英語)",
  "会議名(日本語)",
  "会議名(英語)",
  "発表年月日",
  "開催年月日(From)",
  "開催年月日(To)",
  "招待の有無",
  "記述言語",
  "会議種別",
  "主催者(日本語)",
  "主催者(英語)",
  "開催地(日本語)",
  "開催地(英語)",
  "国・地域",
  "概要(日本語)",
  "概要(英語)",
  "国際・国内会議",
  "国際共著",
  "URL",
  "URL2"
]).freeze

MEDIA_COVERAGE_HEADERS = (COMMON_HEADERS + [
  "タイトル(日本語)",
  "タイトル(英語)",
  "執筆者",
  "発行元・放送局(日本語)",
  "発行元・放送局(英語)",
  "番組・新聞雑誌名(日本語)",
  "番組・新聞雑誌名(英語)",
  "報道年月",
  "掲載箇所(日本語)",
  "掲載箇所(英語)",
  "種別",
  "概要(日本語)",
  "概要(英語)",
  "URL"
]).freeze

def front_matter(path)
  text = File.read(path)
  match = text.match(/\A---\s*\n(.*?)\n---/m)
  return {} unless match

  YAML.safe_load(
    match[1],
    permitted_classes: [Date, Time],
    aliases: true
  ) || {}
rescue Psych::SyntaxError => e
  warn "Skipping #{path}: #{e.message}"
  {}
end

def nullish?(value)
  value.nil? || value == "" || value == [] || value == [nil]
end

def value_or_null(value)
  nullish?(value) ? "null" : value.to_s
end

def list_or_null(values)
  values = Array(values).compact.map(&:to_s).reject(&:empty?)
  return "null" if values.empty?

  "[#{values.join(",")}]"
end

def date_value(value)
  return "null" if nullish?(value)

  value.to_s.sub(/T.*/, "")
end

def japanese_text?(value)
  value.to_s.match?(/[ぁ-んァ-ン一-龠々]/)
end

def split_language(value)
  japanese_text?(value) ? [value_or_null(value), "null"] : ["null", value_or_null(value)]
end

def common_row
  {
    "アクション名" => "insert",
    "アクションタイプ" => "merge",
    "類似業績マージ優先度" => "null",
    "ID" => "null",
    "公開の有無" => "disclosed",
    "主要な業績かどうか" => "FALSE"
  }
end

def apply_update_id(row, id)
  return row if nullish?(id)

  row.merge(
    "アクション名" => "update",
    "アクションタイプ" => "doc",
    "類似業績マージ優先度" => "null",
    "ID" => id.to_s
  )
end

def publication_kind(path, data)
  type = Array(data["publication_types"]).first.to_s
  relative_path = path.delete_prefix("#{PUBLICATION_ROOT}/")

  return :media_coverage if relative_path.start_with?("press/") || type == "9"
  return :published_papers if relative_path.start_with?("journal/")
  return :published_papers if %w[3 4 5].include?(type)

  :published_papers
end

def publishing_type(path, data)
  type = Array(data["publication_types"]).first.to_s
  publication = data["publication"].to_s.downcase

  return "scientific_journal" if path.include?("/journal/")
  return "international_conference_proceedings" if type == "3"
  return "research_society" if type == "4"
  return "research_society" if type == "5"
  return "international_conference_proceedings" if publication.match?(/conference|symposium|proceedings|acm|ieee|eurohaptics|dis|uist/)

  "others"
end

def conference_type(data)
  type = Array(data["publication_types"]).first.to_s
  publication = data["publication"].to_s.downcase

  return "poster_presentation" if publication.include?("poster") || type == "4"

  "oral_presentation"
end

def international?(data)
  text = [data["publication"], data["title"], Array(data["authors"]).join(" ")].join(" ")
  japanese_text?(text) ? "FALSE" : "TRUE"
end

def peer_reviewed(data)
  type = Array(data["publication_types"]).first.to_s
  return "FALSE" if type == "5"

  "null"
end

def url_value(data)
  url = value_or_null(data["url_pdf"])
  return "null" if url == "null"
  return "#{SITE_BASE_URL}#{url}" if url.start_with?("/")

  url
end

def published_paper_row(path, data)
  title_ja, title_en = split_language(data["title"])
  authors_ja, authors_en = japanese_text?(Array(data["authors"]).join(" ")) ? [list_or_null(data["authors"]), "null"] : ["null", list_or_null(data["authors"])]
  journal_ja, journal_en = split_language(data["publication"])
  abstract_ja, abstract_en = split_language(data["abstract"])

  common_row.merge(
    "タイトル(日本語)" => title_ja,
    "タイトル(英語)" => title_en,
    "著者(日本語)" => authors_ja,
    "著者(英語)" => authors_en,
    "担当区分" => "null",
    "概要(日本語)" => abstract_ja,
    "概要(英語)" => abstract_en,
    "出版者・発行元(日本語)" => "null",
    "出版者・発行元(英語)" => "null",
    "出版年月" => date_value(data["date"]),
    "誌名(日本語)" => journal_ja,
    "誌名(英語)" => journal_en,
    "巻" => "null",
    "号" => "null",
    "開始ページ" => "null",
    "終了ページ" => "null",
    "記述言語" => japanese_text?(data["title"]) ? "jpn" : "eng",
    "査読の有無" => peer_reviewed(data),
    "招待の有無" => "null",
    "掲載種別" => publishing_type(path, data),
    "国際・国内誌" => international?(data),
    "国際共著" => "null",
    "ISSN" => "null",
    "eISSN" => "null",
    "DOI" => value_or_null(data["doi"]),
    "URL" => url_value(data),
    "URL2" => "null"
  )
end

def presentation_row(_path, data)
  title_ja, title_en = split_language(data["title"])
  speakers_ja, speakers_en = japanese_text?(Array(data["authors"]).join(" ")) ? [list_or_null(data["authors"]), "null"] : ["null", list_or_null(data["authors"])]
  meeting_ja, meeting_en = split_language(data["publication"])
  abstract_ja, abstract_en = split_language(data["abstract"])

  common_row.merge(
    "タイトル(日本語)" => title_ja,
    "タイトル(英語)" => title_en,
    "講演者(日本語)" => speakers_ja,
    "講演者(英語)" => speakers_en,
    "会議名(日本語)" => meeting_ja,
    "会議名(英語)" => meeting_en,
    "発表年月日" => date_value(data["date"]),
    "開催年月日(From)" => "null",
    "開催年月日(To)" => "null",
    "招待の有無" => "null",
    "記述言語" => japanese_text?(data["title"]) ? "jpn" : "eng",
    "会議種別" => conference_type(data),
    "主催者(日本語)" => "null",
    "主催者(英語)" => "null",
    "開催地(日本語)" => "null",
    "開催地(英語)" => "null",
    "国・地域" => "null",
    "概要(日本語)" => abstract_ja,
    "概要(英語)" => abstract_en,
    "国際・国内会議" => international?(data),
    "国際共著" => "null",
    "URL" => url_value(data),
    "URL2" => "null"
  )
end

def media_coverage_row(_path, data)
  title_ja, title_en = split_language(data["title"])
  source_ja, source_en = split_language(data["publication"])
  summary_ja, summary_en = split_language(data["summary"] || data["abstract"])

  common_row.merge(
    "タイトル(日本語)" => title_ja,
    "タイトル(英語)" => title_en,
    "執筆者" => "other_than_myself",
    "発行元・放送局(日本語)" => source_ja,
    "発行元・放送局(英語)" => source_en,
    "番組・新聞雑誌名(日本語)" => source_ja,
    "番組・新聞雑誌名(英語)" => source_en,
    "報道年月" => date_value(data["date"]),
    "掲載箇所(日本語)" => "null",
    "掲載箇所(英語)" => "null",
    "種別" => "internet",
    "概要(日本語)" => summary_ja,
    "概要(英語)" => summary_en,
    "URL" => url_value(data)
  )
end

def write_researchmap_csv(path, type_name, headers, rows)
  if rows.empty?
    FileUtils.rm_f(path)
    return
  end

  CSV.open(path, "w", encoding: "UTF-8", force_quotes: false) do |csv|
    csv << [type_name]
    csv << headers
    rows.each do |row|
      csv << headers.map { |header| row.fetch(header, "null") }
    end
  end
end

def validate_researchmap_csv!(path, expected_headers)
  rows = CSV.read(path)
  type_row, header_row, *data_rows = rows
  raise "#{path}: first row is missing" if type_row.nil? || type_row.empty?
  raise "#{path}: header row is missing" if header_row.nil?
  raise "#{path}: unexpected headers" unless header_row == expected_headers
  raise "#{path}: duplicate headers found" unless header_row.uniq.length == header_row.length

  forbidden_headers = [
    "会員 ID",
    "DOI ランディング先",
    "DOI 無償アクセス可否",
    "DOI 公開開始(予定)日",
    "DOI2",
    "DOI2 ランディング先",
    "DOI2 無償アクセス可否",
    "DOI2 公開開始(予定)日",
    "URL 無償アクセス可否",
    "URL 公開開始(予定)日",
    "URL2 無償アクセス可否",
    "URL2 公開開始(予定)日",
    "関連情報 URL",
    "関連情報 URL2"
  ]
  found_forbidden = header_row & forbidden_headers
  raise "#{path}: forbidden headers found: #{found_forbidden.join(", ")}" unless found_forbidden.empty?

  data_rows.each_with_index do |row, index|
    line = index + 3
    raise "#{path}: line #{line} has #{row.length} columns; expected #{header_row.length}" unless row.length == header_row.length
    raise "#{path}: line #{line} has blank cells; use null" if row.any? { |cell| cell.nil? || cell == "" }

    if type_row.first == "published_papers"
      title_ja = row[header_row.index("タイトル(日本語)")]
      title_en = row[header_row.index("タイトル(英語)")]
      authors_ja = row[header_row.index("著者(日本語)")]
      authors_en = row[header_row.index("著者(英語)")]
      publication_date = row[header_row.index("出版年月")]

      raise "#{path}: line #{line} has no title" if [title_ja, title_en].all? { |cell| cell == "null" }
      raise "#{path}: line #{line} has no authors" if [authors_ja, authors_en].all? { |cell| cell == "null" }
      raise "#{path}: line #{line} has no publication date" if publication_date == "null"
    elsif type_row.first == "media_coverage"
      title_ja = row[header_row.index("タイトル(日本語)")]
      title_en = row[header_row.index("タイトル(英語)")]

      raise "#{path}: line #{line} has no title" if [title_ja, title_en].all? { |cell| cell == "null" }
    end
  end
end

paths = Dir.glob(File.join(PUBLICATION_ROOT, "**/index.md")).sort
rows = {
  published_papers: [],
  presentations: [],
  media_coverage: []
}
seen_published_papers = {}

paths.each do |path|
  data = front_matter(path)
  next if data.empty? || nullish?(data["title"])

  case publication_kind(path, data)
  when :published_papers
    dedupe_key = if !nullish?(data["doi"])
                   "doi:#{data["doi"].to_s.downcase}"
                 else
                   title = data["title"].to_s.downcase.gsub(/\s+/, " ").strip
                   date = date_value(data["date"])
                   "title:#{title}:#{date}"
                 end
    next if seen_published_papers[dedupe_key]

    seen_published_papers[dedupe_key] = true
    rows[:published_papers] << published_paper_row(path, data)
  when :presentations
    rows[:presentations] << presentation_row(path, data)
  when :media_coverage
    rows[:media_coverage] << media_coverage_row(path, data)
  end
end

FileUtils.mkdir_p(OUTPUT_DIR)
write_researchmap_csv(
  File.join(OUTPUT_DIR, "published_papers.csv"),
  "published_papers",
  PUBLISHED_PAPERS_HEADERS,
  rows[:published_papers]
)
write_researchmap_csv(
  File.join(OUTPUT_DIR, "presentations.csv"),
  "presentations",
  PRESENTATIONS_HEADERS,
  rows[:presentations]
)
write_researchmap_csv(
  File.join(OUTPUT_DIR, "media_coverage.csv"),
  "media_coverage",
  MEDIA_COVERAGE_HEADERS,
  rows[:media_coverage]
)

validate_researchmap_csv!(File.join(OUTPUT_DIR, "published_papers.csv"), PUBLISHED_PAPERS_HEADERS) if rows[:published_papers].any?
validate_researchmap_csv!(File.join(OUTPUT_DIR, "presentations.csv"), PRESENTATIONS_HEADERS) if rows[:presentations].any?
validate_researchmap_csv!(File.join(OUTPUT_DIR, "media_coverage.csv"), MEDIA_COVERAGE_HEADERS) if rows[:media_coverage].any?

puts "Generated #{rows[:published_papers].size} published_papers rows"
puts "Generated #{rows[:presentations].size} presentations rows"
puts "Generated #{rows[:media_coverage].size} media_coverage rows"
