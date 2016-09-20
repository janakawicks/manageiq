module LiveMetricsMixin
  extend ActiveSupport::Concern

  LIVE_METRICS_DIR = Rails.root.join("product/live_metrics")

  class MetricValidationError < RuntimeError; end

  delegate :fetch_metrics_available, :to => :metrics_capture
  delegate :collect_live_metric, :to => :metrics_capture
  delegate :collect_stats_metric, :to => :metrics_capture

  included do
    def live_metrics_name
      self.class.name.demodulize.underscore
    end

    def chart_report_name
      self.class.name.demodulize.underscore
    end

    def collect_live_metrics(metrics, start_time, end_time, interval)
      processed = Hash.new { |h, k| h[k] = {} }
      metrics.each do |metric|
        values = collect_live_metric(metric, start_time, end_time, interval)
        processed.merge!(values) { |_k, old, new| old.merge(new) }
      end
      processed
    end

    def metrics_available
      @metrics_available ||= fetch_metrics_available
    end

    def first_and_last_capture(interval_name = "realtime")
      firsts, lasts = metrics_available.collect do |metric|
        metrics_capture.first_and_last_capture(metric)
      end.transpose
      adjust_timestamps(firsts, lasts, interval_name)
    rescue => e
      _log.error("LiveMetrics unavailable for #{self.class.name} id: #{id}. #{e.message}")
      return [nil, nil]
    end

    def adjust_timestamps(firsts, lasts, interval_name)
      first = Time.at(firsts.min / 1000).utc
      last = Time.at(lasts.max / 1000).utc
      now = Time.new.utc
      if interval_name == "hourly"
        first = (now - first) > 1.hour ? first : nil
      end
      [first, last]
    end

    def included_children
      self.class.live_metrics_config ||= {}
      self.class.live_metrics_config[live_metrics_name] ||= load_live_metrics_config
      self.class.live_metrics_config[live_metrics_name]['included_children']
    end

    def supported_metrics
      self.class.live_metrics_config ||= {}
      self.class.live_metrics_config[live_metrics_name] ||= load_live_metrics_config
      self.class.live_metrics_config[live_metrics_name]['supported_metrics']
    end

    def supported_metrics_by_column
      self.class.supported_metrics_by_column ||= {}
      self.class.supported_metrics_by_column[live_metrics_name] ||= supported_metrics.invert
    end

    def load_live_metrics_config
      live_metrics_file = File.join(LIVE_METRICS_DIR, "#{live_metrics_name}.yaml")
      live_metrics_config = File.exist?(live_metrics_file) ? YAML.load_file(live_metrics_file) : {}
      if live_metrics_config['supported_metrics']
        live_metrics_config['supported_metrics'] = live_metrics_config['supported_metrics'].reduce({}, :merge)
      end
      live_metrics_config
    end
  end

  module ClassMethods
    attr_accessor :live_metrics_config
    attr_accessor :supported_metrics_by_column
  end
end