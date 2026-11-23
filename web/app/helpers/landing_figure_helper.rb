# Fig. 1 on the landing page: two real trends from the backtest, drawn from
# db/landing_figure.json (exported from backtest/parity_fixture.json), so the page
# needs no API calls. Each panel shows 8 weeks before the surge to a year after:
# the six weeks the model reads, and the line the outcome is judged against
# (weeks 26-51 must average at least 25% of the early peak).
module LandingFigureHelper
  W = 520
  H = 190
  PAD = 8

  def landing_trends
    @landing_trends ||= JSON.parse(Rails.root.join("db", "landing_figure.json").read).fetch("trends")
  end

  def landing_figure_svg(trend)
    values = trend["values"]
    onset = trend["onset_offset"]
    max = values.max.to_f
    x = ->(i) { (PAD + i * (W - 2 * PAD) / (values.size - 1.0)).round(1) }
    y = ->(v) { (H - PAD - v / max * (H - 2 * PAD)).round(1) }
    points = values.each_with_index.map { |v, i| "#{x.(i)},#{y.(v)}" }.join(" ")
    threshold = y.(Hindsight::SUSTAIN_RATIO * trend["peak"])

    tag.svg(viewBox: "0 0 #{W} #{H}", class: "fig-svg", role: "img",
            "aria-label": "#{trend['name']}: weekly Wikipedia views from 8 weeks before the surge to a year after") do
      safe_join([
        tag.rect(x: x.(onset), y: 0, width: x.(onset + TrendMath::EARLY_WEEKS) - x.(onset), height: H, class: "fig-window"),
        tag.line(x1: x.(onset), x2: x.(onset), y1: 0, y2: H, class: "fig-onset"),
        tag.line(x1: x.(onset + Hindsight::PEAK_WEEKS), x2: x.(onset + Hindsight::LATE_END - 1),
                 y1: threshold, y2: threshold, class: "fig-threshold"),
        tag.polyline(points: points, class: "fig-line")
      ])
    end
  end

  def landing_call(trend)
    p = trend["probability_sustained"]
    p >= 0.5 ? ["Likely sustained", p, "success"] : ["Likely spike", 1 - p, "warning"]
  end
end
