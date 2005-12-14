require 'erb'
require 'fileutils'

begin
  require 'rss/maker'
rescue LoadError
end

require 'rabbit/rabbit'
require 'rabbit/front'
require 'rabbit/utils'

module Rabbit
  module HTML
    class Generator
      extend ERB::DefMethod

      include ERB::Util

      path = ["rabbit", "html", "template.erb"]
      template_path = Utils.find_path_in_load_path(*path)
      raise CantFindHTMLTemplate.new(File.join(*path)) if template_path.nil?
      def_erb_method("to_html(file_name_format, slide_number, image_type)",
                     template_path)
      
      def initialize(canvas)
        @canvas = canvas
        @suffix = "html"
        @rss_info = []
        @rss_file_name = "index.rdf"
      end

      def save(file_name_format, slide_number, image_type)
        file_name = slide_file_name(file_name_format, slide_number)
        File.open(file_name, "w") do |f|
          f.print(to_html(file_name_format, slide_number, image_type))
        end
        @rss_info << [file_name, slide_title, @canvas.current_slide.to_html]
      end

      def save_rss(base_dir, base_uri)
        if Object.const_defined?(:RSS)
          rss = make_rss(base_uri)
          name = File.join(base_dir, @rss_file_name)
          File.open(name, "w") do |f|
            f.print(rss.to_s)
          end
          true
        else
          false
        end
      end

      private
      def make_file_name(file_name_format, slide_number, suffix=@suffix)
        file_name_format % [slide_number, suffix]
      end

      def slide_file_name(file_name_format, slide_number)
        if slide_number.zero?
          File.join(File.dirname(file_name_format), "index.#{@suffix}")
        else
          make_file_name(file_name_format, slide_number, @suffix)
        end
      end
        
      def a_link(file_name_format, slide_number, label, label_only)
        name = slide_file_name(file_name_format, slide_number)
        href = File.basename(name)
        HTML.a_link("<a href=\"#{href}\">", label, label_only)
      end

      def first_slide?(slide_number)
        slide_number.zero?
      end

      def last_slide?(slide_number)
        @canvas.slide_size.zero? or slide_number == @canvas.slide_size - 1
      end
      
      def first_link(file_name_format, slide_number)
        a_link(file_name_format, 0, h("<<"), first_slide?(slide_number))
      end

      def previous_link(file_name_format, slide_number)
        a_link(file_name_format, slide_number - 1,
               h("<"), first_slide?(slide_number))
      end

      def next_link(file_name_format, slide_number)
        a_link(file_name_format, slide_number + 1,
               h(">"), last_slide?(slide_number))
      end

      def last_link(file_name_format, slide_number)
        a_link(file_name_format, @canvas.slide_size - 1,
               h(">>"), last_slide?(slide_number))
      end

      def navi(file_name_format, slide_number)
        result = ''
        result << '<div class="navi">'
        result << first_link(file_name_format, slide_number)
        result << previous_link(file_name_format, slide_number)
        result << next_link(file_name_format, slide_number)
        result << last_link(file_name_format, slide_number)
        result << '</div>'
        result
      end

      def image_title(slide_number)
        title = h(slide_title)
        title << "(#{slide_number}/#{@canvas.slide_size})"
        title
      end

      def image_src(file_name_format, slide_number, image_type)
        name = make_file_name(file_name_format, slide_number, image_type)
        File.basename(name)
      end

      def slide_title
        Utils.unescape_title(@canvas.slide_title)
      end

      def make_rss(base_uri)
        base_uri = base_uri.chomp('/') + '/'
        RSS::Maker.make('1.0') do |maker|
          now = Time.now
          title_slide_info = @rss_info.first
          filename, title, html = title_slide_info
          maker.channel.about = "#{base_uri}index.rdf"
          maker.channel.title = title
          maker.channel.description = html
          maker.channel.link = base_uri
          maker.channel.date = now
          
          @rss_info.each_with_index do |info, i|
            filename, title, html = info
            item = maker.items.new_item
            item.link = "#{base_uri}#{File.basename(filename)}"
            item.title = title
            item.description = html
            File.open(filename) do |f|
              content = f.read
              content.gsub!(/(href|src)="([^\":]+)"/) do
                %Q|#{$1}="#{base_uri}#{$2}"|
              end
              content.gsub!(/\A.*(<style.*<\/style>).*<body>/m, '\\1')
              content.gsub!(/<\/body>.*\z/m, '')
              item.content_encoded = content
            end
            item.date = now - i
          end
        end
      end
    end
  end
end
