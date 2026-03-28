// Supabase Edge Function — creates a Stripe Checkout session with server-side pricing
// Deploy: supabase functions deploy create-checkout
// Secrets: supabase secrets set STRIPE_SECRET_KEY=sk_live_...
//
// Optional secrets to override pricing without redeploying:
//   supabase secrets set BASE_FEE_GBP=35 PER_MILE_GBP=1.80 ROAD_FACTOR=1.30

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@14.0.0?target=deno";

// ── Pricing lives here, server-side only ─────────────────────────────────────
// The client never sends a price — we calculate it here so it cannot be tampered with.
const BASE_FEE  = parseFloat(Deno.env.get("BASE_FEE_GBP")  ?? "35");
const PER_MILE  = parseFloat(Deno.env.get("PER_MILE_GBP")  ?? "1.80");
const ROAD_FACTOR = parseFloat(Deno.env.get("ROAD_FACTOR") ?? "1.30");
// ─────────────────────────────────────────────────────────────────────────────

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2023-10-16",
  httpClient: Stripe.createFetchHttpClient(),
});

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Allowed redirect base URLs — must end without a trailing slash.
// Stripe success_url / cancel_url will only be built from these origins
// to prevent open-redirect phishing via a crafted siteUrl payload.
const ALLOWED_ORIGINS = [
  /^https:\/\/[\w-]+\.github\.io(\/[\w-]+)*$/,  // any GitHub Pages subdomain/path
  /^http:\/\/localhost(:\d+)?(\/.*)?$/,           // local development
  /^http:\/\/127\.0\.0\.1(:\d+)?(\/.*)?$/,        // local development (numeric)
];

function isSiteUrlAllowed(url: string): boolean {
  return ALLOWED_ORIGINS.some((re) => re.test(url));
}

// Fetch lat/lng from postcodes.io — free, no API key required
async function getLatLng(postcode: string): Promise<{ lat: number; lng: number }> {
  const clean = postcode.replace(/\s/g, "").toUpperCase();
  const res = await fetch(`https://api.postcodes.io/postcodes/${clean}`);
  if (!res.ok) throw new Error(`Postcode lookup failed for ${postcode}`);
  const json = await res.json();
  if (json.status !== 200) throw new Error(`Invalid postcode: ${postcode}`);
  return { lat: json.result.latitude, lng: json.result.longitude };
}

// Haversine formula — straight-line distance in miles
function haversine(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 3958.8;
  const rad = (x: number) => (x * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.asin(Math.sqrt(h));
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  try {
    const body = await req.json();
    const {
      customerName,
      customerEmail,
      bookingDate,
      pickupPostcode,
      deliveryPostcode,
      pickupTime,
      etaWindow,
      dimensions,
      weightKg,
      siteUrl,
    } = body;

    // ── Server-side price calculation — client value is intentionally ignored ──
    const [from, to] = await Promise.all([
      getLatLng(pickupPostcode),
      getLatLng(deliveryPostcode),
    ]);
    const straightLineMiles = haversine(from, to);
    const roadMiles         = straightLineMiles * ROAD_FACTOR;
    const totalGBP          = BASE_FEE + roadMiles * PER_MILE;
    const amountPence       = Math.round(totalGBP * 100);
    // ──────────────────────────────────────────────────────────────────────────

    if (amountPence < 100) throw new Error("Calculated amount is too low — check postcode inputs");

    // siteUrl is sent by the frontend and includes the subpath, e.g.
    // "https://username.github.io/manvan" — needed because the Origin header
    // alone only carries the hostname, not the repo subfolder.
    // We validate it against an allowlist to prevent open-redirect phishing.
    const rawSiteUrl = (siteUrl as string | undefined)?.replace(/\/$/, "");
    const originHeader = req.headers.get("origin") ?? "";
    const candidateUrl = rawSiteUrl ?? originHeader;

    if (!candidateUrl || !isSiteUrlAllowed(candidateUrl)) {
      return new Response(JSON.stringify({ error: "Invalid or disallowed siteUrl" }), {
        status: 400,
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    const baseUrl = candidateUrl;

    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card"],
      customer_email: customerEmail || undefined,
      line_items: [
        {
          price_data: {
            currency: "gbp",
            product_data: {
              name: "Weekend Courier Booking",
              description: [
                `Date: ${bookingDate}`,
                `Route: ${pickupPostcode} → ${deliveryPostcode}`,
                `Pickup: ${pickupTime} · Est. delivery: ${etaWindow}`,
                `Distance: ~${roadMiles.toFixed(1)} miles`,
              ].join(" | "),
            },
            unit_amount: amountPence,
          },
          quantity: 1,
        },
      ],
      mode: "payment",
      success_url: `${baseUrl}/success.html?session={CHECKOUT_SESSION_ID}`,
      cancel_url:  `${baseUrl}/`,
      metadata: {
        customer_name:     customerName ?? "",
        booking_date:      bookingDate,
        pickup_postcode:   pickupPostcode,
        delivery_postcode: deliveryPostcode,
        pickup_time:       pickupTime,
        eta_window:        etaWindow,
        length_cm:         String(dimensions?.lengthCm ?? ""),
        width_cm:          String(dimensions?.widthCm  ?? ""),
        height_cm:         String(dimensions?.heightCm ?? ""),
        weight_kg:         String(weightKg),
        distance_miles:    roadMiles.toFixed(1),
        total_gbp:         totalGBP.toFixed(2),
      },
    });

    return new Response(JSON.stringify({ url: session.url }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
