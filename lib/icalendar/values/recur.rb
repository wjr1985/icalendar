# frozen_string_literal: true

module Icalendar
  module Values

    class Recur < Value
      RecurFields = Struct.new(:frequency, :until, :count, :interval,
                               :by_second, :by_minute, :by_hour, :by_day,
                               :by_month_day, :by_year_day, :by_week_number,
                               :by_month, :by_set_position, :week_start,
                               keyword_init: true)

      def initialize(value, *args)
        if value.is_a? Icalendar::Values::Recur
          super value.value, *args
        else
          super RecurFields.new(**parse_fields(value)), *args
        end
      end

      def valid?
        return false if frequency.nil?
        return false if !self.until.nil? && !count.nil?
        true
      end

      def value_ical
        builder = ["FREQ=#{frequency}"]
        builder << "UNTIL=#{self.until}" unless self.until.nil?
        builder << "COUNT=#{count}" unless count.nil?
        builder << "INTERVAL=#{interval}" unless interval.nil?
        builder << "BYSECOND=#{by_second.join ','}" unless by_second.nil?
        builder << "BYMINUTE=#{by_minute.join ','}" unless by_minute.nil?
        builder << "BYHOUR=#{by_hour.join ','}" unless by_hour.nil?
        builder << "BYDAY=#{by_day.join ','}" unless by_day.nil?
        builder << "BYMONTHDAY=#{by_month_day.join ','}" unless by_month_day.nil?
        builder << "BYYEARDAY=#{by_year_day.join ','}" unless by_year_day.nil?
        builder << "BYWEEKNO=#{by_week_number.join ','}" unless by_week_number.nil?
        builder << "BYMONTH=#{by_month.join ','}" unless by_month.nil?
        builder << "BYSETPOS=#{by_set_position.join ','}" unless by_set_position.nil?
        builder << "WKST=#{week_start}" unless week_start.nil?
        builder.join ';'
      end

      private

      def parse_fields(value)
        parts = {}
        value.split(';').each do |segment|
          key, val = segment.split('=', 2)
          parts[key.upcase] = val if key && val
        end

        {
          frequency:       parts['FREQ']&.upcase,
          until:           parts['UNTIL'],
          count:           parts['COUNT']&.to_i,
          interval:        parts['INTERVAL']&.to_i,
          by_second:       parts['BYSECOND']&.split(',')&.map(&:to_i),
          by_minute:       parts['BYMINUTE']&.split(',')&.map(&:to_i),
          by_hour:         parts['BYHOUR']&.split(',')&.map(&:to_i),
          by_day:          parts['BYDAY']&.split(','),
          by_month_day:    parts['BYMONTHDAY']&.split(','),
          by_year_day:     parts['BYYEARDAY']&.split(','),
          by_week_number:  parts['BYWEEKNO']&.split(','),
          by_month:        parts['BYMONTH']&.split(',')&.map(&:to_i),
          by_set_position: parts['BYSETPOS']&.split(','),
          week_start:      parts['WKST']&.upcase
        }
      end
    end
  end
end
