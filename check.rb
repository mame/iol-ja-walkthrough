class CheckError < StandardError; end

def error(msg)
  raise CheckError, msg
end

def check_index_md(src, contest, year)
  error "wrong format" unless src =~ %r{\A
    \+\+\+\n
    year\s=\s#{ year }\n
    problem_url\s=\s'([^'\n]+)'\n
    \+\+\+\n
  \z}x
  problem_url = $1
  error "wrong url: #{ problem_url }" unless problem_url.include?(contest)
  error "wrong url: #{ problem_url }" unless problem_url.include?(year.to_s)
end

def check_md(src, line_offset)
  errors = {}
  src.lines.each_with_index do |line, lineno|
    error_cols = []
    next if line.start_with?("|")
    line = line.gsub(/^\s*\*/, "").gsub(/\[([^\[]+)\]\(.+?\)/) { $1 }.gsub("**", "").lstrip
    error "line too long: #{ line }" if line.size > 120
    (0 ... line.size - 1).map do |i|
      c = line[i]
      a = c =~ /[\x21-\u1fff]/
      w = c =~ /[\p{Hiragana}\p{Katakana}\p{Han}\u3000-\u303f\uFF01-\uFF60\uFFE0-\uFFE6≠]/
      [c, a, w]
    end.each_cons(2).with_index do |((c1, a1, w1), (c2, a2, w2)), col|
      case
      when a1 && w2
        next if c1 =~ /\A[\[\]]\z/
        next if c2 =~ /\A[：「」～（）]\z/
      when w1 && a2
        next if c1 =~ /\A[：、。「」～（）]\z/
        next if c2 =~ /\A[\[\]]\z/
      when c1 == " " && c2 == " "
      when c1 =~ /\d/ && c2 == "."
      when c1 == "、" && c2 == " "
      when c1 == " " && c2 == "「"
      when c1 == "」" && c2 == " "
      when c1 == "：" && c2 == " "
      when c1 == "＋"
      when c1 == "＝"
      when c1 == "◯"
      when c1 == ":" && c2 == " "
      else
        next
      end
      error_cols << col << col + 1
    end
    unless error_cols.empty?
      errors[lineno] ||= [line, error_cols.sort.uniq]
    end
  end
  unless errors.empty?
    msg = []
    errors.keys.sort.map do |lineno|
      line, cols = errors[lineno]
      line = line.dup
      cols.reverse_each do |col|
        line[col + 1, 0] = "\e[m"
        line[col, 0] = "\e[41m"
      end
      msg << "#{ lineno + line_offset }: #{ line }"
    end
    error "\n#{ msg.join }"
  end
end

def check_problem_md(src, contest, year, index)
  error "wrong format" unless src =~ %r{\A
    (
      \+\+\+\n
      index\s=\s#{ index }\n
      lang\s=\s'[^\n]+'\n
      level\s=\s\d+\n
      tags\s=\s\[[^\n]+\]\n
      (note\s=\strue\n)?
      \+\+\+\n
      \n
      \#\sdetails\n
    )
    (.*)
    \#\s\/details\n
  \z}xm
  line_offset = $1.lines.size
  note = $2
  src = $3
  sections = []
  section = nil
  src.scan(/^(#+)(.*)$/) do |level, heading|
    unless heading =~ /^\s/
      error "heading no space"
    end
    level = level.size
    heading = heading.strip
    case level
    when 2
      sections << section = []
      section << heading
    when 3
      section << heading
    else
      error "wrong heading level (#{ level }): #{ heading }"
    end
  end
  if sections.size == 1
    heading = sections.first.first
    error "wrong heading: #{ heading }" unless heading == "ヒント"
  end
  index = 1
  if note
    error "note should be false" unless sections.first.first == "問題文に関する注意点"
  end
  sections.each do |heading, *subheadings|
    case heading
    when "ヒント"
      index = "ABCDE"
    when /\Aヒント #{ index }\z/
      index += 1 if index != ""
    when "問題の要約（参考）", "問題文に関する注意点", "余談"
    else
      error "wrong heading: #{ heading }"
    end
    if subheadings.first == "さらなるヒント"
      unless subheadings.size == 1 || subheadings.size == 2 && subheadings.last == "答え"
        error "wrong subheadings: #{ subheadings.inspect }"
      end
    else
      subindex = 1
      subheadings.each do |subheading|
        case subheading
        when /\A#{ heading }-#{ subindex }\z/
          subindex += 1
        when /\A答え\z/
        else
          error "wrong subheading: #{ subheading }"
        end
      end
      error "use さらなるヒント" if subindex == 2
    end
  end
  check_md(src, line_offset)
end

def check_misc_md(src)
  error "wrong format?" unless src =~ %r{\A
    (
      \+\+\+\n
      (?:\w+\s=\s[^\n]+\n)+
      \+\+\+\n
    )
    (.*)
  \z}xm
  check_md($2, $1.lines.size)
end

def check_md_file(path)
  src = File.read(path)
  case path
  when /\Acontent\/(\w+)\/(\d+)\/_index\.md\z/
    check_index_md(src, $1, $2.to_i)
  when /\Acontent\/(\w+)\/(\d+)\/(\d+)\.md\z/
    check_problem_md(src, $1, $2.to_i, $3.to_i)
  when /\Acontent\/tags\/\w+\/_index\.md\z/
    check_misc_md(src)
  else
    check_misc_md(src)
  end
rescue CheckError
  puts "#{ path }: #{ $!.message }"
end

argv = ARGV
argv = Dir.glob("content/**/*.md") if argv.empty?
argv.each do |f|
  check_md_file(f)
end
