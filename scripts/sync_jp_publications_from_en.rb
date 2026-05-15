#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"

ROOT = Pathname.new(__dir__).parent
SOURCE_ROOT = ROOT.join("content/en/publication")
TARGET_ROOT = ROOT.join("content/jp/publication")

overwrite = ARGV.include?("--overwrite")
dry_run = ARGV.include?("--dry-run")

def ignored_path?(path)
  path.each_filename.any? { |part| part == "researchmap" || part.start_with?(".") }
end

def copy_file(source, target, dry_run:)
  puts "#{dry_run ? "would copy" : "copy"} #{source.relative_path_from(ROOT)} -> #{target.relative_path_from(ROOT)}"
  return if dry_run

  FileUtils.mkdir_p(target.dirname)
  FileUtils.cp(source, target)
end

copied_entries = 0
copied_assets = 0
skipped_entries = 0

SOURCE_ROOT.glob("**/index.md").sort.each do |source_index|
  relative_dir = source_index.dirname.relative_path_from(SOURCE_ROOT)
  next if ignored_path?(relative_dir)

  source_dir = source_index.dirname
  target_dir = TARGET_ROOT.join(relative_dir)
  target_index = target_dir.join("index.md")

  if target_index.exist? && !overwrite
    skipped_entries += 1
  else
    source_dir.find do |source|
      next if source.directory?
      next if ignored_path?(source.relative_path_from(SOURCE_ROOT))

      relative_file = source.relative_path_from(SOURCE_ROOT)
      target = TARGET_ROOT.join(relative_file)
      copy_file(source, target, dry_run: dry_run)
    end
    copied_entries += 1
    next
  end

  source_dir.find do |source|
    next if source.directory?
    next if source.basename.to_s == "index.md"
    next if ignored_path?(source.relative_path_from(SOURCE_ROOT))

    relative_file = source.relative_path_from(SOURCE_ROOT)
    target = TARGET_ROOT.join(relative_file)
    next if target.exist?

    copy_file(source, target, dry_run: dry_run)
    copied_assets += 1
  end
end

puts "publication sync complete: copied_entries=#{copied_entries}, copied_assets=#{copied_assets}, skipped_existing_entries=#{skipped_entries}"
