# Default mapping overrides for the demo dev store (stockout-tracker).
#
# Why seeds: on Render's free plan the SQLite database is recreated on every boot,
# so overrides saved through the UI disappear. `db:prepare` runs this file whenever
# it creates the database, so these come back every time.
#
# Keys are the search terms the app derives (see ProductMapper): the productType
# if it's specific, otherwise the title. Article titles are canonical (checked
# against Wikipedia's API, no redirects). Existing overrides are never changed,
# so a merchant's own fix always wins. Run by hand with: bin/rails db:seed
default_overrides = {
  # Auto-search found nothing.
  "crocs jibbitz charm pack"     => "Crocs",                     # "Jibbitz" redirects to Crocs
  "jellycat bashful bunny"       => "Jellycat",
  "pokemon tcg booster box"      => "Pokémon Trading Card Game",
  "ninja creami ice cream maker" => "SharkNinja",                # no Creami article; brand-level interest
  "the minimal snowboard"        => "Snowboard",                 # group with the other sample snowboards
  # Auto-search picked the parent company; Owala has its own article.
  "owala freesip water bottle"   => "Owala",
  # Not trend products.
  "giftcard"                     => nil,
  "accessories"                  => nil                          # Shopify's sample ski wax
}

default_overrides.each do |term, article|
  MappingOverride.find_or_create_by!(term_key: term) do |override|
    override.article = article
    override.ignored = article.nil?
  end
end
