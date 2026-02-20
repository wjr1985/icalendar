# frozen_string_literal: true

module Icalendar
  module Values
    class Text < Value
      UNESCAPE_REGEX = /\\[\\,;nN]/.freeze
      UNESCAPE_MAP = { "\\\\" => "\\", "\\," => ",", "\\;" => ";", "\\n" => "\n", "\\N" => "\n" }.freeze

      ESCAPE_REGEX = /[\\;,\r\n]/.freeze
      ESCAPE_MAP = { "\\" => "\\\\", ";" => "\\;", "," => "\\,", "\r" => "", "\n" => "\\n" }.freeze

      def initialize(value, *args)
        super value.gsub(UNESCAPE_REGEX, UNESCAPE_MAP), *args
      end

      def value_ical
        value.gsub(ESCAPE_REGEX, ESCAPE_MAP)
      end
    end
  end
end
