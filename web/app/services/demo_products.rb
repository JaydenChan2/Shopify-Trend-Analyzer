# Sample products used when Shopify credentials aren't set, so the app runs immediately.
# Same shape as ShopifyClient#products returns.
module DemoProducts
  ALL = [
    { id: "demo-1", title: "5.8qt Basket Air Fryer",            product_type: "Air fryer",       tags: %w[kitchen] },
    { id: "demo-2", title: "Labubu Blind Box – Macaron Series", product_type: "Labubu",          tags: %w[collectible] },
    { id: "demo-3", title: "Ceremonial Grade Matcha 30g",       product_type: "Matcha",          tags: %w[tea] },
    { id: "demo-4", title: "Pro Pickleball Paddle Set",         product_type: "Pickleball",      tags: %w[sports] },
    { id: "demo-5", title: "Classic Fidget Spinner",            product_type: "Fidget spinner",  tags: %w[toys] },
    { id: "demo-6", title: "Pistachio Dubai Chocolate Bar",     product_type: "Dubai chocolate", tags: %w[snacks] },
    { id: "demo-7", title: "Weighted Blanket 15lb",             product_type: "",                tags: %w[home] }, # no type: title fallback
    { id: "demo-8", title: "Organic Cotton Tee",                product_type: "T-shirt",         tags: %w[apparel] }
  ].freeze
end
