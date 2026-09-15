"""
etl.py — Clean raw e-commerce exports and load them into a star-schema
SQLite warehouse (ecommerce.db) defined in schema.sql.

Source files (raw, untouched):
    messy_data.csv  — 12,180 raw order rows, deliberately inconsistent
    ad_spend.csv    — daily ad spend by category

Run:
    python3 etl.py
"""

import sqlite3
import pandas as pd

RAW_ORDERS = "messy_data.csv"
RAW_AD_SPEND = "ad_spend.csv"
DB_PATH = "ecommerce.db"
SCHEMA_PATH = "schema.sql"

# ------------------------------------------------------------------
# Lookup tables for standardizing free-text fields
# ------------------------------------------------------------------

PAYMENT_METHOD_MAP = {
    "net banking": "Net Banking", "netbanking": "Net Banking",
    "debit card": "Debit Card",
    "cash on delivery": "Cash on Delivery", "cod": "Cash on Delivery",
    "credit_card": "Credit Card", "credit card": "Credit Card",
    "upi": "UPI", "u.p.i": "UPI",
    "pay pal": "PayPal", "paypal": "PayPal",
}

COUNTRY_MAP = {
    "uk": "United Kingdom", "u.k.": "United Kingdom", "united kingdom": "United Kingdom",
    "ca": "Canada", "canada": "Canada",
    "au": "Australia", "australia": "Australia",
    "usa": "United States", "u.s.a": "United States", "us": "United States",
    "united states": "United States",
    "de": "Germany", "germany": "Germany",
    "in": "India", "india": "India",
    "uae": "United Arab Emirates", "u.a.e": "United Arab Emirates",
}

DATE_FORMATS = ["%Y-%m-%d", "%Y/%m/%d", "%m-%d-%Y", "%d/%m/%Y", "%d %b %Y"]


def parse_mixed_dates(series: pd.Series) -> pd.Series:
    """The source system exported dates in five different formats.
    Try each format in turn and keep whichever one succeeds per row."""
    parsed = pd.Series(pd.NaT, index=series.index)
    for fmt in DATE_FORMATS:
        still_missing = parsed.isna()
        parsed.loc[still_missing] = pd.to_datetime(
            series[still_missing], format=fmt, errors="coerce"
        )
    return parsed


def clean_orders() -> pd.DataFrame:
    df = pd.read_csv(RAW_ORDERS)
    df = df.drop_duplicates()  # 180 exact-duplicate rows in the raw export

    df["Order_Date"] = parse_mixed_dates(df["Order_Date"])
    df["date_id"] = df["Order_Date"].dt.strftime("%Y-%m-%d")

    df["Payment_Method"] = (
        df["Payment_Method"].str.strip().str.lower().map(PAYMENT_METHOD_MAP)
    )
    df["Country"] = df["Country"].str.strip().str.lower().map(COUNTRY_MAP)
    df["Order_Status"] = df["Order_Status"].str.strip().str.title()
    df["Discount_Percent"] = df["Discount_Percent"].fillna(0.0)
    df["Shipping_City"] = df["Shipping_City"].fillna("Unknown")

    df["revenue_usd"] = (
        df["Quantity"] * df["Unit_Price_USD"] * (1 - df["Discount_Percent"] / 100)
    ).round(2)

    return df


def clean_ad_spend() -> pd.DataFrame:
    df = pd.read_csv(RAW_AD_SPEND)
    df["date_id"] = pd.to_datetime(df["Date"]).dt.strftime("%Y-%m-%d")
    return df


def build_dim_date(all_dates: pd.Series) -> pd.DataFrame:
    unique_dates = pd.to_datetime(sorted(all_dates.unique()))
    return pd.DataFrame({
        "date_id": unique_dates.strftime("%Y-%m-%d"),
        "full_date": unique_dates.strftime("%Y-%m-%d"),
        "year": unique_dates.year,
        "quarter": unique_dates.quarter,
        "month": unique_dates.month,
        "month_name": unique_dates.strftime("%B"),
        "year_month": unique_dates.strftime("%Y-%m"),
        "day_of_week": unique_dates.strftime("%A"),
    })


def build_dim_customers(orders: pd.DataFrame) -> pd.DataFrame:
    def mode_or_first(s):
        m = s.mode()
        return m.iloc[0] if not m.empty else s.iloc[0]

    grouped = orders.groupby("Customer_ID").agg(
        country=("Country", mode_or_first),
        city=("Shipping_City", mode_or_first),
        first_order_date=("date_id", "min"),
    ).reset_index()
    grouped.columns = ["customer_id", "country", "city", "first_order_date"]
    return grouped


def build_dim_products(orders: pd.DataFrame) -> pd.DataFrame:
    products = (
        orders[["Product_Category", "Product_Name"]]
        .drop_duplicates()
        .reset_index(drop=True)
    )
    products.insert(0, "product_id", range(1, len(products) + 1))
    products.columns = ["product_id", "category", "product_name"]
    return products


def main():
    orders = clean_orders()
    ad_spend = clean_ad_spend()

    dim_date = build_dim_date(pd.concat([orders["date_id"], ad_spend["date_id"]]))
    dim_customers = build_dim_customers(orders)
    dim_products = build_dim_products(orders)

    orders = orders.merge(
        dim_products, left_on=["Product_Category", "Product_Name"],
        right_on=["category", "product_name"],
    )

    fact_orders = orders[[
        "Order_ID", "Customer_ID", "product_id", "date_id", "Quantity",
        "Unit_Price_USD", "Discount_Percent", "revenue_usd",
        "Payment_Method", "Order_Status", "Customer_Rating",
    ]].copy()
    fact_orders.columns = [
        "order_id", "customer_id", "product_id", "date_id", "quantity",
        "unit_price_usd", "discount_percent", "revenue_usd",
        "payment_method", "order_status", "customer_rating",
    ]

    fact_ad_spend = ad_spend[["date_id", "Product_Category", "Ad_Spend"]].copy()
    fact_ad_spend.columns = ["date_id", "category", "ad_spend_usd"]

    conn = sqlite3.connect(DB_PATH)
    with open(SCHEMA_PATH) as f:
        conn.executescript(f.read())

    dim_date.to_sql("dim_date", conn, if_exists="append", index=False)
    dim_customers.to_sql("dim_customers", conn, if_exists="append", index=False)
    dim_products.to_sql("dim_products", conn, if_exists="append", index=False)
    fact_orders.to_sql("fact_orders", conn, if_exists="append", index=False)
    fact_ad_spend.to_sql("fact_ad_spend", conn, if_exists="append", index=False)
    conn.commit()

    for table in ["dim_date", "dim_customers", "dim_products", "fact_orders", "fact_ad_spend"]:
        n = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"{table:16s} {n:>7,} rows")

    conn.close()


if __name__ == "__main__":
    main()
