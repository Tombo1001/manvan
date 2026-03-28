#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup.sh — one-time Supabase + Stripe wiring for the Man & Van booking site
#
# Run once after cloning, before pushing to GitHub:
#   chmod +x setup.sh && ./setup.sh
#
# What it does:
#   1. Checks / installs the Supabase CLI
#   2. Logs you into Supabase
#   3. Links this folder to your Supabase project
#   4. Sets the Stripe secret key as a Supabase encrypted secret
#   5. Deploys the edge function
#   6. Patches the checkoutUrl in index.html automatically
# ─────────────────────────────────────────────────────────────────────────────
set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # no colour

info()    { echo -e "${GREEN}▶${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
heading() { echo -e "\n${BOLD}$*${NC}"; }
die()     { echo -e "${RED}✗  $*${NC}"; exit 1; }

# ── 1. Supabase CLI ───────────────────────────────────────────────────────────
heading "Step 1 — Supabase CLI"

if ! command -v supabase &>/dev/null; then
  warn "Supabase CLI not found. Installing via npm..."
  if command -v npm &>/dev/null; then
    npm install -g supabase
  elif command -v brew &>/dev/null; then
    brew install supabase/tap/supabase
  else
    die "Neither npm nor Homebrew found. Install the Supabase CLI manually:\n  https://supabase.com/docs/guides/cli/getting-started"
  fi
fi

SUPA_VER=$(supabase --version 2>&1 | head -1)
info "Supabase CLI ready ($SUPA_VER)"

# ── 2. Login ──────────────────────────────────────────────────────────────────
heading "Step 2 — Supabase login"
echo "This will open your browser to authenticate."
echo "If you don't have a Supabase account, create a free one at https://supabase.com"
echo ""
supabase login
info "Logged in."

# ── 3. Project ref ───────────────────────────────────────────────────────────
heading "Step 3 — Link your Supabase project"
echo ""
echo "  Create a project at https://supabase.com/dashboard → New project"
echo "  (free tier, no credit card needed)"
echo ""
echo "  Your project ref is the ID in the dashboard URL:"
echo "  https://supabase.com/dashboard/project/YOUR_PROJECT_REF"
echo ""
read -rp "  Paste your project ref: " PROJECT_REF
[[ -z "$PROJECT_REF" ]] && die "Project ref cannot be empty."

supabase link --project-ref "$PROJECT_REF"
info "Linked to project: $PROJECT_REF"

# ── 4. Stripe secret ─────────────────────────────────────────────────────────
heading "Step 4 — Stripe secret key"
echo ""
echo "  Get your secret key from https://dashboard.stripe.com/apikeys"
echo "  Use sk_test_... for testing, sk_live_... when going live."
echo "  (This key is stored encrypted inside Supabase — it never touches GitHub)"
echo ""
read -rsp "  Paste your Stripe secret key (input hidden): " STRIPE_KEY
echo ""
[[ -z "$STRIPE_KEY" ]] && die "Stripe key cannot be empty."
[[ "$STRIPE_KEY" != sk_* ]] && warn "Key doesn't start with 'sk_' — double-check it."

supabase secrets set STRIPE_SECRET_KEY="$STRIPE_KEY" --project-ref "$PROJECT_REF"
info "Stripe secret stored in Supabase."

# ── Optional pricing overrides ────────────────────────────────────────────────
echo ""
read -rp "  Override base fee in GBP? (press Enter to keep default £35): " BASE_FEE
read -rp "  Override per-mile rate in GBP? (press Enter to keep default £1.80): " PER_MILE

if [[ -n "$BASE_FEE" || -n "$PER_MILE" ]]; then
  EXTRA_SECRETS=""
  [[ -n "$BASE_FEE"  ]] && EXTRA_SECRETS+=" BASE_FEE_GBP=$BASE_FEE"
  [[ -n "$PER_MILE"  ]] && EXTRA_SECRETS+=" PER_MILE_GBP=$PER_MILE"
  # shellcheck disable=SC2086
  supabase secrets set $EXTRA_SECRETS --project-ref "$PROJECT_REF"
  info "Pricing secrets stored."
fi

# ── 5. Deploy function ────────────────────────────────────────────────────────
heading "Step 5 — Deploy edge function"
supabase functions deploy create-checkout --no-verify-jwt --project-ref "$PROJECT_REF"
info "Function deployed."

FUNCTION_URL="https://${PROJECT_REF}.supabase.co/functions/v1/create-checkout"
info "Function URL: $FUNCTION_URL"

# ── 6. Patch index.html ───────────────────────────────────────────────────────
heading "Step 6 — Update index.html"

INDEX="$(dirname "$0")/index.html"
if [[ -f "$INDEX" ]]; then
  # Replace the placeholder checkoutUrl value
  sed -i.bak \
    "s|checkoutUrl:.*|checkoutUrl: \"$FUNCTION_URL\",|" \
    "$INDEX" && rm -f "${INDEX}.bak"
  info "index.html updated with your function URL."
else
  warn "index.html not found at $INDEX — update checkoutUrl manually:"
  echo "  checkoutUrl: \"$FUNCTION_URL\","
fi

# ── 7. GitHub Actions secrets reminder ───────────────────────────────────────
heading "Step 7 — GitHub repository secrets (for CI/CD)"
echo ""
echo "  So future pushes auto-redeploy the function, add these two secrets"
echo "  to your GitHub repo (Settings → Secrets and variables → Actions):"
echo ""
echo "    SUPABASE_ACCESS_TOKEN  — from https://supabase.com/dashboard/account/tokens"
echo "    SUPABASE_PROJECT_REF   — $PROJECT_REF"
echo ""
echo "  The Stripe key does NOT go in GitHub — it's already safe in Supabase."

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✓ All done!${NC}"
echo ""
echo "  Next steps:"
echo "  1. Push this repo to GitHub and enable Pages (Settings → Pages → main / root)"
echo "     Your site will be live at: https://YOUR_USERNAME.github.io/REPO_NAME/"
echo "  2. Add SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF to GitHub repo secrets"
echo "     (Settings → Secrets and variables → Actions)"
echo "  3. Test end-to-end using your Stripe test key (sk_test_...) and card 4242 4242 4242 4242"
echo "  4. Swap in your live key when ready:"
echo "     supabase secrets set STRIPE_SECRET_KEY=sk_live_... --project-ref $PROJECT_REF"
echo ""
