CREATE TABLE IF NOT EXISTS products (
 id INTEGER PRIMARY KEY,
 name TEXT NOT NULL CHECK(length(trim(name)) > 0),
 kind TEXT NOT NULL CHECK(length(trim(kind)) > 0),
 code TEXT NOT NULL UNIQUE CHECK(length(trim(code)) > 0),
 price_kopecks INTEGER NOT NULL CHECK(price_kopecks >= 0),
 quantity INTEGER NOT NULL CHECK(quantity >= 0),
 expiry_date TEXT NOT NULL
);
CREATE VIEW IF NOT EXISTS products_view AS
 SELECT *, CASE WHEN expiry_date < date('now','localtime')
 THEN 'истек' ELSE '' END AS PRIM FROM products;
