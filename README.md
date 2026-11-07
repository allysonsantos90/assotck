# AS Kitchen Stock — Demo Web App

A responsive, browser-based stock control prototype for kitchen and catering operations.

## Run it

1. Download and extract the ZIP file.
2. Open `index.html` in a modern browser (Chrome, Edge, Safari or Firefox).
3. No installation, Node.js or build process is required.

For local development, you can also run a simple static server from this folder:

```bash
python -m http.server 8000
```

Then open http://localhost:8000.

## Included in this prototype

- Dashboard with stock overview and low-stock alerts.
- Product catalogue with add/edit, categories, units, supplier and location assignments.
- Storage locations and supplier directory.
- Stock check workflow: count each product, explicitly mark zero by entering `0`, save counts, complete locations, and finish only when all locations are complete.
- Purchase needs calculated as `max(0, minimum stock - counted quantity)`.
- Consolidated draft purchase orders by supplier, with location allocations retained.
- Manual manager approval state; no supplier emails or orders are sent.
- Activity history.
- Local browser persistence using `localStorage`.

## Important limitations

This is a front-end prototype with sample data. Data is saved only in the browser/device where it is used. It has no login, shared database, multi-user sync, server-side audit log, live supplier integration, or production security. Do not enter confidential business data. A production release needs a backend (for example Supabase/PostgreSQL), authentication, role-based access and database policies.

## Product location IDs for sample setup

`freezer`, `fridge`, `dry`, `prep`, `cold`, `other`

When adding a product, assign existing location IDs and enter minimums in the format `fridge:5, dry:10`.
