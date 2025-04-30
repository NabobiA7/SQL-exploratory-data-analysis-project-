-- Creating Schemas if they do not exist
DROP SCHEMA IF EXISTS customers CASCADE;
DROP SCHEMA IF EXISTS products CASCADE;
DROP SCHEMA IF EXISTS sales CASCADE;

CREATE SCHEMA IF NOT EXISTS gold;
SET search_path TO gold;

CREATE TABLE IF NOT EXISTS gold.dim_customers (
    customer_key INT,
    customer_id INT,
    customer_number VARCHAR(50),		
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    country VARCHAR(50),
    marital_status VARCHAR(50),
    gender VARCHAR(50),
    birthdate DATE,
    create_date DATE
);

-- Create the dim_products table under the 'products' schema
CREATE TABLE IF NOT EXISTS gold.dim_products (
    product_key INT,
    product_id INT,
    product_number VARCHAR(50),
    product_name VARCHAR(50),
    category_id VARCHAR(50),
    category VARCHAR(50),
    subcategory VARCHAR(50),
    maintenance VARCHAR(50),
    cost INT,
    product_line VARCHAR(50),
    start_date DATE
);

-- Create the fact_sales table under the 'sales' schema
CREATE TABLE IF NOT EXISTS gold.fact_sales (
    order_number VARCHAR(50),
    product_key INT,
    customer_key INT,
    order_date DATE,
    shipping_date DATE,
    due_date DATE,
    sales_amount INT,
    quantity SMALLINT,
    price INT
);

COPY gold.dim_customers FROM 'C:\Users\nabob\OneDrive\Desktop\gold.dim_customers.csv'
DELIMITER ',' CSV HEADER;

COPY gold.dim_products FROM 'C:\Users\nabob\OneDrive\Desktop\gold.dim_products.csv'
DELIMITER ',' CSV HEADER;

COPY gold.fact_sales FROM 'C:\Users\nabob\OneDrive\Desktop\gold.fact_sales.csv'
DELIMITER ',' CSV HEADER;

SELECT current_database();

-- Checking the data in each table 
SELECT*FROM gold.dim_customers LIMIT 10;  
SELECT*FROM gold.dim_products  LIMIT 10;  
SELECT*FROM gold.fact_sales LIMIT 10;
---output had visuality restriction so used VACCUM syntax
VACUUM FULL gold.dim_customers;
SELECT 
    EXTRACT(YEAR FROM order_date) AS order_year, 
    SUM(sales_amount) AS total_sales 
FROM gold.fact_sales 
WHERE order_date IS NOT NULL 
GROUP BY EXTRACT(YEAR FROM order_date) 
ORDER BY EXTRACT(YEAR FROM order_date);
----Changes Over Time in sales by comparing year to month
------ Analyse sales performance over time
------ Quick Date Functions

SELECT 
     DATE_PART('year',order_date)AS order_year,
	 DATE_PART('month',order_date)AS order_month,
	 SUM(sales_amount)AS total_sales,
	 COUNT(DISTINCT customer_key)AS total_customer,
	 SUM(quantity)AS total_quantity
FROM gold.fact_sales 
	 WHERE order_date IS NOT NULL
	 GROUP BY DATE_PART('year',order_date),DATE_PART('month',order_date) 
     ORDER BY DATE_PART('year',order_date),DATE_PART('month',order_date); 

SELECT
  DATE_TRUNC('month', order_date)AS order_month,
  COUNT(DISTINCT customer_key)AS total_customer,
  SUM(sales_amount)AS total_sales	
  FROM gold.fact_sales
  WHERE order_date IS NOT NULL
  GROUP BY DATE_TRUNC('month', order_date)
  ORDER BY DATE_TRUNC('month', order_date);

SELECT 
 TO_CHAR(order_date,'YYYY-Mon')AS order_date,
 SUM(sales_amount) AS total_sales,
 COUNT(DISTINCT 'customer_key') AS total_customers,
 SUM(quantity)AS total_quantity
 FROM gold.fact_sales
 WHERE order_date IS NOT NULL
 GROUP BY TO_CHAR(order_date,'YYYY-Mon')
 ORDER BY TO_CHAR(order_date,'YYYY-Mon'); 



----Performance Analysis (Year-over-Year, Month-over-Month)
----Q:Analyze the *yearly* performance of *products* by comparing their *sales* to both the **average sales performance** of the product and the **previous year's sales** 

WITH yearly_product_sales AS (
    SELECT
        EXTRACT(YEAR FROM f.order_date) AS order_year,
        p.product_name,
        SUM(f.sales_amount) AS current_sales
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p
        ON f.product_key = p.product_key
    WHERE f.order_date IS NOT NULL
    GROUP BY EXTRACT(YEAR FROM f.order_date), p.product_name
)
SELECT 
    order_year,
    product_name,
    current_sales,

    -- Compute avg_sales first
    AVG(current_sales) OVER (PARTITION BY product_name) AS avg_sales,
    current_sales - AVG(current_sales) OVER (PARTITION BY product_name) AS diff_avg,

    -- Use avg_sales inside CASE
    CASE 
        WHEN current_sales > AVG(current_sales) OVER (PARTITION BY product_name) THEN 'Above Avg'
        WHEN current_sales < AVG(current_sales) OVER (PARTITION BY product_name) THEN 'Below Avg'
        ELSE 'Avg'
    END AS avg_change,

    -- Computing previous year's sales
    LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS py_sales,           
    current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS diff_py,

    -- Using LAG inside CASE correctly
    CASE
        WHEN current_sales > LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) THEN 'Increase'
        WHEN current_sales < LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) THEN 'Decrease' 
        ELSE 'No Change'
    END AS py_change  

FROM yearly_product_sales
ORDER BY product_name, order_year;

----Which catagory contributing mostly to the overall sales
WITH category_sales AS(
SELECT
p.category, 
SUM(f.sales_amount) AS total_sales 
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p 
ON f.product_key = p.product_key 
GROUP BY p.category
)
	
	SELECT 
	category,
	total_sales,
	SUM(total_sales)OVER()overall_sales,
    ROUND((total_sales::NUMERIC/SUM(total_sales)OVER())*100,2)AS percentage_of_total
	FROM category_sales
	ORDER BY total_sales DESC;

------- Segment products into cost ranges and count how many products fall into each segment
WITH product_segments AS(
SELECT
product_key,
product_name,
cost,
CASE 
 WHEN cost< 100 THEN 'BELOW 100'
 WHEN cost BETWEEN 100 AND 500 THEN '100-500'
 WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
 WHEN cost BETWEEN 100 AND 500 THEN '100-500'
 ELSE 'Above 1000'
 END AS cost_range
FROM gold.dim_products
)
SELECT 
cost_range,
COUNT(product_key)AS total_products
FROM product_segments
GROUP BY cost_range
ORDER BY total_products DESC;

----- Group customers into VIP, Regular, and New based on spending and customer history
---/*Group customers into three segments based on their spending behavior----------------------------
----VIP: Customers with at least 12 months of history and spending more than â‚¬5,000.
----Regular: Customers with at least 12 months of history but spending â‚¬5,000 or less.
----New: Customers with a lifespan less than 12 months.
----And find the total number of customers by each group

----------------------------------------------------------------------------------------------------

WITH unique_customers AS (
    SELECT DISTINCT customer_key
    FROM gold.dim_customers
),
customer_spending AS (
    SELECT
        c.customer_key,
        COALESCE(SUM(DISTINCT f.sales_amount), 0) AS total_spending,
        MIN(f.order_date) AS first_order,
        MAX(f.order_date) AS last_order,
        COALESCE(
            (DATE_PART('year', MAX(f.order_date)) - DATE_PART('year', MIN(f.order_date))) * 12 +
            (DATE_PART('month', MAX(f.order_date)) - DATE_PART('month', MIN(f.order_date))),0
    ) AS lifespan
    FROM gold.dim_customers c
    LEFT JOIN gold.fact_sales f ON c.customer_key = f.customer_key
    GROUP BY c.customer_key
)

SELECT 
    customer_segment,
    COUNT(customer_key) AS total_customers
FROM (
    SELECT 
        customer_key,
        CASE 
            WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
            WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'Regular'
            ELSE 'New'
        END AS customer_segment
    FROM customer_spending
) AS segmented_customers
GROUP BY customer_segment
ORDER BY total_customers DESC;


-- =============================================================================
-- Create Report: gold.report_customers
 ---Highlights:
    /*1. Gather essential fields such as names, ages, and transaction details.
	2. Segment customers into categories (VIP, Regular, New) and age groups.
    3. Aggregate customer-level metrics:
	   - total orders
	   - total sales
	   - total quantity purchased
	   - total products
	   - lifespan (in months)
    4. Calculate valuable KPIs:
	    - recency (months since last order)
		- average order value
		- average monthly spend
---------------------------------------------------------------------------*/
WITH base_query AS (
   ----1)Base Query: Retrieves core columns from tables--
    SELECT
        f.order_number,
        f.product_key,
        f.order_date,
        f.sales_amount,
        f.quantity,
        c.customer_key,
        c.customer_number,
        CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
        EXTRACT(YEAR FROM AGE(c.birthdate)) AS age
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_customers c ON c.customer_key = f.customer_key
    WHERE f.order_date IS NOT NULL
),

customer_aggregation AS (
    /*---------------------------------------------------------------------------
    2) Customer Aggregations: Summarizes key metrics at the customer level
    ---------------------------------------------------------------------------*/
    SELECT 
        customer_key,
        customer_number,
        customer_name,
        age,
        COUNT(DISTINCT order_number) AS total_orders,
        SUM(sales_amount) AS total_sales,
        SUM(quantity) AS total_quantity,
        COUNT(DISTINCT product_key) AS total_products,
        MAX(order_date) AS last_order_date,
        EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date))) * 12 + 
        EXTRACT(MONTH FROM AGE(MAX(order_date), MIN(order_date))) AS lifespan
    FROM base_query
    GROUP BY 
        customer_key,
        customer_number,
        customer_name,
        age
)

SELECT
    customer_key,
    customer_number,
    customer_name,
    age,
    CASE 
        WHEN age < 20 THEN 'Under 20'
        WHEN age BETWEEN 20 AND 29 THEN '20-29'
        WHEN age BETWEEN 30 AND 39 THEN '30-39'
        WHEN age BETWEEN 40 AND 49 THEN '40-49'
        ELSE '50 and above'
    END AS age_group,
    CASE 
        WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
        WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
        ELSE 'New'
    END AS customer_segment,
    last_order_date,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, last_order_date)) * 12 + 
    EXTRACT(MONTH FROM AGE(CURRENT_DATE, last_order_date)) AS recency,
    total_orders,
    total_sales,
    total_quantity,
    total_products,
    lifespan,
    -- deriving average order value (AVO)
    CASE WHEN total_orders = 0 THEN 0
         ELSE total_sales / total_orders
    END AS avg_order_value,
    -- deriving average monthly spend
    CASE WHEN lifespan = 0 THEN total_sales
         ELSE total_sales / lifespan
    END AS avg_monthly_spend
FROM customer_aggregation;



/*
===============================================================================
Product Report
    - This report will consolidate key product metrics and behaviors.

Highlights:
    1. Gathers essential fields such as product name, category, subcategory, and cost.
    2. Segments products by revenue to identify High-Performers, Mid-Range, or Low-Performers.
    3. Aggregates product-level metrics:
       - total orders
       - total sales
       - total quantity sold
       - total customers (unique)
       - lifespan (in months)
    4. Calculates valuable KPIs:
       - recency (months since last sale)
       - average order revenue (AOR)
       - average monthly revenue
===============================================================================
*/

WITH base_query AS (
    SELECT
        f.order_number,
        f.order_date,
        f.customer_key,
        f.sales_amount,
        f.quantity,
        p.product_key,
        p.product_name,
        p.category,
        p.subcategory,
        p.cost
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p
        ON f.product_key = p.product_key
    WHERE f.order_date IS NOT NULL  
),

product_aggregations AS (

SELECT
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date))) * 12 + 
    EXTRACT(MONTH FROM AGE(MAX(order_date), MIN(order_date))) AS lifespan,
    MAX(order_date) AS last_sale_date,
    COUNT(DISTINCT order_number) AS total_orders,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS total_quantity,
CASE 
    WHEN SUM(quantity) = 0 THEN 0
    ELSE ROUND(SUM(sales_amount) / SUM(quantity), 1)
END AS avg_selling_price

FROM base_query
GROUP BY
    product_key,
    product_name,
    category,
    subcategory,
    cost
)

 ------3) Final Query: Combining all product results into one output
SELECT 
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    last_sale_date,
    EXTRACT(YEAR FROM AGE(last_sale_date)) * 12 + 
    EXTRACT(MONTH FROM AGE(last_sale_date)) AS recency_in_months,
    CASE
        WHEN total_sales > 50000 THEN 'High-Performer'
        WHEN total_sales >= 10000 THEN 'Mid-Range'
        ELSE 'Low-Performer'
    END AS product_segment,
    lifespan,
    total_orders,
    total_sales,
    total_quantity,
    total_customers,
    avg_selling_price,
    -- Average Order Revenue (AOR)
    CASE 
        WHEN total_orders = 0 THEN 0
        ELSE total_sales / total_orders
    END AS avg_order_revenue,

    -- Average Monthly Revenue
    CASE
        WHEN lifespan = 0 THEN total_sales
        ELSE total_sales / lifespan
    END AS avg_monthly_revenue

FROM product_aggregations;
