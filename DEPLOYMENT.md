# Deployment Guide — Weekend Courier Booking Page

## Cost summary

| Service | Free tier | Usage for this site |
|---|---|---|
| [GitHub Pages](https://pages.github.com) | Unlimited (public repo) | Hosts the static site |
| [Supabase](https://supabase.com/pricing) | 500k edge fn calls/month | ~2 calls per booking |
| [postcodes.io](https://postcodes.io) | Unlimited, no key needed | Distance calculation |
| [Stripe](https://stripe.com/gb/pricing) | No monthly fee | 1.4% + 20p per transaction (EU cards) |
| [Make](https://make.com/en/pricing) | 1,000 operations/month | 2 ops per booking = 500 bookings/month free |

**Running cost: £0/month.** Stripe takes a small cut per transaction — that comes out of revenue, not your pocket.

> **Supabase free-tier note:** free projects pause their *database* after 1 week of inactivity. The edge function still wakes and serves immediately — customers won't notice. If it bothers you, a single £0 "health-check" cron job (e.g. via [cron-job.org](https://cron-job.org), also free) hitting the function URL weekly keeps it warm.

---

## First-time setup (run once)

### Prerequisites

- A [GitHub account](https://github.com) (free)
- A [Supabase account](https://supabase.com) (free, no credit card)
- A [Stripe account](https://stripe.com) (free, pay-per-transaction)
- Node.js ≥18 **or** Homebrew (macOS) — needed to install the Supabase CLI

### 1. Create your Supabase project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard) → **New project**
2. Choose the **Free** plan — no credit card required
3. Note the **Project Ref** from the URL: `supabase.com/dashboard/project/YOUR_PROJECT_REF`

### 2. Get your Stripe secret key

1. Sign into [dashboard.stripe.com/apikeys](https://dashboard.stripe.com/apikeys)
2. Copy the **Secret key** (`sk_test_...` for testing, `sk_live_...` for live)
3. Fill in your bank account under **Settings → Business details** so payouts work

### 3. Create your GitHub repo and do the initial push

Create an empty repo on GitHub first — **the repo name becomes part of every URL you share with customers:**

```
https://YOUR_USERNAME.github.io/REPO_NAME/
```

Then push:

```bash
git init
git add .
git commit -m "Initial site"
git remote add origin https://github.com/YOUR_USERNAME/REPO_NAME.git
git push -u origin main
```

Then in the repo: **Settings → Pages → Source → Deploy from branch → main / root**

> **Tip:** keep the repo name short and lowercase — e.g. `manvan` or `johnsmith-courier`.

### 4. Run setup.sh

This script wires up Supabase automatically:

```bash
chmod +x setup.sh
./setup.sh
```

It will:
- Install the Supabase CLI if needed
- Log you into Supabase (opens browser)
- Link this folder to your project
- Store your Stripe secret key **encrypted inside Supabase** (never touches GitHub)
- Deploy the edge function
- Patch the `checkoutUrl` in `index.html` with your live function URL

Then push the patched `index.html`:

```bash
git add index.html
git commit -m "Add Supabase function URL"
git push
```

### 5. Add GitHub Actions secrets (for CI/CD)

So future pushes to `main` redeploy the edge function automatically:

**Settings → Secrets and variables → Actions → New repository secret**

| Secret name | Where to find it |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens) → New token |
| `SUPABASE_PROJECT_REF` | Your project ref from step 1 |

The Stripe key **does not go in GitHub** — it's already stored in Supabase.

---

## Infrastructure as code

The Supabase configuration lives in two committed files:

```
supabase/
  config.toml                        ← function settings (verify_jwt = false)
  functions/
    create-checkout/
      index.ts                       ← edge function source
.github/
  workflows/
    deploy.yml                       ← auto-deploys on push to main
```

To update pricing (base fee, per-mile rate) without touching code:

```bash
supabase secrets set BASE_FEE_GBP=40 --project-ref YOUR_PROJECT_REF
supabase secrets set PER_MILE_GBP=2.00 --project-ref YOUR_PROJECT_REF
```

---

## Going live checklist

**Infrastructure**
- [ ] Ran `./setup.sh` — Supabase linked, Stripe key stored, function deployed
- [ ] Added `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF` to GitHub repo secrets
- [ ] Pushed to GitHub and confirmed GitHub Pages is live

**Stripe**
- [ ] Stripe account set up with bank details for payouts
- [ ] Tested full booking flow in test mode (card `4242 4242 4242 4242`)
- [ ] Swapped in live key: `supabase secrets set STRIPE_SECRET_KEY=sk_live_... --project-ref YOUR_REF`

**Make → Google Calendar**
- [ ] Make account created and Scenario built (Stripe → Google Calendar)
- [ ] Stripe webhook registered with Make's URL and signing secret added to Make
- [ ] Test webhook sent and Google Calendar event confirmed
- [ ] Make scenario toggled **ON**

**Content**
- [ ] Added `hero.jpg` (landscape photo, compress to ≤500 KB at [squoosh.app](https://squoosh.app))
- [ ] Customised business name, phone, email, and reviews in the `const C = { … }` block in `index.html`
- [ ] Created `success.html` (see template below)

---

## Google Calendar sync via Make

When a customer pays, Make (formerly Integromat) catches the Stripe webhook and automatically creates a Google Calendar event for the driver. Free tier gives 1,000 operations/month — each booking uses 2 (one to receive the webhook, one to create the event), so you'd need 500 paid bookings a month before hitting the limit.

### How it works

```
Customer pays on site
  → Stripe fires a webhook
    → Make receives it
      → Make creates a Google Calendar event with all booking details
```

### Step 1 — Create a Make account

Sign up at [make.com](https://make.com) — free, no credit card needed. Choose the **Free** plan.

### Step 2 — Create a new Scenario

1. Dashboard → **Create a new scenario**
2. Click the large **+** in the centre of the canvas to add your first module

### Step 3 — Add the Stripe trigger

1. Search for **Stripe** and select it
2. Choose the trigger: **Watch Events**
3. Click **Add** to connect your Stripe account — Make will ask for your Stripe **Restricted key**:
   - In Stripe dashboard: **Developers → API keys → Create restricted key**
   - Give it a name (e.g. "Make read-only")
   - Under **Permissions**, enable **Read** access for **Checkout Sessions** only
   - Copy the key and paste it into Make
4. Back in Make, set **Event type** to: `checkout.session.completed`
5. Make will show you a **Webhook URL** — copy it (you'll paste it into Stripe next)

### Step 4 — Register the webhook in Stripe

1. Stripe dashboard → **Developers → Webhooks → Add endpoint**
2. **Endpoint URL**: paste the Make webhook URL from Step 3
3. **Events to send**: select `checkout.session.completed`
4. Click **Add endpoint**
5. Copy the **Signing secret** shown (`whsec_...`) — paste it back into the Make Stripe module's **Webhook secret** field

> The signing secret lets Make verify that webhooks genuinely came from Stripe and haven't been tampered with.

### Step 5 — Add the Google Calendar action

1. Click the **+** after the Stripe module to add a second module
2. Search for **Google Calendar** and select it
3. Choose action: **Create an Event**
4. Click **Add** to connect the driver's Google account — log in and grant calendar access
5. Select the calendar to write to (the driver's main calendar, or a dedicated "Bookings" one)

### Step 6 — Map the booking data

Fill in the Google Calendar event fields using values from the Stripe payload. In Make, values from previous modules are inserted by clicking into a field and selecting from the data picker.

| Calendar field | Value to map |
|---|---|
| **Summary (title)** | `📦 {{metadata.pickup_postcode}} → {{metadata.delivery_postcode}}` |
| **Start date & time** | `{{metadata.booking_date}}` + `T` + `{{metadata.pickup_time}}` + `:00` — see note below |
| **End date & time** | Start time + 12 hours (use Make's `addHours` function) |
| **Description** | See template below |
| **Color** | Pick anything distinctive — Teal works well |

**Start date formula** — click into the Start date field, switch to **formula mode**, and enter:
```
parseDate({{metadata.booking_date}} & "T" & {{metadata.pickup_time}} & ":00"; "YYYY-MM-DDTHH:mm:ss")
```

**End date formula:**
```
addHours(parseDate({{metadata.booking_date}} & "T" & {{metadata.pickup_time}} & ":00"; "YYYY-MM-DDTHH:mm:ss"); 12)
```

**Description template** — paste this into the Description field and use the data picker to replace each `{{…}}`:
```
Customer: {{metadata.customer_name}}
Email: {{customer_email}}

Route: {{metadata.pickup_postcode}} → {{metadata.delivery_postcode}}
Distance: ~{{metadata.distance_miles}} miles

Pickup: {{metadata.pickup_time}}
Est. delivery window: {{metadata.eta_window}}

Item dimensions: {{metadata.length_cm}}cm × {{metadata.width_cm}}cm × {{metadata.height_cm}}cm
Weight: {{metadata.weight_kg}} kg

Amount charged: £{{metadata.total_gbp}}
```

### Step 7 — Test it

1. In Make, click **Run once** — this puts the scenario into "listening" mode
2. In Stripe, use the **Send test webhook** button on your webhook endpoint
   (or complete a test payment with card `4242 4242 4242 4242`)
3. Make should show the run succeeded with a green tick on both modules
4. Check the driver's Google Calendar — the event should be there

### Step 8 — Activate

Toggle the scenario from **OFF** to **ON** in the bottom-left of the Make canvas. It will now run automatically on every real payment.

---

### Blocking off weekends

To mark a weekend as unavailable, the driver simply adds any event to Google Calendar for that day. **The website date picker doesn't check live availability** — weekdays are always blocked, weekends always appear free. Managing this is intentionally low-tech: the driver controls his own calendar.

---

### If Make ever goes away

The escape hatch is already in the stack. A second Supabase edge function pointed at by the Stripe webhook would do exactly the same job with no third-party dependency. The only extra piece is a Google service account (a JSON key stored as a Supabase secret). Migration would take about an hour and requires changing one URL in the Stripe webhook dashboard.

---

## Success page template

Create `success.html` in the repo root:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Booking Confirmed</title>
  <style>
    body { font-family: sans-serif; display: flex; align-items: center;
           justify-content: center; min-height: 100vh; background: #f8fafc; margin: 0; }
    .card { background: white; border-radius: 16px; padding: 2.5rem; text-align: center;
            max-width: 440px; width: 100%; box-shadow: 0 4px 24px rgba(0,0,0,.08); }
    h1 { color: #0f172a; margin-top: .5rem; }
    p { color: #475569; margin-top: .5rem; line-height: 1.6; }
    a { color: #f59e0b; font-weight: 600; text-decoration: none; }
  </style>
</head>
<body>
  <div class="card">
    <div style="font-size:3rem">✅</div>
    <h1>You're booked!</h1>
    <p>Payment received. A confirmation email is on its way.<br>
       We'll be in touch to confirm the details.</p>
    <p style="margin-top:1.5rem"><a href="/">← Back to home</a></p>
  </div>
</body>
</html>
```

---

## Looking up a booking in Stripe

Every booking confirmation page shows a 10-digit numeric reference (e.g. `0001234567`). This is derived from the underlying Stripe Checkout session ID. To find a booking:

1. Go to [Stripe Dashboard → Payments](https://dashboard.stripe.com/payments)
2. Use the search bar — search by **customer email**, **amount**, or **date** to find the payment
3. Click the payment — the full session ID is shown under **Payment details → Checkout session**
4. Alternatively, go to **Developers → Logs** and search by the session ID directly

The numeric ref is for the customer's convenience. The Stripe session ID (starting `cs_live_...`) is the authoritative record — it contains all booking metadata (route, date, dimensions, amount).

---

## Customisation reference

| Setting | File | Key |
|---|---|---|
| Business name, phone, email | `index.html` | `const C = { businessName, phone, email }` |
| Base fee | `index.html` (display) + Supabase secret | `C.baseFee` / `BASE_FEE_GBP` |
| Per-mile rate | `index.html` (display) + Supabase secret | `C.perMile` / `PER_MILE_GBP` |
| Van dimensions / weight limits | `index.html` | `C.maxLenCm`, `C.maxWidCm`, `C.maxHgtCm`, `C.maxWgtKg` |
| Pickup time window | `index.html` | `C.windowStart`, `C.windowEnd`, `C.slotMins` |
| Delivery ETA range | `index.html` | `C.etaMin`, `C.etaMax` |
| Reviews | `index.html` | `C.reviews` array |
| Restricted items list | `index.html` | `<ul>` inside the modal |
| Hero photo | repo root | `hero.jpg` |
