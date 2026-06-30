# Supply Chain Efficiency & Delivery Lead Time Optimization

SQL Server + Power BI analysis identifying a 6.8x Mid-Mile delivery bottleneck in North-East India logistics, with stage-level root cause analysis and business recommendations.

## Problem Statement

Shipments from Indian warehouses to North-East states were consistently delayed. The goal was to determine whether the bottleneck was at the Origin Warehouse, Mid-Mile Transit, or Last Mile delivery stage — and recommend a fix.

## Key Findings

| Metric | NE India | Metro | Gap |
|---|---|---|---|
| Avg Mid-Mile Transit | 109.3 hrs | 16.0 hrs | **6.8x slower** |
| Avg Warehouse Processing | 12.1 hrs | 4.5 hrs | 2.7x |
| Avg Last Mile | 51.3 hrs | 8.3 hrs | 6.2x |
| RTO (Return to Origin) Rate | 28% | 0% | — |
| Worst zones (RTO) | Aizawl & Imphal — 60% RTO | — | — |

**The bottleneck is Mid-Mile transit, not the warehouse.** Even the best-performing NE India shipment was 4x slower than the worst-performing Metro shipment.

## Methodology

1. **Database design** — SQL Server schema with 4 tables (Warehouses, Orders, Shipments, DeliveryZones), modeled on Delhivery's published zone-wise SLA benchmarks
2. **Stage-level lead time calculation** — T-SQL window functions (`DATEDIFF`, `RANK() OVER (PARTITION BY Region)`) to break total delivery time into 3 measurable stages
3. **Bottleneck analysis** — Aggregation queries to isolate which stage and which specific warehouses/zones were underperforming
4. **Visualization** — 3-page Power BI dashboard with DAX measures, region slicers, and zone-level drill-down
5. **Business reporting** — Executive presentation translating technical findings into prioritized recommendations

## Tech Stack

`SQL Server` `T-SQL` `SSMS 22` `Power BI` `DAX` `Canva`

## Files in this repo

- `schema_and_seed_data.sql` — Full database schema and seed data
- `lead_time_queries.sql` — Stage-level DATEDIFF and window function queries
- `bottleneck_analysis_queries.sql` — Aggregation queries for root cause analysis
- `dashboard_screenshots/` — Power BI dashboard pages
- `executive_summary.pdf` — 6-slide business presentation

## Key Insight

Not all NE India zones shared the same root cause. Aizawl and Imphal (60% RTO) reflect a geography constraint requiring hyperlocal delivery partners. WH-Siliguri-East had the highest RTO count despite average warehouse processing time — its problem was purely in Mid-Mile transit. Same region, two different root causes, two different solutions — a distinction only visible through stage-level analysis.

## Recommendations

1. Dedicated NE India transit hubs at Guwahati & Siliguri to reduce Mid-Mile average to under 48 hrs
2. Hyperlocal delivery partners for Aizawl & Imphal instead of national courier reliance
3. Real-time zone-wise SLA monitoring to catch delays before they become RTOs
4. RTO insurance negotiation with courier partners to offset reverse logistics cost

**Target: Reduce NE India RTO rate from 28% to under 10%**

---

*Data is synthetic, modeled on Delhivery's publicly available zone-wise SLA benchmarks. Built as a portfolio project to demonstrate end-to-end BI analysis methodology.*
