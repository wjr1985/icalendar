# frozen_string_literal: true

require 'icalendar/timezone_store'
require 'stringio'
require 'strscan'

module Icalendar

  class Parser
    attr_writer :component_class
    attr_reader :source, :strict, :timezone_store, :verbose

    CLEAN_BAD_WRAPPING_GSUB_REGEX = /\r?\n[ \t]/.freeze

    def self.clean_bad_wrapping(source)
      content = if source.respond_to? :read
        source.read
      elsif source.respond_to? :to_s
        source.to_s
      else
        msg = 'Icalendar::Parser.clean_bad_wrapping must be called with a String or IO object'
        Icalendar.fatal msg
        fail ArgumentError, msg
      end
      encoding = content.encoding
      content.force_encoding(Encoding::ASCII_8BIT)
      content.gsub(CLEAN_BAD_WRAPPING_GSUB_REGEX, "").force_encoding(encoding)
    end

    def initialize(source, strict = false, verbose = false)
      if source.respond_to? :gets
        @source = source
      elsif source.respond_to? :to_s
        @source = StringIO.new source.to_s, 'r'
      else
        msg = 'Icalendar::Parser.new must be called with a String or IO object'
        Icalendar.fatal msg
        fail ArgumentError, msg
      end
      read_in_data
      @strict = strict
      @verbose = verbose
      @timezone_store = TimezoneStore.new
    end

    def parse
      components = []
      while (fields = next_fields)
        component = component_class.new
        if fields[:name] == 'begin' && fields[:value].downcase == component.ical_name.downcase
          components << parse_component(component)
        end
      end
      components
    end

    def parse_property(component, fields = nil)
      fields = next_fields if fields.nil?
      prop_name = %w(class method name).include?(fields[:name]) ? "ip_#{fields[:name]}" : fields[:name]
      multi_property = component.class.multiple_properties.include? prop_name
      prop_value = wrap_property_value component, fields, multi_property
      begin
        method_name = if multi_property
          "append_#{prop_name}"
        else
          "#{prop_name}="
        end
        component.send method_name, prop_value
      rescue NoMethodError => nme
        if strict?
          Icalendar.logger.error "No method \"#{method_name}\" for component #{component}"
          raise nme
        else
          Icalendar.logger.warn "No method \"#{method_name}\" for component #{component}. Appending to custom." if verbose?
          component.append_custom_property prop_name, prop_value
        end
      end
    end

    WRAP_PROPERTY_VALUE_DELIMETER_REGEX = /(?<!\\)([,;])/.freeze
    WRAP_PROPERTY_VALUE_SPLIT_REGEX = /(?<!\\)[;,]/.freeze


    def wrap_property_value(component, fields, multi_property)
      klass = get_wrapper_class component, fields
      if wrap_in_array? klass, fields[:value], multi_property
        delimiter = fields[:value].match(WRAP_PROPERTY_VALUE_DELIMETER_REGEX)[1]
        Icalendar::Values::Helpers::Array.new fields[:value].split(WRAP_PROPERTY_VALUE_SPLIT_REGEX),
                                     klass,
                                     fields[:params],
                                     delimiter: delimiter,
                                     timezone_store: timezone_store
      else
        klass.new fields[:value], fields[:params], timezone_store: timezone_store
      end
    rescue Icalendar::Values::DateTime::FormatError => fe
      raise fe if strict?
      fields[:params]['value'] = ['DATE']
      retry
    end

    WRAP_IN_ARRAY_REGEX_1 = /(?<!\\)[,;]/.freeze
    WRAP_IN_ARRAY_REGEX_2 = /(?<!\\);/.freeze

    def wrap_in_array?(klass, value, multi_property)
      klass.value_type != 'RECUR' &&
        ((multi_property && value =~ WRAP_IN_ARRAY_REGEX_1) || value =~ WRAP_IN_ARRAY_REGEX_2)
    end

    GET_WRAPPER_CLASS_GSUB_REGEX = /(?:\A|-|\s+)(.)/.freeze

    def get_wrapper_class(component, fields)
      klass = component.class.default_property_types[fields[:name]]
      if !fields[:params]['value'].nil?
        klass_name = fields[:params].delete('value').first
        unless klass_name.upcase == klass.value_type
          klass_name = "Icalendar::Values::#{klass_name.downcase.gsub(GET_WRAPPER_CLASS_GSUB_REGEX) { |m| m[-1].upcase }}"
          begin
            klass = Object.const_get klass_name if Object.const_defined?(klass_name)
          rescue NameError => e
            Icalendar.logger.error "NameError trying to find value type for #{component.name} | #{fields[:name]}: #{e.message}"
            raise e if strict?
          end
        end
      end
      klass
    end

    def strict?
      !!@strict
    end

    def verbose?
      @verbose
    end

    private

    def component_class
      @component_class ||= Icalendar::Calendar
    end

    PARSE_COMPONENT_KLASS_NAME_GSUB_REGEX = /\AV/.freeze

    def parse_component(component)
      while (fields = next_fields)
        if fields[:name] == 'end'
          klass_name = fields[:value].gsub(PARSE_COMPONENT_KLASS_NAME_GSUB_REGEX, '').downcase.capitalize
          timezone_store.store(component) if klass_name == 'Timezone'
          break
        elsif fields[:name] == 'begin'
          klass_name = fields[:value].gsub(PARSE_COMPONENT_KLASS_NAME_GSUB_REGEX, '').gsub("-", "_").downcase.capitalize
          Icalendar.logger.debug "Adding component #{klass_name}"
          if Object.const_defined? "Icalendar::#{klass_name}"
            component.add_component parse_component(Object.const_get("Icalendar::#{klass_name}").new)
          elsif Object.const_defined? "Icalendar::Timezone::#{klass_name}"
            component.add_component parse_component(Object.const_get("Icalendar::Timezone::#{klass_name}").new)
          else
            component.add_custom_component klass_name, parse_component(Component.new klass_name.downcase, fields[:value])
          end
        else
          parse_property component, fields
        end
      end
      component
    end

    def read_in_data
      @data = source.gets and @data.chomp!
    end

    NEXT_FIELDS_TAB_REGEX = /\A[ \t].+\z/.freeze
    NEXT_FIELDS_WHITESPACE_REGEX = /\A\s*\z/.freeze

    def next_fields
      line = @data or return nil
      loop do
        read_in_data
        if @data =~ NEXT_FIELDS_TAB_REGEX
          line << @data[1, @data.size]
        elsif @data !~ NEXT_FIELDS_WHITESPACE_REGEX
          break
        end
      end
      parse_fields line
    end

    SCANNER_NAME_REGEX = /[-a-zA-Z0-9]+/.freeze
    SCANNER_QUOTED_REGEX = /"[^"]*"/.freeze
    SCANNER_PARAMTEXT_REGEX = /[^";:,]*/.freeze
    SCANNER_SEMICOLON_REGEX = /;/.freeze
    SCANNER_EQUALS_REGEX = /=/.freeze
    SCANNER_COMMA_REGEX = /,/.freeze
    SCANNER_COLON_REGEX = /:/.freeze

    def parse_fields(input)
      s = StringScanner.new(input)

      # 1. Property name: iana-token / x-name
      raw_name = s.scan(SCANNER_NAME_REGEX) or
        fail(ParseError, "Invalid iCalendar input line: #{input}")

      # 2. Parameters: ;name=value(,value)*
      params = {}
      loop do
        pos = s.pos
        break unless s.skip(SCANNER_SEMICOLON_REGEX)
        pn = s.scan(SCANNER_NAME_REGEX)
        unless pn && s.skip(SCANNER_EQUALS_REGEX)
          s.pos = pos
          break
        end
        values = (params[pn.downcase] ||= [])
        loop do
          if s.peek(1) == '"'
            qs = s.scan(SCANNER_QUOTED_REGEX)
            values << qs[1..-2] if qs
          else
            pt = s.scan(SCANNER_PARAMTEXT_REGEX)
            values << pt if pt && !pt.empty?
          end
          break unless s.skip(SCANNER_COMMA_REGEX)
        end
      end

      # 3. Colon + value
      if s.skip(SCANNER_COLON_REGEX)
        value = s.rest
      else
        fail(ParseError, "Invalid iCalendar input line: #{input}") if strict?
        value = ''
      end

      params = Icalendar::DowncasedHash.new(params) unless params.empty?

      if ::Logger::DEBUG >= Icalendar.logger.level
        Icalendar.logger.debug "Found fields: #{input.inspect} with params: #{params.inspect}"
      end

      { name: cached_property_name(raw_name), params: params, value: value }
    end

    def cached_property_name(raw_name)
      @property_name_cache ||= {}
      @property_name_cache[raw_name] ||= raw_name.downcase.tr('-', '_').freeze
    end

    class ParseError < RuntimeError
    end
  end
end
