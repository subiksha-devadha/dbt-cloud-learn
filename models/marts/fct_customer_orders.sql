WITH 
-- Import CTEs
customers AS (
  SELECT * FROM {{ source('jaffle_shop', 'raw_customers') }}
),
orders AS (
  SELECT * FROM {{ source('jaffle_shop', 'raw_orders') }}
),
payments AS (
  SELECT * FROM {{ source('stripe', 'raw_payments') }}
),

-- Logical CTEs
completed_payments AS (
  SELECT 
    orderid AS order_id,
    MAX(created) AS payment_finalized_date,
    SUM(amount) / 100.0 AS total_amount_paid
  FROM payments
  WHERE status <> 'fail'
  GROUP BY 1
),

paid_orders AS (
  SELECT 
    orders.id AS order_id,
    orders.user_id AS customer_id,
    orders.order_date AS order_placed_at,
    orders.status AS order_status,
    p.total_amount_paid,
    p.payment_finalized_date,
    c.first_name AS customer_first_name,
    c.last_name AS customer_last_name
  FROM orders
  LEFT JOIN completed_payments AS p ON orders.id = p.order_id
  LEFT JOIN customers AS c ON orders.user_id = c.id
),

customer_orders AS (
  SELECT 
    c.id AS customer_id,
    MIN(o.order_date) AS first_order_date,
    MAX(o.order_date) AS most_recent_order_date,
    COUNT(o.id) AS number_of_orders
  FROM customers AS c
  LEFT JOIN orders AS o ON o.user_id = c.id 
  GROUP BY c.id
),

-- final CTE 
final AS (
  SELECT
    p.*,
    ROW_NUMBER() OVER (ORDER BY p.order_id) AS transaction_seq,
    ROW_NUMBER() OVER (PARTITION BY p.customer_id ORDER BY p.order_id) AS customer_sales_seq,
    CASE 
      WHEN (
        RANK() OVER (
          PARTITION BY p.customer_id
          ORDER BY p.order_placed_at, p.order_id
        ) = 1
      ) THEN 'new'
      ELSE 'return'
    END AS nvsr,
    x.clv_bad AS customer_lifetime_value,
    FIRST_VALUE(p.order_placed_at) OVER (
      PARTITION BY p.customer_id
      ORDER BY p.order_placed_at
    ) AS fdos
  FROM paid_orders p
  LEFT JOIN customer_orders c USING (customer_id)
  LEFT JOIN (
    SELECT
      p.order_id,
      SUM(t2.total_amount_paid) AS clv_bad
    FROM paid_orders p
    LEFT JOIN paid_orders t2 ON p.customer_id = t2.customer_id AND p.order_id >= t2.order_id
    GROUP BY p.order_id
    ORDER BY p.order_id
  ) x ON x.order_id = p.order_id
  ORDER BY p.order_id
)

-- Simple Select Statement
SELECT * FROM final
