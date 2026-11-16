require "test_helper"

class WikidataClientTest < ActiveSupport::TestCase
  # Answers the client's two SPARQL queries from a tiny made-up graph, so the
  # real walking and classification code runs with no network.
  class GraphWikidata < WikidataClient
    TYPES = { # item => direct types ("instance of" / "subclass of")
      "Q1" => ["Q100"],          # fidget spinner -> spinning toy
      "Q2" => ["Q5"],            # a person
      "Q3" => ["Q300"],          # chatbot -> software, but also a "product"
      "Q4" => ["Q400"],          # matcha -> powdered tea (drink) and medication
      "Q5x" => ["Q500"],         # deep chain, beyond MAX_DEPTH
      "Q6" => ["Q11422", "Q196600"] # a toy line that's also a media franchise
    }.freeze
    PARENTS = {
      "Q100" => ["Q11422"], "Q5" => ["Q215627"], "Q215627" => [],
      "Q300" => ["Q7397", "Q431289"], "Q400" => ["Q40050", "Q12140"],
      "Q500" => ["Q501"], **(501..520).to_h { |i| ["Q#{i}", ["Q#{i + 1}"]] }, "Q521" => ["Q11422"]
    }.freeze

    attr_reader :queries

    def initialize
      super
      @parents = {} # no shipped catalog: everything goes through "SPARQL"
      @queries = 0
    end

    private

    def sparql(query)
      @queries += 1
      ids = query[/VALUES \?(?:item|type) \{([^}]*)\}/, 1].scan(/wd:(Q\w+)/).flatten
      if query.include?("wdt:P31")
        ids.flat_map { |i| TYPES.fetch(i, []).map { |t| row("item" => i, "type" => t) } }
      else
        ids.flat_map { |i| PARENTS.fetch(i, []).map { |p| row("type" => i, "parent" => p) } }
      end
    end

    def row(vars) = vars.transform_values { |q| { "value" => "http://www.wikidata.org/entity/#{q}" } }
  end

  test "keeps products, drops people, software and franchises" do
    kinds = GraphWikidata.new.product_kinds(%w[Q1 Q2 Q3 Q4 Q6])
    assert_equal({ "Q1" => ["toy"], "Q4" => ["drink"] }, kinds)
  end

  test "stops climbing after MAX_DEPTH levels" do
    assert_empty GraphWikidata.new.product_kinds(["Q5x"]), "toy is 22 levels up: too far to count"
  end

  test "parents are cached in memory: a second lookup makes no queries" do
    client = GraphWikidata.new
    client.product_kinds(%w[Q1 Q4])
    before = client.queries
    client.product_kinds(%w[Q4])
    assert_equal before + 1, client.queries, "only the direct-types query runs again"
  end

  test "the classification rule" do
    assert_equal %w[toy brand], WikidataClient.kinds_from(%w[brand toy])
    assert_empty WikidataClient.kinds_from(["brand", "software"])
    assert_empty WikidataClient.kinds_from(["food", "film"])
    assert_empty WikidataClient.kinds_from(["medication"])
    assert_equal ["drink"], WikidataClient.kinds_from(%w[drink medication])
  end

  test "the shipped catalog is a type -> parents graph" do
    skip "no catalog yet" unless WikidataClient::CATALOG_PATH.exist?
    catalog = WikidataClient.catalog
    assert catalog.size > 100
    assert(catalog.all? { |type, parents| type.match?(/\AQ\d+\z/) && parents.is_a?(Array) })
  end
end
