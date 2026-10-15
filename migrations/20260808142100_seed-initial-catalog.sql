-- Initial product catalog requested by the Owner. Conversion factors default
-- to 1 pcs/jar and 1 jar/carton, and no unit prices are set yet — the Owner
-- fills in real prices per product via the Products screen (FR-3.4).
INSERT INTO categories (name) VALUES
  ('Mini Pack Biscuits'),
  ('Economy Pack Biscuits'),
  ('Standard Pack Biscuits'),
  ('Family Pack Biscuits'),
  ('Regular/Large Pack Biscuits'),
  ('Wafers & Chocolate Bars'),
  ('Fresh Funfill Candy')
ON CONFLICT (name) DO NOTHING;

INSERT INTO products (name, category_id, pcs_per_jar, jars_per_carton, low_stock_threshold)
SELECT v.name, c.id, 1, 1, 0
FROM (VALUES
  ('Fresh Funfill Sandwich Cream Biscuit – Pineapple (18 g)', 'Mini Pack Biscuits'),
  ('Fresh Funfill Sandwich Cream Biscuit – Chocolate (18 g)', 'Mini Pack Biscuits'),
  ('Fresh Sugar Crush Sugar-Coated Biscuit (18 g)', 'Mini Pack Biscuits'),
  ('Fresh Energy Power Biscuit (19 g)', 'Mini Pack Biscuits'),
  ('Fresh Sweet ''N'' Salty Biscuit (15 g)', 'Mini Pack Biscuits'),
  ('Fresh Tea Potato Cookies (16 g)', 'Mini Pack Biscuits'),
  ('Fresh Deluxe Digestive Crackers (16.5 g)', 'Mini Pack Biscuits'),

  ('Fresh Funfill Sandwich Cream Biscuit – Pineapple (40 g)', 'Economy Pack Biscuits'),
  ('Fresh Funfill Sandwich Cream Biscuit – Chocolate (38 g)', 'Economy Pack Biscuits'),
  ('Fresh Sugar Crush Sugar-Coated Biscuit (39 g)', 'Economy Pack Biscuits'),
  ('Fresh Energy Power Biscuit (40 g)', 'Economy Pack Biscuits'),
  ('Fresh Orange Biscuit (42 g)', 'Economy Pack Biscuits'),
  ('Fresh Sweet ''N'' Salty Biscuit (37 g)', 'Economy Pack Biscuits'),
  ('Fresh Milk Shakti Biscuit (40 g)', 'Economy Pack Biscuits'),

  ('Fresh Healthy Choice Salted Biscuit (80 g)', 'Standard Pack Biscuits'),
  ('Fresh Super Delicious Cookies (80 g)', 'Standard Pack Biscuits'),
  ('Fresh Coconut Cookies (80 g)', 'Standard Pack Biscuits'),
  ('Fresh Chocolate Biscuit (45 g)', 'Standard Pack Biscuits'),

  ('Fresh Fancy Chocolate Filled Cookies (75 g)', 'Family Pack Biscuits'),
  ('Fresh Fancy Chocolate Filled Cookies (175 g)', 'Family Pack Biscuits'),
  ('Fresh Chocolate Chip Cookies (220 g)', 'Family Pack Biscuits'),
  ('Fresh Super Delicious Cookies (240 g)', 'Family Pack Biscuits'),

  ('Fresh Coconut Cookies (240 g)', 'Regular/Large Pack Biscuits'),
  ('Fresh Tea Potato Cookies (200 g)', 'Regular/Large Pack Biscuits'),
  ('Fresh Butter Cookies (Jar – 600 g)', 'Regular/Large Pack Biscuits'),
  ('Fresh Butter Cookies (Jar – 850 g)', 'Regular/Large Pack Biscuits'),
  ('Fresh Deluxe Digestive Crackers (204 g)', 'Regular/Large Pack Biscuits'),
  ('Fresh Energy Power Biscuit (185 g)', 'Regular/Large Pack Biscuits'),
  ('Fresh Orange Biscuit (155 g)', 'Regular/Large Pack Biscuits'),
  ('Fresh Salted Cookies (180 g)', 'Regular/Large Pack Biscuits'),
  ('Fresh Sugar Crush Sugar-Coated Biscuit (200 g)', 'Regular/Large Pack Biscuits'),
  ('Fresh Special Toast Biscuit (350 g)', 'Regular/Large Pack Biscuits'),

  ('Fresh Energy Wafer – Chocolate Cream (8 g)', 'Wafers & Chocolate Bars'),
  ('Fresh Energy Wafer – Chocolate Cream (10 g)', 'Wafers & Chocolate Bars'),
  ('Fresh Energy Wafer – Chocolate Cream (20 g)', 'Wafers & Chocolate Bars'),
  ('Fresh Moving Wafer – Chocolate Cream (30 g)', 'Wafers & Chocolate Bars'),
  ('Fresh Chocolate Bar (4.8 g)', 'Wafers & Chocolate Bars'),
  ('Fresh Chocolate Bar (12.5 g)', 'Wafers & Chocolate Bars'),
  ('Fresh Crispy Wafer – Milk Cream (12 pcs)', 'Wafers & Chocolate Bars'),
  ('Fresh Crispy Wafer – Milk Cream (20 g)', 'Wafers & Chocolate Bars'),
  ('Fresh Crispy Wafer – Coconut Cream (12 pcs)', 'Wafers & Chocolate Bars'),
  ('Fresh Crispy Wafer – Coconut Cream (20 g)', 'Wafers & Chocolate Bars'),
  ('Fresh Crispy Wafer – Chocolate Cream (12 pcs)', 'Wafers & Chocolate Bars'),
  ('Fresh Crispy Wafer – Chocolate Cream (20 g)', 'Wafers & Chocolate Bars'),
  ('Fresh Crispy Sandwich Wafer (20 g)', 'Wafers & Chocolate Bars'),

  ('Fresh Funfill Candy – Orange (3.5 g)', 'Fresh Funfill Candy'),
  ('Fresh Funfill Candy – Lychee (3.5 g)', 'Fresh Funfill Candy'),
  ('Fresh Funfill Candy – Mixed Flavour (3.5 g)', 'Fresh Funfill Candy')
) AS v(name, category_name)
JOIN categories c ON c.name = v.category_name
ON CONFLICT (name) DO NOTHING;
